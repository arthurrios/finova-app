package com.arthurrios.finova.domain.importer

import java.time.DateTimeException
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import kotlin.math.max

/**
 * One way of spelling a date, in the iOS `DateFormatter` pattern language (the spelling is stored in
 * the batch's column mapping and shown on the mapping screen). [localeId] matters only for month names.
 */
data class DateFormatSpec(val pattern: String, val localeId: String = "en_US_POSIX") {
    companion object {
        /** Ordered roughly by how often they appear, so the first hit is usually the answer. */
        val Candidates = listOf(
            DateFormatSpec("dd/MM/yyyy"),
            DateFormatSpec("yyyy-MM-dd"),
            DateFormatSpec("MM/dd/yyyy"),
            DateFormatSpec("dd-MM-yyyy"),
            DateFormatSpec("dd.MM.yyyy"),
            DateFormatSpec("dd/MM/yy"),
            DateFormatSpec("yyyy/MM/dd"),
            DateFormatSpec("dd/MM/yyyy HH:mm"),
            DateFormatSpec("dd/MM/yyyy HH:mm:ss"),
            DateFormatSpec("yyyy-MM-dd HH:mm:ss"),
            DateFormatSpec("yyyy-MM-dd'T'HH:mm:ssZ"),
            DateFormatSpec("yyyy-MM-dd'T'HH:mm:ss"),
            DateFormatSpec("d 'de' MMMM 'de' yyyy", "pt_BR"),
            DateFormatSpec("dd MMM yyyy", "pt_BR"),
            DateFormatSpec("dd MMM yyyy", "en_US_POSIX"),
        )
        val DayFirst = DateFormatSpec("dd/MM/yyyy")
        val MonthFirst = DateFormatSpec("MM/dd/yyyy")
    }
}

/**
 * Text to a calendar day. Port of DateFieldParser.swift. Android keeps dates as [LocalDate], so the
 * iOS noon anchoring (against Brazil's old midnight DST gaps) has nothing to guard here.
 *
 * Hand-rolled over the pattern instead of `DateTimeFormatter`: inference tries fifteen patterns on
 * every cell of every column, and a formatter answers each miss with an exception, which turns a
 * two-thousand-row file into seconds of work. Numeric fields take one or two digits like ICU does
 * ("1/7/2026"), years take exactly their width, and a field out of range fails the whole cell.
 */
object DateFieldParser {
    private const val EARLIEST_YEAR = 1980
    private const val LATEST_YEAR_OFFSET = 5

    /** The current year, for plausibility and two-digit years. A seam for tests. */
    var currentYear: () -> Int = { LocalDate.now().year }

    fun parse(raw: String, spec: DateFormatSpec): LocalDate? {
        val text = raw.trim()
        if (text.isEmpty()) return null
        val date = Matcher(text, spec).run() ?: return null
        val year = date.year
        return if (year >= EARLIEST_YEAR && year <= currentYear() + LATEST_YEAR_OFFSET) date else null
    }

    // ---- Format detection ----------------------------------------------------------------------

    sealed interface Detection {
        /** A component above 12 settled it, or only one candidate parsed at all. */
        data class Proven(val spec: DateFormatSpec) : Detection
        /** Both readings parse; the ordering test broke the tie. */
        data class Likely(val spec: DateFormatSpec, val alternative: DateFormatSpec) : Detection
        /** Both readings are equally defensible. Ask. */
        data class Ambiguous(val first: DateFormatSpec, val second: DateFormatSpec) : Detection
        /** One row proves dd/MM and another MM/dd. */
        data object Inconsistent : Detection
        data object None : Detection
    }

