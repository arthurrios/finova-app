package com.arthurrios.finova.domain.importer

import kotlin.math.min

class ColumnProfile(
    val index: Int,
    val headerText: String?,
    val values: List<String>,
    val emptyRate: Double,
    val distinctRatio: Double,
    val dateHitRate: Double,
    val numericHitRate: Double,
    val negativeRate: Double,
    val meanTokenCount: Double,
    val letterRate: Double,
    /** Values drawn from a tiny set like {D, C} or {+, -}. */
    val looksLikeDirectionFlag: Boolean,
)

/**
 * Works out what a file's columns mean. Port of SchemaInferencer.swift. Header keywords are not
 * enough (localized, abbreviated, absent), so two CONTENT proofs do the heavy lifting:
 * - mutual exclusivity finds a split debit/credit pair: two numeric columns where each row fills one;
 * - the balance proof finds the amount column AND its sign: `balance[i] - balance[i-1] == amount[i]`.
 * Keywords then break ties and label the rest.
 */
object SchemaInferencer {

    class Result(
        val schema: ResolvedSchema,
        val confidence: InferenceConfidence,
        val profiles: List<ColumnProfile>,
        /** The data rows, preamble and header removed. */
        val dataRows: List<SourceRow>,
        val headerRow: SourceRow?,
    )

    /** Accent- and case-folded before matching. */
    private val Keywords: Map<ColumnRole, List<String>> = mapOf(
        ColumnRole.Date to listOf("data", "data lancamento", "data movimento", "data da compra", "dt", "dt lancamento",
            "date", "posted", "posted date", "transaction date", "booking date"),
        ColumnRole.Description to listOf("descricao", "historico", "lancamento", "detalhes", "estabelecimento",
            "titulo", "description", "memo", "details", "payee", "merchant", "narrative"),
        ColumnRole.Amount to listOf("valor", "valor r$", "valor (r$)", "montante", "quantia", "amount", "value", "transaction amount"),
        ColumnRole.Debit to listOf("debito", "saida", "saidas", "pagamento", "debit", "withdrawal", "money out", "paid out"),
        ColumnRole.Credit to listOf("credito", "entrada", "entradas", "recebimento", "credit", "deposit", "money in", "paid in"),
        ColumnRole.Balance to listOf("saldo", "saldo atual", "balance", "running balance"),
        ColumnRole.Category to listOf("categoria", "category", "tipo de transacao"),
        ColumnRole.DocId to listOf("documento", "doc", "num doc", "numero do documento", "identificador", "id", "reference", "transaction id"),
        ColumnRole.DirectionFlag to listOf("d/c", "dc", "tipo", "natureza", "debito/credito"),
    )

