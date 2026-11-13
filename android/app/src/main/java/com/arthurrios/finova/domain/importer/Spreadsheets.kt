package com.arthurrios.finova.domain.importer

import org.xml.sax.Attributes
import org.xml.sax.helpers.DefaultHandler
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.time.LocalDate
import java.util.zip.ZipInputStream
import javax.xml.parsers.SAXParserFactory
import kotlin.math.floor
import kotlin.math.roundToInt

sealed class SpreadsheetError : Exception() {
    data object NotAWorkbook : SpreadsheetError()
    data object NoSheets : SpreadsheetError()
    data object EmptyWorkbook : SpreadsheetError()
    data class Corrupt(val detail: String) : SpreadsheetError()
    data object Encrypted : SpreadsheetError()
}

/**
 * Workbooks in, the same rows of strings the CSV path makes out. Port of SpreadsheetReader.swift.
 * Cells are handed over as the STRINGS a person would see, so dates and amounts go through the one
 * CSV parser and its one set of edge cases.
 */
object SpreadsheetImporter {
    fun canRead(data: ByteArray) = XlsxReader.canRead(data) || XlsReader.canRead(data)

    fun read(data: ByteArray): List<SourceRow> = when {
        XlsxReader.canRead(data) -> XlsxReader.read(data)
        XlsReader.canRead(data) -> XlsReader.read(data)
        else -> throw SpreadsheetError.NotAWorkbook
    }
}

internal object SpreadsheetCell {
    /**
     * Excel serial to a day. Excel believes 1900 was a leap year (a bug kept from Lotus 1-2-3), so
     * serials from 60 on are one day ahead; getting it wrong shifts every date in the file.
     */
    fun date(serial: Double): LocalDate? {
        if (serial <= 0 || serial >= 2_958_466) return null
        val corrected = if (serial >= 60) serial - 1 else serial
        return LocalDate.of(1899, 12, 31).plusDays(floor(corrected).toLong())
    }

    /** `dd/MM/yyyy`, a shape the date detection can prove, plus the time when the serial has one. */
    fun displayDate(serial: Double, includesTime: Boolean): String? {
        val date = date(serial) ?: return null
        val day = "%02d/%02d/%04d".format(date.dayOfMonth, date.monthValue, date.year)
        if (!includesTime) return day
        val minutes = ((serial - floor(serial)) * 24 * 60).roundToInt()
        return "%s %02d:%02d".format(day, minutes / 60, minutes % 60)
    }

    /** A POSIX decimal point and no grouping, so the importer reads it as en-US and gets it right. */
    fun displayNumber(value: Double): String {
        if (value == floor(value) && kotlin.math.abs(value) < 1e15) return value.toLong().toString()
        return java.math.BigDecimal(value).round(java.math.MathContext(10)).stripTrailingZeros().toPlainString()
    }

    /** Built-in number formats 14-22 and 45-47 are dates and times; custom ones (164+) are read by code. */
    val BuiltInDateFormats = (14..22).toSet() + (45..47).toSet()

    /** Date tokens outside quoted literal text: `"y"0.00` is a currency format, not a year. */
    fun looksTemporal(code: String): Boolean {
        var inQuotes = false
        for (c in code) {
            if (c == '"') { inQuotes = !inQuotes; continue }
            if (!inQuotes && c in "yYmMdDhHsS") return true
        }
        return false
    }
}

/**
 * `.xlsx` into rows. Port of XLSXReader.swift: text cells are indexes into `sharedStrings.xml`, a
 * date is a number whose style points at a date format, and empty cells are ABSENT from the XML, so
 * columns are rebuilt from each cell's reference (`BC7`).
 */
internal object XlsxReader {
    fun canRead(data: ByteArray): Boolean {
        if (data.size <= 4 || FileFormatSniffer.detect(data) != DetectedFileFormat.ZipContainer) return false
        val names = runCatching { entries(data, wanted = { false }).keys }.getOrNull() ?: return false
        return "[Content_Types].xml" in names && names.any { it.startsWith("xl/worksheets/") }
    }

