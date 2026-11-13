package com.arthurrios.finova.domain.importer

import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import java.security.MessageDigest
import java.util.UUID
import kotlin.math.abs

/**
 * Rows plus a schema plus the ledger in; the reviewable plan out. Port of ImportPlanner.swift. The
 * ledger arrives as a SNAPSHOT list, so all of parsing, inference, categorization and dedupe is a
 * pure function, tested without a database.
 */
class ImportPlanner(
    existing: List<Transaction>,
    private val alreadyImported: Set<String> = emptySet(),
    rules: MerchantRuleSet = MerchantRuleSet(),
    categoryNames: Map<TransactionCategory, String> = emptyMap(),
    private val untitled: String = "Untitled transaction",
) {
    private val duplicates = DuplicateIndex(existing)
    private val categorizer = DeterministicCategorizer(existing, rules, categoryNames)

    fun plan(rows: List<SourceRow>, schema: ResolvedSchema, confidence: InferenceConfidence, source: ImportSource): ImportPlan {
        // The first of identical rows wins the slot; the rest are flagged but still imported.
        val seenInFile = HashMap<DuplicateIndex.Key, Int>()
        val numberUnproven = confidence.numberFormat.score < 0.9
        val signUnproven = confidence.signConvention.score < 0.6
        val dateUnproven = confidence.dateFormat.score < 0.6

        val planned = rows.map { row ->
            val fingerprint = fingerprint(source.sha256, row.line, row.cells)
            val warnings = mutableListOf<RowWarning>()
            val parsed = parse(row, schema, warnings)
                ?: return@map ImportRow(row.line, row.cells, fingerprint, null, Disposition.Failed(failureReason(row, schema)), null, warnings)
            if (numberUnproven) warnings += RowWarning.AmbiguousNumberFormat
            if (parsed.title.installmentHint != null) warnings += RowWarning.InstallmentHintIgnored
            val type = if (parsed.signedCents > 0) TransactionType.Income else TransactionType.Expense
            val suggestion = categorizer.categorize(parsed.title, type, parsed.bankCategory)
            val disposition = classify(parsed, fingerprint, row.line, seenInFile, signUnproven, dateUnproven)
            ImportRow(row.line, row.cells, fingerprint, parsed, disposition, suggestion, warnings)
        }
        return ImportPlan(source, schema, confidence, planned)
    }

    // ---- Parsing one row -----------------------------------------------------------------------

    private fun parse(row: SourceRow, schema: ResolvedSchema, warnings: MutableList<RowWarning>): ParsedRow? {
        val rawDate = schema.column(ColumnRole.Date)?.let { row.cells.getOrNull(it) } ?: return null
        // A fused column carries the date and the description; the date is consumed, the rest kept.
        var fusedRemainder: String? = null
        val date = if (schema.dateColumnCarriesDescription) {
            val leading = DateFieldParser.parseLeadingDate(rawDate) ?: return null
            fusedRemainder = leading.remainder
            leading.date
        } else {
            DateFieldParser.parse(rawDate, schema.dateFormat) ?: return null
        }
        val cents = signedCents(row, schema, warnings) ?: return null
        if (cents == 0L) return null
        // A real description column still wins; the fused remainder is the fallback.
        val rawTitle = schema.column(ColumnRole.Description)?.let { row.cells.getOrNull(it) }?.takeIf { it.isNotEmpty() }
            ?: fusedRemainder ?: ""
        val cleaned = TitleCleaner.clean(rawTitle, untitled)
        if (cleaned.title.isEmpty()) warnings += RowWarning.TitleWasEmpty
        val bankCategory = schema.column(ColumnRole.Category)?.let { row.cells.getOrNull(it) }?.takeIf { it.isNotEmpty() }
        return ParsedRow(date, cents, cleaned, bankCategory)
    }

    private fun cell(row: SourceRow, schema: ResolvedSchema, role: ColumnRole) = schema.column(role)?.let { row.cells.getOrNull(it) }

    private fun signedCents(row: SourceRow, schema: ResolvedSchema, warnings: MutableList<RowWarning>): Long? {
        fun amount(role: ColumnRole) = cell(row, schema, role)?.let { AmountParser.parseOrNull(it, schema.numberFormat) }
        return when (schema.signConvention) {
            SignConvention.SeparateDebitCredit -> {
                val debit = amount(ColumnRole.Debit)
                val credit = amount(ColumnRole.Credit)
                when {
                    debit != null && debit.cents != 0L -> { if (debit.wasRounded) warnings += RowWarning.AmountRounded; -abs(debit.cents) }
                    credit != null && credit.cents != 0L -> { if (credit.wasRounded) warnings += RowWarning.AmountRounded; abs(credit.cents) }
                    else -> null
                }
            }
            SignConvention.IndicatorColumn -> {
                val parsed = amount(ColumnRole.Amount) ?: return null
                if (parsed.wasRounded) warnings += RowWarning.AmountRounded
                val flag = cell(row, schema, ColumnRole.DirectionFlag)?.trim()?.uppercase()
                if (flag == "D" || flag == "-" || flag == "DEBITO") -abs(parsed.cents) else abs(parsed.cents)
            }
            SignConvention.NegativeIsExpense -> amount(ColumnRole.Amount)?.also { if (it.wasRounded) warnings += RowWarning.AmountRounded }?.cents
            SignConvention.PositiveIsExpense -> amount(ColumnRole.Amount)?.also { if (it.wasRounded) warnings += RowWarning.AmountRounded }?.let { -it.cents }
        }
    }

    private fun failureReason(row: SourceRow, schema: ResolvedSchema): RowError {
        val rawDate = cell(row, schema, ColumnRole.Date) ?: return RowError.MissingField(ColumnRole.Date)
        val dateReads = if (schema.dateColumnCarriesDescription) DateFieldParser.parseLeadingDate(rawDate) != null
            else DateFieldParser.parse(rawDate, schema.dateFormat) != null
        if (!dateReads) return RowError.UnparseableDate(rawDate)
        // The amount cell this row was read from, whichever shape the file has.
        val raw = cell(row, schema, ColumnRole.Amount)
            ?: listOfNotNull(cell(row, schema, ColumnRole.Debit), cell(row, schema, ColumnRole.Credit)).firstOrNull { it.isNotBlank() }
            ?: return if (schema.signConvention == SignConvention.SeparateDebitCredit) RowError.ZeroAmount else RowError.MissingField(ColumnRole.Amount)
        return try {
            if (AmountParser.parse(raw, schema.numberFormat).cents == 0L) RowError.ZeroAmount else RowError.UnparseableAmount(raw)
        } catch (_: AmountParser.Failure.OutOfRange) {
            RowError.AmountOutOfRange
        } catch (_: AmountParser.Failure) {
            RowError.UnparseableAmount(raw)
        }
    }

    // ---- Classification ------------------------------------------------------------------------

    private fun classify(
        parsed: ParsedRow,
        fingerprint: String,
        line: Int,
        seenInFile: HashMap<DuplicateIndex.Key, Int>,
        signUnproven: Boolean,
        dateUnproven: Boolean,
    ): Disposition {
        // Tier 0: this exact row came in before.
        if (fingerprint in alreadyImported) return Disposition.AlreadyImported
        // Open file-level questions outrank dedupe: a duplicate badge means nothing on an inverted sign.
        if (dateUnproven) return Disposition.NeedsDecision(RowDecision.AmbiguousDate)
        if (signUnproven) return Disposition.NeedsDecision(RowDecision.AmbiguousSign)

        val key = DuplicateIndex.Key(parsed.date, parsed.signedCents, parsed.title.title.normalizedForSearch())
        // Tier 3: a twin earlier in the file.
        seenInFile[key]?.let { return Disposition.DuplicateInFile(it) }
        seenInFile[key] = line
        // Tier 1: an exact match in the ledger.
        duplicates.exactMatch(key)?.let { return Disposition.DuplicateExact(it) }
        // Tier 2: same amount, a few days apart, similar title.
        duplicates.fuzzyMatch(parsed.date, parsed.signedCents, parsed.title.title)?.let { return Disposition.DuplicateLikely(it.first, it.second) }
        return Disposition.Insert
    }

    companion object {
        /**
         * Stable across re-imports of the same file and re-inference of the same import. Over the RAW
         * cells, so better title cleaning later does not make every imported row look new.
         */
        fun fingerprint(fileHash: String, line: Int, cells: List<String>): String =
            DeterministicIdentity.v5("csvimport|$fileHash|$line|${cells.joinToString("\u001F")}")
    }
}

/** RFC 4122 name-based UUIDs (v5, SHA-1), over the same namespace as iOS DeterministicIdentity. */
object DeterministicIdentity {
    private val Namespace = UUID.fromString("6E9C1B7A-4F3D-4A21-9E62-8D5C0A17B3F4")

    fun v5(name: String): String {
        val digest = MessageDigest.getInstance("SHA-1")
        digest.update(java.nio.ByteBuffer.allocate(16).putLong(Namespace.mostSignificantBits).putLong(Namespace.leastSignificantBits).array())
        digest.update(name.toByteArray(Charsets.UTF_8))
        val bytes = digest.digest().copyOf(16)
        bytes[6] = ((bytes[6].toInt() and 0x0F) or 0x50).toByte()
        bytes[8] = ((bytes[8].toInt() and 0x3F) or 0x80).toByte()
        val hex = bytes.joinToString("") { "%02X".format(it) }
        return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}"
    }

    fun sha256(data: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }
}