    fun infer(rows: List<SourceRow>): Result? {
        if (rows.isEmpty()) return null
        val (modalCount, _) = CsvTokenizer.modalFieldCount(rows)
        if (modalCount < 2) return null

        // Preamble and summary lines are exactly the rows that disagree with the modal width.
        val shaped = rows.filter { it.cells.size == modalCount }
        if (shaped.isEmpty()) return null
        val preambleRows = rows.takeWhile { it.cells.size != modalCount }.size

        val (hasHeader, headerConfidence) = detectHeader(shaped)
        val headerRow = if (hasHeader) shaped.first() else null
        val dataRows = if (hasHeader) shaped.drop(1) else shaped
        if (dataRows.isEmpty()) return null

        val profiles = (0 until modalCount).map { profile(it, headerRow?.cells?.getOrNull(it), dataRows) }
        val roles = mutableMapOf<Int, ColumnRole>()

        // 1. The date, by content. A file where no column reads as dates is not an error: it is a file
        //    the user maps by hand, so the roles stay empty and the confidence zero.
        val dateColumn = pickDateColumn(profiles)
        val dateIndex = dateColumn?.first
        val dateIsFused = dateColumn?.second ?: false
        if (dateIndex != null) roles[dateIndex] = ColumnRole.Date

        var dateFormat = DateFormatSpec.DayFirst
        val dateConfidence = if (dateIndex == null) {
            SubConfidence.none("no column reads as dates")
        } else {
            // A fused column is detected from its extracted PREFIXES.
            val values = if (dateIsFused) DateFieldParser.leadingDateTexts(profiles[dateIndex].values) else profiles[dateIndex].values
            when (val detection = DateFieldParser.detectFormat(values)) {
                is DateFieldParser.Detection.Proven -> { dateFormat = detection.spec; SubConfidence.proof("a component above 12 fixes the order") }
                is DateFieldParser.Detection.Likely -> { dateFormat = detection.spec; SubConfidence.strong("dates run in order under this reading") }
                is DateFieldParser.Detection.Ambiguous -> {
                    dateFormat = detection.first
                    SubConfidence.weak("every component is 12 or less — day and month are interchangeable")
                }
                DateFieldParser.Detection.Inconsistent, DateFieldParser.Detection.None ->
                    SubConfidence.none("the dates in this column contradict each other")
            }
        }

        // 2. The amount shape.
        val numericColumns = profiles.filter { it.index != dateIndex && it.numericHitRate >= 0.8 }.sortedBy { it.index }
        val shape = resolveAmountShape(numericColumns, profiles)
        roles.putAll(shape.roles)
        val foundAnAmount = shape.roles.values.any { it == ColumnRole.Amount || it == ColumnRole.Debit || it == ColumnRole.Credit }

        // 3. The number format, across every column that carries money.
        val moneyValues = shape.roles.filterValues { it == ColumnRole.Amount || it == ColumnRole.Debit || it == ColumnRole.Credit }
            .keys.flatMap { profiles[it].values }
        val (numberFormat, numberProven) = AmountParser.detectFormat(moneyValues)
        val numberConfidence = when {
            !foundAnAmount -> SubConfidence.none("no column reads as amounts")
            numberProven -> SubConfidence.proof("a value carries both separators, so the order is fixed")
            else -> SubConfidence.weak("no value carries both separators — the decimal mark is inferred")
        }

        // 4. The description: the wordiest free column, unless the date column already carries it.
        if (!dateIsFused) pickDescriptionColumn(profiles, roles.keys)?.let { roles[it] = ColumnRole.Description }

        // 5. The rest by keyword: hints, where a wrong guess costs nothing.
        for (profile in profiles) if (profile.index !in roles) roles[profile.index] = keywordRole(profile) ?: ColumnRole.Ignored

        val rolesConfidence = when {
            dateIsFused -> SubConfidence.strong("the date and description share one column")
            ColumnRole.Description in roles.values -> SubConfidence.strong("a date, an amount and a description were all identified")
            else -> SubConfidence.weak("no description column — titles will fall back to the payment rail")
        }

        return Result(
            schema = ResolvedSchema(
                roles = roles,
                hasHeaderRow = hasHeader,
                preambleRows = preambleRows,
                dateFormat = dateFormat,
                numberFormat = numberFormat,
                signConvention = shape.signConvention,
                dateColumnCarriesDescription = dateIsFused,
            ),
            confidence = InferenceConfidence(
                header = headerConfidence,
                dateFormat = dateConfidence,
                numberFormat = numberConfidence,
                amountShape = shape.confidence,
                signConvention = shape.signConfidence,
                columnRoles = rolesConfidence,
            ),
            profiles = profiles,
            dataRows = dataRows,
            headerRow = headerRow,
        )
    }

    // ---- Header --------------------------------------------------------------------------------

    private fun detectHeader(rows: List<SourceRow>): Pair<Boolean, SubConfidence> {
        val first = rows.firstOrNull()
        if (first == null || rows.size < 2) return false to SubConfidence.weak("too few rows to tell")
        val cells = first.cells
        val allNonEmpty = cells.all { it.isNotBlank() }
        val allDistinct = cells.map { it.normalizedForSearch() }.toSet().size == cells.size
        val noDates = cells.all { DateFieldParser.dateHitRate(listOf(it)) == 0.0 }
        val noNumbers = cells.all { AmountParser.parseOrNull(it, NumberFormatSpec.PtBR) == null }
        // Text where the rows below are data. All four together: a data row can be all-distinct, and a
        // header can hold a number-ish code, but not both at once.
        if (!(allNonEmpty && allDistinct && noDates && noNumbers)) {
            return false to SubConfidence.strong("the first row parses as data, so there is no header")
        }
        val recognised = cells.count { cell ->
            val folded = cell.normalizedForSearch()
            Keywords.values.any { list -> list.any { folded.contains(it) } }
        }
        return true to if (recognised >= 2) SubConfidence.proof("the first row is text and names columns we recognise")
            else SubConfidence.strong("the first row is text where the rows below are data")
    }

    // ---- Profiling -----------------------------------------------------------------------------

