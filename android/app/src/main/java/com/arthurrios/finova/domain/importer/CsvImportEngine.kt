package com.arthurrios.finova.domain.importer

import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory

/**
 * The whole read path: bytes in, [ImportPlan] out. Port of CSVImportEngine.swift. Synchronous and
 * free of side effects; the caller picks the thread, which keeps every decision testable with a
 * string and a list.
 */
object CsvImportEngine {
    /** Two orders of magnitude past any real bank export. */
    const val MAX_FILE_BYTES = 10 * 1_048_576

    class Input(
        val filename: String,
        val data: ByteArray,
        /** Fingerprints this user already imported, for the "imported before" tier. */
        val alreadyImported: Set<String>,
        /** The ledger, injected rather than fetched. */
        val existing: List<Transaction>,
        val categoryNames: Map<TransactionCategory, String> = emptyMap(),
        val untitled: String = "Untitled transaction",
        val rules: MerchantRuleSet = MerchantRuleSet(),
    )

    /** The rows a file holds, how it was decoded, and whether it was a workbook. */
    private class Table(val rows: List<SourceRow>, val dialect: CsvDialect, val encoding: String, val wasLossy: Boolean, val decodedText: String?, val isWorkbook: Boolean)

    fun makePlan(input: Input): ImportPlan {
        val table = readTable(input.data)
        // A file that IS a table but whose columns could not be identified comes back with an unusable
        // schema and zero confidence: a file the user maps by hand, not an error.
        val inferred = SchemaInferencer.infer(table.rows) ?: throw ImportError.NotTabular(diagnostics(table))
        var schema = inferred.schema
        // Workbook readers write numbers with a POSIX point and no grouping, so the format is KNOWN.
        // Inferring it fails: `-50.5` matches neither pattern, and pt-BR would read the dot as
        // thousands, so fifty and a half becomes five hundred and five.
        if (table.isWorkbook) schema = schema.copy(numberFormat = NumberFormatSpec.EnUS)
        return planner(input).plan(inferred.dataRows, schema, inferred.confidence, source(input, table))
    }

    /**
     * The same file again under a schema the user corrected. A full recompute, since a new date
     * format changes which rows parse and which are duplicates. Overrides survive: they are keyed by
     * fingerprint, not by position. Reads the rows the same way [makePlan] did, so a workbook works
     * here too (iOS re-decodes the bytes as CSV text, which a workbook is not).
     */
    fun replan(input: Input, schema: ResolvedSchema, previous: ImportPlan): ImportPlan {
        val table = readTable(input.data)
        val (modal, _) = CsvTokenizer.modalFieldCount(table.rows)
        var shaped = table.rows.filter { it.cells.size == modal }
        if (schema.hasHeaderRow && shaped.isNotEmpty()) shaped = shaped.drop(1)
        // The user settled whatever inference was unsure about.
        return planner(input).plan(shaped, schema, previous.confidence.confirmedByUser(), previous.source)
    }

    private fun planner(input: Input) =
        ImportPlanner(input.existing, input.alreadyImported, input.rules, input.categoryNames, input.untitled)

    private fun source(input: Input, table: Table) = ImportSource(
        filename = input.filename,
        byteCount = input.data.size,
        sha256 = DeterministicIdentity.sha256(input.data),
        encoding = table.encoding,
        dialect = table.dialect,
        wasLossy = table.wasLossy,
    )

    private fun readTable(data: ByteArray): Table {
        if (data.isEmpty()) throw ImportError.EmptyFile
        if (data.size > MAX_FILE_BYTES) throw ImportError.FileTooLarge(data.size, MAX_FILE_BYTES)

        // A workbook becomes the same rows a CSV does, so everything downstream is shared.
        if (SpreadsheetImporter.canRead(data)) {
            val rows = try {
                SpreadsheetImporter.read(data)
            } catch (e: SpreadsheetError) {
                throw when (e) {
                    SpreadsheetError.EmptyWorkbook -> ImportError.EmptyFile
                    SpreadsheetError.Encrypted -> ImportError.WrongFileFormat(DetectedFileFormat.Ole2Document, encrypted = true)
                    // The answer is the same either way (export a CSV instead), so name the format.
                    else -> ImportError.WrongFileFormat(FileFormatSniffer.detect(data))
                }
            } catch (e: Exception) {
                throw ImportError.WrongFileFormat(FileFormatSniffer.detect(data))
            }
            if (rows.isEmpty()) throw ImportError.EmptyFile
            return Table(rows, CsvDialect('\t'), "workbook", false, null, true)
        }

        // Checked before decoding: a PDF through a text decoder is line noise, and every later error
        // would describe a symptom instead of the cause.
        val format = FileFormatSniffer.detect(data)
        if (format != DetectedFileFormat.Text) throw ImportError.WrongFileFormat(format)
        val decoded = EncodingSniffer.decode(data) ?: throw ImportError.NotTextual
        if (decoded.text.isBlank()) throw ImportError.EmptyFile

        val detection = DelimiterSniffer.sniff(decoded.text)
        val body = if (detection.skipLeadingLines > 0) decoded.text.split('\n').drop(detection.skipLeadingLines).joinToString("\n") else decoded.text
        var dialect = detection.dialect
        var rows = CsvTokenizer.tokenize(body, dialect)
        if (rows.isEmpty()) throw ImportError.EmptyFile

        // A wrong delimiter pick collapses the file into one column. Cheap insurance: try the others.
        if (CsvTokenizer.modalFieldCount(rows).first < 2) {
            for (candidate in CsvDialect.CandidateDelimiters) {
                if (candidate == dialect.delimiter) continue
                val retry = runCatching { CsvTokenizer.tokenize(body, CsvDialect(candidate)) }.getOrNull() ?: continue
                if (CsvTokenizer.modalFieldCount(retry).first < 2) continue
                dialect = CsvDialect(candidate)
                rows = retry
                break
            }
        }
        return Table(rows, dialect, decoded.encoding, decoded.wasLossy, decoded.text, false)
    }

    /**
     * What the engine saw in a file it could not make a table of: the encoding, separator, shape and
     * first line. Control characters show as `·`, the tell of a binary renamed to .csv.
     */
    private fun diagnostics(table: Table): String {
        val firstLine = table.decodedText?.lineSequence()?.firstOrNull { it.isNotEmpty() }?.take(80).orEmpty()
        val readable = firstLine.map { if (it.isISOControl() && it != '\t') '·' else it }.joinToString("")
        return "${table.encoding} · ${table.dialect.displayName} · ${CsvTokenizer.modalFieldCount(table.rows).first} col · ${table.rows.size} rows\n“$readable”"
    }
}
