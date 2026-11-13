package com.arthurrios.finova.domain.importer

import kotlin.math.log2
import kotlin.math.min

/** How one particular file spells "CSV". Port of CSVDialect.swift. */
data class CsvDialect(val delimiter: Char, val quote: Char = '"') {
    val displayName: String get() = if (delimiter == '\t') "tab" else delimiter.toString()

    companion object {
        /**
         * In the order the sniffer scores them. Semicolon leads because it is what every Brazilian
         * bank emits: a comma cannot be the delimiter where it is also the decimal separator.
         */
        val CandidateDelimiters = listOf(';', ',', '\t', '|')
        val Semicolon = CsvDialect(';')
    }
}

/** A row of strings, from a CSV or a workbook. [line] is 1-based in the source file. */
data class SourceRow(val line: Int, val cells: List<String>)

/**
 * RFC 4180, plus the ways real banks break it. Port of CSVTokenizer.swift: a ragged row (the `Saldo`
 * line at the end of most statements) costs that line only, and every error carries a line number.
 */
object CsvTokenizer {
    const val DEFAULT_MAX_ROWS = 50_000

    fun tokenize(text: String, dialect: CsvDialect, maxRows: Int = DEFAULT_MAX_ROWS): List<SourceRow> {
        val delimiter = dialect.delimiter
        val quote = dialect.quote
        val rows = mutableListOf<SourceRow>()
        var cells = mutableListOf<String>()
        val field = StringBuilder()
        // Trailing whitespace held back rather than appended, so ` "value" ` unquotes cleanly but a
        // genuine internal space in an unquoted field is kept.
        val pendingSpaces = StringBuilder()
        var index = 0
        var line = 1
        var rowStartLine = 1
        var inQuotes = false

        fun endField() {
            // Held-back spaces are dropped here: they were trailing padding.
            pendingSpaces.setLength(0)
            cells.add(field.toString())
            field.setLength(0)
        }

        fun endRow() {
            endField()
            // A blank line is structure, not data. Banks pad with them freely.
            if (!(cells.size == 1 && cells[0].isEmpty())) {
                if (rows.size >= maxRows) throw ImportError.TooManyRows(rows.size + 1, maxRows)
                rows.add(SourceRow(rowStartLine, cells))
            }
            cells = mutableListOf()
            rowStartLine = line
        }

        while (index < text.length) {
            val c = text[index]
            if (inQuotes) {
                when {
                    c == quote -> {
                        // A doubled quote is one literal quote; a single one closes the field.
                        if (index + 1 < text.length && text[index + 1] == quote) {
                            field.append(quote); index += 2; continue
                        }
                        inQuotes = false
                    }
                    // Newlines inside quotes are content, but still move the line counter.
                    c == '\n' -> { line++; field.append(c) }
                    c == '\r' -> {
                        if (index + 1 < text.length && text[index + 1] == '\n') index++
                        line++
                        field.append('\n')
                    }
                    else -> field.append(c)
                }
                index++
                continue
            }
            when {
                c == quote && field.isEmpty() -> {
                    // Whitespace before an opening quote is not RFC-legal; banks do it anyway.
                    pendingSpaces.setLength(0)
                    inQuotes = true
                }
                c == delimiter -> endField()
                c == '\r' -> {
                    if (index + 1 < text.length && text[index + 1] == '\n') index++
                    line++
                    endRow()
                }
                c == '\n' -> { line++; endRow() }
                c == ' ' || (c == '\t' && delimiter != '\t') -> if (field.isNotEmpty()) pendingSpaces.append(c)
                else -> {
                    field.append(pendingSpaces)
                    pendingSpaces.setLength(0)
                    field.append(c)
                }
            }
            index++
        }

        if (inQuotes) throw ImportError.UnterminatedQuote(rowStartLine)
        // A file with no trailing newline still has a final row.
        if (field.isNotEmpty() || pendingSpaces.isNotEmpty() || cells.isNotEmpty()) endRow()
        return rows
    }

    /**
     * The most common field count, and the share of rows that have it. Ties break toward the wider
     * shape: half 2-field and half 5-field rows is far likelier a 5-column file with preamble.
     */
    fun modalFieldCount(rows: List<SourceRow>): Pair<Int, Double> {
        if (rows.isEmpty()) return 0 to 0.0
        val histogram = rows.groupingBy { it.cells.size }.eachCount()
        val best = histogram.entries.maxWith(compareBy<Map.Entry<Int, Int>> { it.value }.thenBy { it.key })
        return best.key to best.value.toDouble() / rows.size
    }
}

/** Picks the delimiter by tokenizing a sample with each candidate. Port of DelimiterSniffer.swift. */
object DelimiterSniffer {
    data class Detection(val dialect: CsvDialect, val skipLeadingLines: Int, val confidence: Double)

    fun sniff(text: String): Detection {
        // Excel writes `sep=;` as a first line: a declaration, and it wins outright.
        declaredSeparator(text)?.let { return Detection(CsvDialect(it), 1, 1.0) }

        val sample = sample(text)
        var best: Triple<CsvDialect, Double, Int>? = null
        for (candidate in CsvDialect.CandidateDelimiters) {
            val dialect = CsvDialect(candidate)
            // Scored on TOKENIZED output, so a delimiter inside a quoted description does not count.
            val rows = runCatching { CsvTokenizer.tokenize(sample, dialect, maxRows = 500) }.getOrNull()
            if (rows.isNullOrEmpty()) continue
            val (columns, matchFraction) = CsvTokenizer.modalFieldCount(rows)
            // A single column means the delimiter never appeared: absence, not evidence.
            if (columns < 2) continue
            // Consistency matters more than width; width breaks ties, gently.
            val score = matchFraction * log2(columns.toDouble())
            if (best == null || score > best.second) best = Triple(dialect, score, columns)
        }
        // Nothing produced structure. Semicolon is the likeliest here, and the mapping screen asks anyway.
        val winner = best ?: return Detection(CsvDialect.Semicolon, 0, 0.0)

        // The pt-BR tie-break: `;` and `,` score the same whenever a description holds a comma, and
        // the decimal separator settles it, because a comma cannot be both.
        var chosen = winner.first
        if ((chosen.delimiter == ',' || chosen.delimiter == ';') && commaDecimalCount(sample) > dotDecimalCount(sample)) {
            chosen = CsvDialect.Semicolon
        }
        return Detection(chosen, 0, min(1.0, winner.second / 3.0))
    }

    private fun declaredSeparator(text: String): Char? {
        val first = text.substringBefore('\n').trim()
        if (!first.lowercase().startsWith("sep=") || first.length != 5) return null
        return first.last()
    }

    private val CommaDecimal = Regex("""\d,\d{2}(?!\d)""")
    private val DotDecimal = Regex("""\d\.\d{2}(?!\d)""")

    fun commaDecimalCount(text: String) = CommaDecimal.findAll(text).count()
    fun dotDecimalCount(text: String) = DotDecimal.findAll(text).count()

    /** The first 200 lines: enough to establish shape, bounded for a 10 MB file. */
    private fun sample(text: String): String = text.split('\n').take(200).joinToString("\n")
}