    private fun profile(index: Int, header: String?, rows: List<SourceRow>): ColumnProfile {
        val values = rows.map { it.cells.getOrNull(index) ?: "" }
        val nonEmpty = values.filter { it.isNotBlank() }
        val total = maxOf(values.size, 1).toDouble()
        val parsed = nonEmpty.mapNotNull { AmountParser.parseOrNull(it, NumberFormatSpec.PtBR) }
        val letters = nonEmpty.count { value -> value.any { it.isLetter() } }
        val tokens = nonEmpty.map { it.split(' ').filter { t -> t.isNotEmpty() }.size.toDouble() }
        val flagValues = nonEmpty.map { it.uppercase().trim() }.toSet()
        return ColumnProfile(
            index = index,
            headerText = header,
            values = values,
            emptyRate = 1 - nonEmpty.size / total,
            distinctRatio = nonEmpty.toSet().size.toDouble() / maxOf(nonEmpty.size, 1),
            dateHitRate = DateFieldParser.dateHitRate(nonEmpty),
            numericHitRate = if (nonEmpty.isEmpty()) 0.0 else parsed.size.toDouble() / nonEmpty.size,
            negativeRate = if (parsed.isEmpty()) 0.0 else parsed.count { it.cents < 0 }.toDouble() / parsed.size,
            meanTokenCount = if (tokens.isEmpty()) 0.0 else tokens.average(),
            letterRate = if (nonEmpty.isEmpty()) 0.0 else letters.toDouble() / nonEmpty.size,
            looksLikeDirectionFlag = flagValues.isNotEmpty() && flagValues.size <= 3 &&
                flagValues.all { it in setOf("D", "C", "+", "-", "DEBITO", "CREDITO") },
        )
    }

    // ---- Column selection ----------------------------------------------------------------------

    /**
     * The date column, and whether it also carries the description. Clean dates always win; the fused
     * probe runs only when nothing qualifies, because it is the most expensive one.
     */
    private fun pickDateColumn(profiles: List<ColumnProfile>): Pair<Int, Boolean>? {
        profiles.filter { it.dateHitRate >= 0.9 }.maxByOrNull(::scoreForDate)?.let { return it.index to false }
        return profiles.map { it to DateFieldParser.leadingDateHitRate(it.values) }
            .filter { it.second >= 0.9 }
            .maxByOrNull { it.second }
            ?.let { it.first.index to true }
    }

    private fun scoreForDate(profile: ColumnProfile): Double {
        var score = profile.dateHitRate
        if (headerMatches(profile, ColumnRole.Date)) score += 0.5
        // Ties go to the leftmost: with a posting and a transaction date, banks lead with the first.
        return score - profile.index * 0.001
    }

    private fun pickDescriptionColumn(profiles: List<ColumnProfile>, taken: Set<Int>): Int? =
        profiles.filter { it.index !in taken && it.letterRate >= 0.5 && it.emptyRate < 0.5 }
            .maxByOrNull(::scoreForDescription)?.index

    private fun scoreForDescription(profile: ColumnProfile): Double {
        var score = profile.letterRate + min(profile.meanTokenCount / 4, 1.0) + profile.distinctRatio
        if (headerMatches(profile, ColumnRole.Description)) score += 1.5
        return score
    }

    private fun keywordRole(profile: ColumnProfile): ColumnRole? {
        if (profile.looksLikeDirectionFlag) return ColumnRole.DirectionFlag
        val header = profile.headerText?.normalizedForSearch()?.takeIf { it.isNotEmpty() } ?: return null
        // Longest match wins, so "saldo atual" beats "saldo" and "data lancamento" beats "data".
        var best: Pair<ColumnRole, Int>? = null
        for ((role, list) in Keywords) for (keyword in list) {
            if (header.contains(keyword) && (best == null || keyword.length > best.second)) best = role to keyword.length
        }
        return best?.first
    }

    private fun headerMatches(profile: ColumnProfile, role: ColumnRole): Boolean {
        val header = profile.headerText?.normalizedForSearch() ?: return false
        return Keywords[role].orEmpty().any { header.contains(it) }
    }

    // ---- Amount shape and sign convention ------------------------------------------------------

    private class AmountShape(
        val roles: Map<Int, ColumnRole>,
        val signConvention: SignConvention,
        val confidence: SubConfidence,
        val signConfidence: SubConfidence,
    )