    fun read(data: ByteArray): List<SourceRow> {
        val files = try {
            entries(data, wanted = { it == "xl/sharedStrings.xml" || it == "xl/styles.xml" || (it.startsWith("xl/worksheets/sheet") && it.endsWith(".xml")) })
        } catch (e: Exception) {
            throw SpreadsheetError.Corrupt("not a readable archive")
        }
        val shared = files["xl/sharedStrings.xml"]?.let(::sharedStrings).orEmpty()
        val dateStyles = files["xl/styles.xml"]?.let(::dateStyles).orEmpty()
        // sheet2 before sheet10.
        val sheets = files.keys.filter { it.startsWith("xl/worksheets/sheet") }
            .sortedWith(compareBy<String> { it.filter(Char::isDigit).toIntOrNull() ?: Int.MAX_VALUE }.thenBy { it })
        if (sheets.isEmpty()) throw SpreadsheetError.NoSheets
        // The first sheet that holds data: banks often lead with a cover sheet.
        for (name in sheets) {
            val rows = sheet(files.getValue(name), shared, dateStyles)
            if (rows.size >= 2) return rows
        }
        throw SpreadsheetError.EmptyWorkbook
    }

    /** Every entry name, with the bytes of the ones [wanted]. */
    private fun entries(data: ByteArray, wanted: (String) -> Boolean): Map<String, ByteArray?> {
        val result = linkedMapOf<String, ByteArray?>()
        ZipInputStream(ByteArrayInputStream(data)).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                result[entry.name] = if (wanted(entry.name)) zip.readBytes() else null
            }
        }
        return result
    }

    private fun parse(bytes: ByteArray?, handler: DefaultHandler) {
        if (bytes == null) return
        val factory = SAXParserFactory.newInstance().apply { isNamespaceAware = false }
        factory.newSAXParser().parse(ByteArrayInputStream(bytes), handler)
    }

    /** Each `<si>` is one string; mixed formatting splits it into several `<t>` runs, concatenated. */
    private fun sharedStrings(bytes: ByteArray?): List<String> {
        val strings = mutableListOf<String>()
        parse(bytes, object : DefaultHandler() {
            var current: StringBuilder? = null
            var capturing = false
            override fun startElement(uri: String?, localName: String?, qName: String, attributes: Attributes) {
                if (qName == "si") current = StringBuilder()
                if (qName == "t") capturing = true
            }
            override fun characters(ch: CharArray, start: Int, length: Int) {
                if (capturing) current?.append(ch, start, length)
            }
            override fun endElement(uri: String?, localName: String?, qName: String) {
                if (qName == "t") capturing = false
                if (qName == "si") { strings += current?.toString().orEmpty(); current = null }
            }
        })
        return strings
    }

    /** Indexes into `cellXfs` whose number format is a date: cell `s="3"` means style 3. */
    private fun dateStyles(bytes: ByteArray?): Set<Int> {
        val custom = mutableMapOf<Int, String>()
        val cellFormats = mutableListOf<Int>()
        parse(bytes, object : DefaultHandler() {
            var inCellXfs = false
            override fun startElement(uri: String?, localName: String?, qName: String, attributes: Attributes) {
                when {
                    qName == "numFmt" -> {
                        val id = attributes.getValue("numFmtId")?.toIntOrNull()
                        val code = attributes.getValue("formatCode")
                        if (id != null && code != null) custom[id] = code
                    }
                    qName == "cellXfs" -> inCellXfs = true
                    qName == "xf" && inCellXfs -> cellFormats += attributes.getValue("numFmtId")?.toIntOrNull() ?: 0
                }
            }
            override fun endElement(uri: String?, localName: String?, qName: String) {
                if (qName == "cellXfs") inCellXfs = false
            }
        })
        val dateFormats = SpreadsheetCell.BuiltInDateFormats + custom.filterValues(SpreadsheetCell::looksTemporal).keys
        return cellFormats.withIndex().filter { it.value in dateFormats }.map { it.index }.toSet()
    }

    /** `"BC7"` to column 54 (0-based). */
    fun columnIndex(reference: String): Int? {
        val letters = reference.takeWhile { it.isLetter() }.uppercase()
        if (letters.isEmpty()) return null
        var value = 0
        for (c in letters) {
            if (c !in 'A'..'Z') return null
            value = value * 26 + (c - 'A' + 1)
        }
        return value - 1
    }

    private fun sheet(bytes: ByteArray?, shared: List<String>, dateStyles: Set<Int>): List<SourceRow> {
        val rows = mutableListOf<SourceRow>()
        parse(bytes, object : DefaultHandler() {
            var line = 0
            val cells = sortedMapOf<Int, String>()
            var column = 0
            var type: String? = null
            var style: Int? = null
            val buffer = StringBuilder()
            var capturing = false
            var inInline = false

            override fun startElement(uri: String?, localName: String?, qName: String, attributes: Attributes) {
                when (qName) {
                    "row" -> { cells.clear(); line++ }
                    "c" -> {
                        column = attributes.getValue("r")?.let(::columnIndex) ?: ((cells.keys.maxOrNull() ?: -1) + 1)
                        type = attributes.getValue("t")
                        style = attributes.getValue("s")?.toIntOrNull()
                    }
                    "v", "t" -> { buffer.setLength(0); capturing = true }
                    "is" -> inInline = true
                }
            }

            override fun characters(ch: CharArray, start: Int, length: Int) {
                if (capturing) buffer.append(ch, start, length)
            }

            override fun endElement(uri: String?, localName: String?, qName: String) {
                when (qName) {
                    "v", "t" -> {
                        capturing = false
                        if (buffer.isNotEmpty() || column !in cells) cells[column] = resolve(buffer.toString())
                    }
                    "is" -> inInline = false
                    "row" -> {
                        // An empty row still takes a line, so preamble detection sees the real shape.
                        val highest = cells.keys.maxOrNull()
                        rows += SourceRow(line, if (highest == null) emptyList() else (0..highest).map { cells[it] ?: "" })
                    }
                }
            }

            fun resolve(raw: String): String {
                if (type == "s") raw.toIntOrNull()?.let { index -> shared.getOrNull(index)?.let { return it } }
                if (type == "str" || type == "inlineStr" || inInline) return raw
                if (type == "b") return if (raw == "1") "TRUE" else "FALSE"
                val number = raw.toDoubleOrNull() ?: return raw
                // A number whose style says "date" is a serial, not a quantity.
                if (style in dateStyles) SpreadsheetCell.displayDate(number, number != floor(number))?.let { return it }
                return SpreadsheetCell.displayNumber(number)
            }
        })
        return rows
    }
}