    fun detectFormat(values: List<String>): Detection {
        val samples = values.map { it.trim() }.filter { it.isNotEmpty() }
        if (samples.isEmpty()) return Detection.None

        // Contradiction first: a file where one row proves dd/MM and another MM/dd makes neither
        // reading viable, and a viability check alone would call it unrecognised.
        var dayFirstProof = false
        var monthFirstProof = false
        for (sample in samples) {
            val parts = sample.split('/', '-', '.').filter { it.isNotEmpty() }
            if (parts.size < 2 || parts[0].length > 2) continue
            val first = parts[0].toIntOrNull() ?: continue
            val second = parts[1].toIntOrNull() ?: continue
            if (first > 12) dayFirstProof = true
            if (second > 12) monthFirstProof = true
        }
        if (dayFirstProof && monthFirstProof) return Detection.Inconsistent

        // Formats that parse EVERY sample: partial success imports three quarters of a statement.
        val viable = DateFormatSpec.Candidates.filter { spec -> samples.all { parse(it, spec) != null } }
        if (viable.isEmpty()) return Detection.None
        if (dayFirstProof && DateFormatSpec.DayFirst in viable) return Detection.Proven(DateFormatSpec.DayFirst)
        if (monthFirstProof && DateFormatSpec.MonthFirst in viable) return Detection.Proven(DateFormatSpec.MonthFirst)

        val bothSlash = DateFormatSpec.DayFirst in viable && DateFormatSpec.MonthFirst in viable
        if (!bothSlash) return Detection.Proven(viable.first())

        // Genuinely ambiguous. A statement is date-ordered over a bounded window, so prefer the reading
        // that is. Below eight rows that proves nothing.
        if (samples.size < 8) return Detection.Ambiguous(DateFormatSpec.DayFirst, DateFormatSpec.MonthFirst)
        val day = monotonicityScore(samples, DateFormatSpec.DayFirst)
        val month = monotonicityScore(samples, DateFormatSpec.MonthFirst)
        return when {
            day > month + 0.15 -> Detection.Likely(DateFormatSpec.DayFirst, DateFormatSpec.MonthFirst)
            month > day + 0.15 -> Detection.Likely(DateFormatSpec.MonthFirst, DateFormatSpec.DayFirst)
            else -> Detection.Ambiguous(DateFormatSpec.DayFirst, DateFormatSpec.MonthFirst)
        }
    }

    /** How much a reading behaves like a statement: in order, over a tight span (not a year of 1sts). */
    private fun monotonicityScore(samples: List<String>, spec: DateFormatSpec): Double {
        val dates = samples.mapNotNull { parse(it, spec) }
        if (dates.size < 2) return 0.0
        val pairs = dates.zipWithNext()
        val ascending = pairs.count { (a, b) -> a <= b }
        val descending = pairs.count { (a, b) -> a >= b }
        val ordered = max(ascending, descending).toDouble() / (dates.size - 1)
        val span = ChronoUnit.DAYS.between(dates.min(), dates.max()).toDouble()
        val spanScore = max(0.0, 1.0 - span / 400)
        return ordered * 0.6 + spanScore * 0.4
    }

    // ---- Dates fused into a description column -------------------------------------------------

    data class LeadingDate(val date: LocalDate, val remainder: String, val spec: DateFormatSpec)

    /**
     * The longest leading run of words that parses as a date, plus what follows. Several Brazilian
     * banks put `15/07/2026 14:30 COMPRA MERCADO` in one "Lançamentos" column; longest-first keeps the
     * `14:30` out of the title.
     */
    fun parseLeadingDate(raw: String): LeadingDate? {
        val tokens = raw.trim().split(' ').filter { it.isNotEmpty() }
        if (tokens.isEmpty()) return null
        for (length in minOf(4, tokens.size) downTo 1) {
            val candidate = tokens.take(length).joinToString(" ")
            for (spec in DateFormatSpec.Candidates) {
                val date = parse(candidate, spec) ?: continue
                return LeadingDate(date, tokens.drop(length).joinToString(" "), spec)
            }
        }
        return null
    }

    /** How much of a column begins with a date. Sampled: the most expensive probe in inference. */
    fun leadingDateHitRate(values: List<String>, sample: Int = 60): Double {
        val candidates = values.map { it.trim() }.filter { it.isNotEmpty() }.take(sample)
        if (candidates.isEmpty()) return 0.0
        return candidates.count { parseLeadingDate(it) != null }.toDouble() / candidates.size
    }

    /** The date prefixes of a fused column, so [detectFormat] can run on them. */
    fun leadingDateTexts(values: List<String>): List<String> = values.mapNotNull { value ->
        val trimmed = value.trim()
        val parsed = parseLeadingDate(trimmed) ?: return@mapNotNull null
        if (parsed.remainder.isEmpty()) trimmed else trimmed.dropLast(parsed.remainder.length).trim()
    }

    /** Whether a column looks like dates at all, for profiling. */
    fun dateHitRate(values: List<String>): Double {
        val samples = values.map { it.trim() }.filter { it.isNotEmpty() }
        if (samples.isEmpty()) return 0.0
        val best = DateFormatSpec.Candidates.maxOf { spec -> samples.count { parse(it, spec) != null } }
        return best.toDouble() / samples.size
    }

    // ---- The pattern matcher -------------------------------------------------------------------