    private fun resolveAmountShape(numeric: List<ColumnProfile>, profiles: List<ColumnProfile>): AmountShape {
        // A. A split debit/credit pair. Exclusivity beats any keyword, and works unlabeled.
        findMutuallyExclusivePair(numeric)?.let { (a, b) ->
            val debitFirst = headerMatches(a, ColumnRole.Debit) || headerMatches(b, ColumnRole.Credit)
            val debit = if (debitFirst) a else b
            val credit = if (debitFirst) b else a
            return AmountShape(
                mapOf(debit.index to ColumnRole.Debit, credit.index to ColumnRole.Credit),
                SignConvention.SeparateDebitCredit,
                SubConfidence.proof("two columns where each row fills exactly one"),
                SubConfidence.proof("direction is which column the value is in"),
            )
        }
        // B. A running balance proves the amount column and its sign, by arithmetic.
        findBalanceProof(numeric)?.let { (amount, balance, positiveIsIncome) ->
            val roles = mutableMapOf(amount.index to ColumnRole.Amount, balance.index to ColumnRole.Balance)
            profiles.firstOrNull { it.looksLikeDirectionFlag }?.let { roles[it.index] = ColumnRole.DirectionFlag }
            return AmountShape(
                roles,
                if (positiveIsIncome) SignConvention.NegativeIsExpense else SignConvention.PositiveIsExpense,
                SubConfidence.proof("the running balance moves by exactly this column's value"),
                SubConfidence.proof("the balance rises when this column is positive"),
            )
        }
        // C. A D/C marker beside one amount.
        val flag = profiles.firstOrNull { it.looksLikeDirectionFlag }
        val flagged = numeric.firstOrNull { !headerMatches(it, ColumnRole.Balance) }
        if (flag != null && flagged != null) {
            return AmountShape(
                mapOf(flagged.index to ColumnRole.Amount, flag.index to ColumnRole.DirectionFlag),
                SignConvention.IndicatorColumn,
                SubConfidence.strong("one amount column beside a debit/credit marker"),
                SubConfidence.proof("direction is stated per row"),
            )
        }
        // D. One amount column, and nothing proves its direction.
        val amount = numeric.filter { !headerMatches(it, ColumnRole.Balance) }.maxByOrNull(::scoreForAmount)
            ?: return AmountShape(
                emptyMap(), SignConvention.NegativeIsExpense,
                SubConfidence.none("no numeric column"), SubConfidence.none("no numeric column"),
            )
        val roles = mutableMapOf(amount.index to ColumnRole.Amount)
        for (profile in numeric) if (profile.index != amount.index && headerMatches(profile, ColumnRole.Balance)) roles[profile.index] = ColumnRole.Balance
        val named = headerMatches(amount, ColumnRole.Amount) && !amount.headerText.isNullOrBlank()
        // NOT inferred from "most rows are negative": in a current account most rows are debits, so
        // the majority sign says nothing, and guessing wrong inverts a month. Assume the common
        // convention, score it low, and let the review ask.
        return AmountShape(
            roles,
            SignConvention.NegativeIsExpense,
            if (named) SubConfidence.strong("a single column named as the amount") else SubConfidence.weak("a single numeric column, identified by content"),
            SubConfidence.weak("nothing in the file proves which sign means money out"),
        )
    }

    private fun findMutuallyExclusivePair(columns: List<ColumnProfile>): Pair<ColumnProfile, ColumnProfile>? {
        for (i in columns.indices) for (j in i + 1 until columns.size) {
            val a = columns[i]
            val b = columns[j]
            val rowCount = minOf(a.values.size, b.values.size)
            if (rowCount < 4) continue
            val exclusive = (0 until rowCount).count { isNonZeroNumber(a.values[it]) != isNonZeroNumber(b.values[it]) }
            if (exclusive.toDouble() / rowCount >= 0.9) return a to b
        }
        return null
    }

    private fun findBalanceProof(columns: List<ColumnProfile>): Triple<ColumnProfile, ColumnProfile, Boolean>? {
        for (balanceColumn in columns) for (amountColumn in columns) {
            if (amountColumn.index == balanceColumn.index) continue
            val balances = balanceColumn.values.map { AmountParser.parseOrNull(it, NumberFormatSpec.PtBR) }
            val amounts = amountColumn.values.map { AmountParser.parseOrNull(it, NumberFormatSpec.PtBR) }
            // Three rows give two consecutive deltas, the minimum the check needs. Short files (one
            // quiet month) are common, and an unproven sign parks every row for a decision.
            val rowCount = minOf(balances.size, amounts.size)
            if (rowCount < 3) continue
            var agreeing = 0
            var opposing = 0
            var comparable = 0
            for (row in 1 until rowCount) {
                val previous = balances[row - 1] ?: continue
                val current = balances[row] ?: continue
                val amount = amounts[row] ?: continue
                comparable++
                val delta = current.cents - previous.cents
                if (delta == amount.cents) agreeing++ else if (delta == -amount.cents) opposing++
            }
            if (comparable < 2) continue
            if (agreeing.toDouble() / comparable >= 0.8) return Triple(amountColumn, balanceColumn, true)
            if (opposing.toDouble() / comparable >= 0.8) return Triple(amountColumn, balanceColumn, false)
        }
        return null
    }

    private fun isNonZeroNumber(value: String) = (AmountParser.parseOrNull(value, NumberFormatSpec.PtBR)?.cents ?: 0L) != 0L

    private fun scoreForAmount(profile: ColumnProfile): Double {
        var score = profile.numericHitRate
        if (headerMatches(profile, ColumnRole.Amount)) score += 1.0
        // A column that never goes negative is likelier a balance or a document number.
        if (profile.negativeRate > 0) score += 0.3
        return score
    }
}