/**
 * Legacy `.xls` (what most Brazilian banks still hand out) into rows. Port of XLSReader.swift: an
 * OLE2 compound file holding a BIFF8 "Workbook" stream. Read-only and deliberately partial; an
 * encrypted workbook is refused rather than read as plausible nonsense.
 */
internal object XlsReader {
    fun canRead(data: ByteArray) = FileFormatSniffer.detect(data) == DetectedFileFormat.Ole2Document

    fun read(data: ByteArray): List<SourceRow> {
        val container = Ole2Container.open(data) ?: throw SpreadsheetError.Corrupt("not a readable compound document")
        val workbook = container.stream("Workbook") ?: container.stream("Book") ?: throw SpreadsheetError.NotAWorkbook
        return Biff.rows(workbook)
    }
}

internal fun ByteArray.u16(offset: Int): Int =
    if (offset < 0 || offset + 2 > size) 0 else (this[offset].toInt() and 0xFF) or ((this[offset + 1].toInt() and 0xFF) shl 8)

internal fun ByteArray.u32(offset: Int): Long =
    if (offset < 0 || offset + 4 > size) 0 else (u16(offset).toLong()) or (u16(offset + 2).toLong() shl 16)

internal fun ByteArray.u64(offset: Int): Long {
    if (offset < 0 || offset + 8 > size) return 0
    var result = 0L
    for (i in 0 until 8) result = result or ((this[offset + i].toLong() and 0xFF) shl (8 * i))
    return result
}