    private val MonthsPt = listOf("janeiro", "fevereiro", "marco", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro")
    private val MonthsEn = listOf("january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december")
    private val ShortPt = listOf("jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez")
    private val ShortEn = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")

    private class Matcher(private val text: String, private val spec: DateFormatSpec) {
        private var pos = 0
        private var day = -1
        private var month = -1
        private var year = -1
        private var hour = 0
        private var minute = 0
        private var second = 0
        private var offset: ZoneOffset? = null

        fun run(): LocalDate? {
            val pattern = spec.pattern
            var i = 0
            while (i < pattern.length) {
                val c = pattern[i]
                if (c == '\'') {
                    val end = pattern.indexOf('\'', i + 1).takeIf { it > i } ?: return null
                    if (!literal(pattern.substring(i + 1, end), ignoreCase = true)) return null
                    i = end + 1
                    continue
                }
                if (c.isLetter()) {
                    var j = i
                    while (j < pattern.length && pattern[j] == c) j++
                    if (!field(c, j - i)) return null
                    i = j
                    continue
                }
                if (pos >= text.length || text[pos] != c) return null
                pos++
                i++
            }
            if (pos != text.length || day < 0 || month < 0 || year < 0) return null
            return try {
                val local = LocalDateTime.of(year, month, day, hour, minute, second)
                val zone = offset
                // A timestamp with an offset lands on the phone's own calendar day, as on iOS.
                if (zone == null) local.toLocalDate()
                else local.atOffset(zone).atZoneSameInstant(ZoneId.systemDefault()).toLocalDate()
            } catch (_: DateTimeException) {
                null
            }
        }

        private fun literal(value: String, ignoreCase: Boolean): Boolean {
            if (!text.regionMatches(pos, value, 0, value.length, ignoreCase)) return false
            pos += value.length
            return true
        }

        private fun digits(min: Int, maxCount: Int): Int? {
            var end = pos
            while (end < text.length && end - pos < maxCount && text[end] in '0'..'9') end++
            if (end - pos < min) return null
            // A field followed by yet another digit was longer than it may be.
            if (end < text.length && text[end] in '0'..'9') return null
            val value = text.substring(pos, end).toInt()
            pos = end
            return value
        }

        private fun field(letter: Char, count: Int): Boolean = when (letter) {
            'd' -> digits(1, 2)?.also { day = it } != null
            'M' -> when {
                count >= 4 -> monthName(if (spec.localeId.startsWith("pt")) MonthsPt else MonthsEn)
                count == 3 -> monthName(if (spec.localeId.startsWith("pt")) ShortPt else ShortEn).also { if (it && pos < text.length && text[pos] == '.') pos++ }
                else -> digits(1, 2)?.also { month = it } != null
            }
            'y' -> if (count == 2) {
                digits(2, 2)?.also { year = twoDigitYear(it) } != null
            } else {
                digits(4, 4)?.also { year = it } != null
            }
            'H' -> digits(1, 2)?.also { hour = it } != null
            'm' -> digits(2, 2)?.also { minute = it } != null
            's' -> digits(2, 2)?.also { second = it } != null
            'Z' -> zoneOffset()
            else -> false
        }

        /** Month names match accent- and case-folded, so "Março", "MARCO" and "março" all read. */
        private fun monthName(names: List<String>): Boolean {
            val rest = text.substring(pos).normalizedForSearch()
            val match = names.withIndex().filter { rest.startsWith(it.value) }.maxByOrNull { it.value.length } ?: return false
            month = match.index + 1
            pos += match.value.length
            return true
        }

        /** "Z", "+0000" or "+00:00". */
        private fun zoneOffset(): Boolean {
            if (pos < text.length && (text[pos] == 'Z' || text[pos] == 'z')) {
                offset = ZoneOffset.UTC
                pos++
                return true
            }
            if (pos >= text.length || (text[pos] != '+' && text[pos] != '-')) return false
            val sign = if (text[pos] == '-') -1 else 1
            pos++
            val hours = digits(2, 2) ?: return false
            if (pos < text.length && text[pos] == ':') pos++
            val minutes = digits(2, 2) ?: return false
            return try {
                offset = ZoneOffset.ofHoursMinutes(sign * hours, sign * minutes)
                true
            } catch (_: DateTimeException) {
                false
            }
        }

        /** Two-digit years resolve into the 80 years before and 20 after now, as ICU does. */
        private fun twoDigitYear(value: Int): Int {
            val start = currentYear() - 80
            val century = start - start % 100
            val candidate = century + value
            return if (candidate < start) candidate + 100 else candidate
        }
    }
}