/** The little filesystem inside an .xls: a FAT of sector chains, a directory, and a mini-FAT. */
internal class Ole2Container private constructor(private val data: ByteArray) {
    private val sectorSize = 1 shl data.u16(30)
    private val miniSectorSize = 1 shl data.u16(32)
    private val fat = mutableListOf<Long>()
    private val miniFat = mutableListOf<Long>()
    private val directory = mutableListOf<Entry>()
    private var miniStream = ByteArray(0)

    private class Entry(val name: String, val start: Long, val size: Int, val isStream: Boolean)

    companion object {
        private const val MINI_STREAM_CUTOFF = 4096
        private const val END_OF_CHAIN = 0xFFFF_FFFEL
        private const val FREE_SECTOR = 0xFFFF_FFFFL
        private val Magic = byteArrayOf(0xD0.toByte(), 0xCF.toByte(), 0x11, 0xE0.toByte(), 0xA1.toByte(), 0xB1.toByte(), 0x1A, 0xE1.toByte())

        fun open(data: ByteArray): Ole2Container? {
            if (data.size < 512 || !data.copyOf(8).contentEquals(Magic)) return null
            val container = Ole2Container(data)
            if (container.sectorSize !in 512..65_536 || container.miniSectorSize < 64) return null
            if (!container.buildFat() || !container.buildDirectory()) return null
            container.buildMiniStream()
            return container
        }
    }

    fun stream(name: String): ByteArray? {
        val entry = directory.firstOrNull { it.isStream && it.name == name } ?: return null
        return if (entry.size < MINI_STREAM_CUTOFF) chain(entry.start, miniStream, miniSectorSize, miniFat, 0, entry.size)
        else chain(entry.start, data, sectorSize, fat, 512, entry.size)
    }

    private fun buildFat(): Boolean {
        val count = data.u32(44).toInt()
        if (count <= 0 || count >= 65_536) return false
        // The first 109 FAT sector pointers live in the header; a bank statement never needs more.
        for (index in 0 until minOf(count, 109)) {
            val sector = data.u32(76 + index * 4)
            if (sector == FREE_SECTOR) continue
            val offset = 512 + sector * sectorSize
            if (offset < 0 || offset + sectorSize > data.size) continue
            for (i in 0 until sectorSize step 4) fat += data.u32(offset.toInt() + i)
        }
        return fat.isNotEmpty()
    }

    private fun buildDirectory(): Boolean {
        val bytes = chain(data.u32(48), data, sectorSize, fat, 512, Int.MAX_VALUE) ?: return false
        // Each entry is 128 bytes: a UTF-16 name, a type byte, then the start sector and size.
        var offset = 0
        while (offset + 128 <= bytes.size) {
            val nameLength = bytes.u16(offset + 64)
            if (nameLength in 3..64) {
                val name = String(bytes, offset, nameLength - 2, Charsets.UTF_16LE)
                directory += Entry(name, bytes.u32(offset + 116), bytes.u32(offset + 120).toInt(), bytes[offset + 66].toInt() == 2)
            }
            offset += 128
        }
        return directory.isNotEmpty()
    }

    private fun buildMiniStream() {
        chain(data.u32(60), data, sectorSize, fat, 512, Int.MAX_VALUE)?.let { bytes ->
            for (i in 0 until bytes.size - 3 step 4) miniFat += bytes.u32(i)
        }
        directory.firstOrNull { !it.isStream }?.let { root ->
            miniStream = chain(root.start, data, sectorSize, fat, 512, root.size) ?: ByteArray(0)
        }
    }

    private fun chain(start: Long, source: ByteArray, size: Int, table: List<Long>, base: Int, limit: Int): ByteArray? {
        val out = ByteArrayOutputStream()
        var sector = start
        var guard = 0
        while (sector != END_OF_CHAIN && sector != FREE_SECTOR && guard < 1_048_576) {
            val offset = base + sector * size
            if (offset < 0 || offset + size > source.size) break
            out.write(source, offset.toInt(), size)
            if (out.size() >= limit) break
            if (sector >= table.size) break
            sector = table[sector.toInt()]
            guard++
        }
        val bytes = out.toByteArray()
        if (bytes.isEmpty()) return null
        return if (limit == Int.MAX_VALUE || bytes.size <= limit) bytes else bytes.copyOf(limit)
    }
}

/** BIFF8 records: an SST of pooled text, NUMBER/RK/MULRK numbers, dates by their XF format. */
internal object Biff {
    private const val BOF = 0x0809
    private const val EOF = 0x000A
    private const val SST = 0x00FC
    private const val CONTINUE = 0x003C
    private const val LABEL_SST = 0x00FD
    private const val LABEL = 0x0204
    private const val NUMBER = 0x0203
    private const val RK = 0x027E
    private const val MUL_RK = 0x00BD
    private const val FORMULA = 0x0006
    private const val XF = 0x00E0
    private const val FORMAT = 0x041E
    private const val FILE_PASS = 0x002F

    fun rows(stream: ByteArray): List<SourceRow> {
        var shared = emptyList<String>()
        val xfFormats = mutableListOf<Int>()
        val customDates = mutableSetOf<Int>()
        // row → column → display string, for the sheet being read.
        var cells = sortedMapOf<Int, MutableMap<Int, String>>()
        var offset = 0

        fun render(value: Double, xf: Int): String {
            val format = xfFormats.getOrElse(xf) { 0 }
            if (format in SpreadsheetCell.BuiltInDateFormats || format in customDates) {
                SpreadsheetCell.displayDate(value, value != floor(value))?.let { return it }
            }
            return SpreadsheetCell.displayNumber(value)
        }
        fun put(row: Int, column: Int, value: String) { cells.getOrPut(row) { mutableMapOf() }[column] = value }

        while (offset + 4 <= stream.size) {
            val type = stream.u16(offset)
            val length = stream.u16(offset + 2)
            val start = offset + 4
            if (start + length > stream.size) break
            val body = stream.copyOfRange(start, start + length)
            offset = start + length
            when (type) {
                FILE_PASS -> throw SpreadsheetError.Encrypted
                SST -> {
                    // CONTINUE boundaries carry meaning: a string resuming in the next segment starts
                    // with its own option byte, which may switch it between 8- and 16-bit mid-word.
                    val segments = mutableListOf(body)
                    while (offset + 4 <= stream.size && stream.u16(offset) == CONTINUE) {
                        val continueLength = stream.u16(offset + 2)
                        if (offset + 4 + continueLength > stream.size) break
                        segments += stream.copyOfRange(offset + 4, offset + 4 + continueLength)
                        offset += 4 + continueLength
                    }
                    shared = SstReader(segments).readAll()
                }
                FORMAT -> if (body.size > 2) {
                    val id = body.u16(0)
                    unicodeString(body, 2)?.let { if (SpreadsheetCell.looksTemporal(it)) customDates += id }
                }
                XF -> if (body.size >= 4) xfFormats += body.u16(2)
                LABEL_SST -> if (body.size >= 10) shared.getOrNull(body.u32(6).toInt())?.let { put(body.u16(0), body.u16(2), it) }
                LABEL -> if (body.size >= 8) unicodeString(body, 6)?.let { put(body.u16(0), body.u16(2), it) }
                NUMBER -> if (body.size >= 14) put(body.u16(0), body.u16(2), render(Double.fromBits(body.u64(6)), body.u16(4)))
                RK -> if (body.size >= 10) put(body.u16(0), body.u16(2), render(rk(body.u32(6)), body.u16(4)))
                MUL_RK -> if (body.size >= 6) {
                    // A run of adjacent RK cells: (xf, rk) pairs, then a trailing last-column field.
                    val row = body.u16(0)
                    val first = body.u16(2)
                    for (pair in 0 until (body.size - 6) / 6) {
                        val base = 4 + pair * 6
                        put(row, first + pair, render(rk(body.u32(base + 2)), body.u16(base)))
                    }
                }
                FORMULA -> if (body.size >= 14) {
                    // The cached result; top 16 bits all set mean "not a number".
                    val bits = body.u64(6)
                    if ((bits ushr 48) != 0xFFFFL) put(body.u16(0), body.u16(2), render(Double.fromBits(bits), body.u16(4)))
                }
                // The first worksheet that holds cells is the one read. (iOS reads every sheet into
                // one grid, so a second sheet's cells land on top of the first's.)
                EOF -> if (cells.isNotEmpty()) return assemble(cells)
                BOF -> Unit
            }
        }
        if (cells.isEmpty()) throw SpreadsheetError.EmptyWorkbook
        return assemble(cells)
    }

    private fun assemble(cells: Map<Int, Map<Int, String>>): List<SourceRow> = cells.mapNotNull { (row, columns) ->
        val highest = columns.keys.maxOrNull() ?: return@mapNotNull null
        // BIFF rows are 0-based; +1 is the line the user sees.
        SourceRow(row + 1, (0..highest).map { columns[it] ?: "" })
    }

    /** RK: two flag bits, then a truncated double or a 30-bit integer, maybe divided by 100. */
    private fun rk(raw: Long): Double {
        val value = if (raw and 0x02L != 0L) {
            ((raw and 0xFFFF_FFFCL).toInt() shr 2).toDouble()
        } else {
            Double.fromBits((raw and 0xFFFF_FFFCL) shl 32)
        }
        return if (raw and 0x01L != 0L) value / 100 else value
    }

    /** A BIFF8 XLUnicodeString: count, options, then 8-bit Latin-1 or 16-bit characters. */
    private fun unicodeString(data: ByteArray, start: Int): String? {
        if (start + 3 > data.size) return null
        val count = data.u16(start)
        val options = data[start + 2].toInt()
        val wide = options and 0x01 != 0
        var offset = start + 3
        if (options and 0x08 != 0) offset += 2
        if (options and 0x04 != 0) offset += 4
        val bytes = if (wide) count * 2 else count
        if (offset + bytes > data.size) return null
        return if (wide) String(data, offset, bytes, Charsets.UTF_16LE) else String(data, offset, bytes, Charsets.ISO_8859_1)
    }

    /** A cursor over the SST's segments that understands continuation. */
    private class SstReader(private val segments: List<ByteArray>) {
        private var segment = 0
        private var offset = 8

        fun readAll(): List<String> {
            val unique = segments.firstOrNull()?.takeIf { it.size >= 8 }?.u32(4)?.toInt() ?: return emptyList()
            if (unique <= 0 || unique >= 1_048_576) return emptyList()
            val strings = mutableListOf<String>()
            while (strings.size < unique) strings += readString() ?: break
            return strings
        }

        private val remaining get() = segments.getOrNull(segment)?.let { maxOf(0, it.size - offset) } ?: 0

        /** Steps to the next segment; only a resuming STRING begins with an option byte. */
        private fun next(withOption: Boolean): Int? {
            segment++
            offset = 0
            val bytes = segments.getOrNull(segment)?.takeIf { it.isNotEmpty() } ?: return null
            if (!withOption) return 0
            offset = 1
            return bytes[0].toInt()
        }

        private fun byte(): Int? {
            if (remaining == 0 && next(false) == null) return null
            if (remaining == 0) return null
            return segments[segment][offset++].toInt() and 0xFF
        }

        private fun u16(): Int? {
            val low = byte() ?: return null
            val high = byte() ?: return null
            return low or (high shl 8)
        }

        private fun skip(count: Int) {
            var left = count
            while (left > 0) {
                if (remaining == 0) { if (next(false) == null) return; continue }
                val step = minOf(left, remaining)
                offset += step
                left -= step
            }
        }

        fun readString(): String? {
            val count = u16() ?: return null
            val options = byte() ?: return null
            var wide = options and 0x01 != 0
            val runs = if (options and 0x08 != 0) u16() ?: 0 else 0
            val farEast = if (options and 0x04 != 0) { val a = u16() ?: 0; val b = u16() ?: 0; a or (b shl 16) } else 0
            val out = StringBuilder(count)
            var read = 0
            while (read < count) {
                // Excel never splits a character, so running out of room means the string resumes in
                // the next segment, behind a fresh option byte.
                if (remaining == 0 || (wide && remaining < 2)) {
                    val option = next(true) ?: break
                    wide = option and 0x01 != 0
                    continue
                }
                if (wide) out.append((u16() ?: break).toChar()) else out.append((byte() ?: break).toChar())
                read++
            }
            skip(runs * 4 + farEast)
            return out.toString()
        }
    }
}
