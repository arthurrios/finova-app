package com.arthurrios.finova.domain.importer

import com.arthurrios.finova.domain.model.BusinessDayRule
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.text.Normalizer
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth

/**
 * Inference, normalization, dedupe and the plan. All pure, no database. Port of
 * FinovaTests/Import/ImportPlanningTests.swift.
 */
class ImportPlanningTest {
    private lateinit var originalYear: () -> Int

    @Before fun pinYear() {
        originalYear = DateFieldParser.currentYear
        DateFieldParser.currentYear = { 2026 }
    }

    @After fun restoreYear() {
        DateFieldParser.currentYear = originalYear
    }

    // ---- Fixtures ----

    private val ptBRStatement = """
        Data;Descrição;Valor;Saldo
        01/07/2026;COMPRA NO DEBITO - MERCADO EXTRA;-1.234,56;8.765,44
        02/07/2026;PADARIA CENTRAL;-12,50;8.752,94
        05/07/2026;PAGAMENTO DE SALARIO;5.000,00;13.752,94
        10/07/2026;NETFLIX.COM;-55,90;13.697,04
        15/07/2026;UBER *TRIP;-23,40;13.673,64
    """.trimIndent()

    private val debitCreditStatement = """
        Date,Description,Debit,Credit
        2026-07-01,Grocery Store,1234.56,
        2026-07-02,Bakery,12.50,
        2026-07-05,Salary,,5000.00
        2026-07-10,Streaming,55.90,
        2026-07-15,Refund,,23.40
    """.trimIndent()

    private fun makeInput(
        text: String,
        filename: String = "extrato.csv",
        existing: List<Transaction> = emptyList(),
        alreadyImported: Set<String> = emptySet(),
    ) = CsvImportEngine.Input(filename = filename, data = text.toByteArray(Charsets.UTF_8), alreadyImported = alreadyImported, existing = existing)

    /** iOS `ImportPlan.insertableRows`. */
    private val ImportPlan.insertableRows get() = rows.filter { it.disposition.isIncludedByDefault }

    // ---- End-to-end inference ----

    @Test fun ptBRStatementIsFullyUnderstood() {
        val plan = CsvImportEngine.makePlan(makeInput(ptBRStatement))

        assertEquals("dd/MM/yyyy", plan.schema.dateFormat.pattern)
        assertEquals(',', plan.schema.numberFormat.decimalSeparator)
        assertTrue(plan.schema.hasHeaderRow)
        assertEquals(5, plan.rows.size)
        assertTrue("no row should fail on a clean file", plan.failedRows.isEmpty())

        // The balance column proves which column is the amount AND which way the signs run.
        assertEquals(SignConvention.NegativeIsExpense, plan.schema.signConvention)
        assertEquals("a running balance is arithmetic proof, not a guess", 1.0, plan.confidence.signConvention.score, 0.0)
        assertEquals(ColumnRole.Balance, plan.schema.roles[3])
    }

    @Test fun amountsAndDirectionsAreReadCorrectly() {
        val plan = CsvImportEngine.makePlan(makeInput(ptBRStatement))
        val byTitle = plan.rows.mapNotNull { it.parsed }.associateBy { it.title.title }

        assertEquals(-123_456L, byTitle["Mercado Extra"]?.signedCents)
        assertEquals(-1_250L, byTitle["Padaria Central"]?.signedCents)
        // "PAGAMENTO DE SALARIO" loses both its rail prefix and the connector left behind by it.
        assertEquals(500_000L, byTitle["Salario"]?.signedCents)
        assertEquals(-5_590L, byTitle["Netflix.com"]?.signedCents)
    }

    @Test fun splitDebitCreditColumnsAreDetectedByMutualExclusivity() {
        val plan = CsvImportEngine.makePlan(makeInput(debitCreditStatement))
        assertEquals(SignConvention.SeparateDebitCredit, plan.schema.signConvention)
        assertEquals(1.0, plan.confidence.signConvention.score, 0.0)

        val amounts = plan.rows.mapNotNull { it.parsed?.signedCents }.sorted()
        assertEquals(listOf(-123_456L, -5_590L, -1_250L, 2_340L, 500_000L), amounts)
    }

    @Test fun aPreambleBeforeTheHeaderIsSkipped() {
        val text = """
            Extrato de Conta Corrente
            Agência 1234 Conta 56789-0
            Período: 01/07/2026 a 31/07/2026

            Data;Descrição;Valor
            01/07/2026;MERCADO;-50,00
            02/07/2026;PADARIA;-10,00
        """.trimIndent()
        val plan = CsvImportEngine.makePlan(makeInput(text))
        assertEquals(2, plan.rows.size)
        assertTrue(plan.failedRows.isEmpty())
    }

    /** Columns we cannot identify are NOT an error: an unusable, zero-confidence plan routes to mapping. */
    @Test fun aFileWithNoUsableColumnsIsSentToMappingRatherThanRejected() {
        val plan = CsvImportEngine.makePlan(makeInput("name;city\nJoão;São Paulo\nMaria;Rio"))

        assertFalse(plan.schema.isUsable)
        assertEquals(InferenceConfidence.Band.Low, plan.confidence.band)
        assertEquals("the rows are still carried, so the user can see them", 2, plan.rows.size)
        assertTrue("and nothing may be imported until it is mapped", plan.insertableRows.isEmpty())
    }

    /** No tabular shape at all fails outright, and the error reports what was actually observed. */
    @Test fun aFileWithNoColumnsIsRejectedWithDiagnostics() {
        val error = assertThrows(ImportError::class.java) { CsvImportEngine.makePlan(makeInput("just one line of prose")) }
        assertTrue("expected NotTabular, got $error", error is ImportError.NotTabular)
        val details = (error as ImportError.NotTabular).details
        assertTrue("the detected encoding must be reported", details.contains("UTF-8"))
        assertTrue("the column count must be reported", details.contains("col"))
        assertTrue("a preview of the first line must be reported", details.contains("just one line of prose"))
    }

    /** A delimiter the sniffer scored poorly must still be tried before the file is rejected. */
    @Test fun anUnusualDelimiterIsRecoveredByRetrying() {
        val text = "Data\tDescrição\tValor\n15/07/2026\tMERCADO EXTRA\t-50,00\n16/07/2026\tPADARIA\t-12,50\n17/07/2026\tSALARIO\t5.000,00"
        val plan = CsvImportEngine.makePlan(makeInput(text))
        assertEquals(3, plan.rows.size)
        assertTrue(plan.failedRows.isEmpty())
    }

    @Test fun anEmptyFileIsRejected() {
        val error = assertThrows(ImportError::class.java) { CsvImportEngine.makePlan(makeInput("   \n  \n")) }
        assertEquals(ImportError.EmptyFile, error)
    }

    /** Nothing proves which sign means money out, so the rows stop for a decision. */
    @Test fun anUnprovableSignConventionParksRowsForADecision() {
        val text = """
            Data;Descrição;Valor
            01/07/2026;MERCADO;50,00
            02/07/2026;PADARIA;10,00
            05/07/2026;LOJA;20,00
        """.trimIndent()
        val plan = CsvImportEngine.makePlan(makeInput(text))
        assertTrue(plan.confidence.signConvention.score < 0.6)
        assertEquals(3, plan.undecidedRows.size)
        assertTrue("nothing may be imported until the sign is settled", plan.insertableRows.isEmpty())
    }

    /**
     * The weakest link sets the score. (iOS also asserts `weakestAspects == ["signConvention"]`;
     * Android has no `weakestAspects`, so that line is not ported.)
     */
    @Test fun overallConfidenceIsTheMinimumNotTheMean() {
        val confidence = InferenceConfidence(
            header = SubConfidence.proof("x"), dateFormat = SubConfidence.proof("x"), numberFormat = SubConfidence.proof("x"),
            amountShape = SubConfidence.proof("x"), signConvention = SubConfidence.weak("unknown"), columnRoles = SubConfidence.proof("x"),
        )
        assertEquals(0.4, confidence.overall, 0.0)
        assertEquals(InferenceConfidence.Band.Low, confidence.band)
    }

    // ---- Title cleaning ----

    @Test fun railPrefixIsSplitOffRatherThanDeleted() {
        val cleaned = TitleCleaner.clean("COMPRA NO DEBITO - MERCADO EXTRA")
        assertEquals("Débito", cleaned.railHint)
        assertEquals("Mercado Extra", cleaned.title)
    }

    @Test fun acronymsSurviveRecasing() {
        assertEquals("PIX", TitleCleaner.clean("PIX ENVIADO PADARIA").railHint)
        assertTrue(TitleCleaner.recase("TED PARA JOAO S/A").contains("TED"))
        assertTrue(TitleCleaner.recase("TED PARA JOAO S/A").contains("S/A"))
    }

    @Test fun mixedCaseTitlesAreLeftAlone() {
        assertEquals("Netflix.com", TitleCleaner.clean("Netflix.com").title)
    }

    @Test fun installmentMarkerIsRecordedNotActedOn() {
        val cleaned = TitleCleaner.clean("LOJA AMERICANAS 3/12")
        assertEquals(3 to 12, cleaned.installmentHint)
        assertFalse(cleaned.title.contains("3/12"))
    }

    @Test fun trailingDocumentNumberIsStrippedButKept() {
        val cleaned = TitleCleaner.clean("TRANSFERENCIA ENVIADA 123456789")
        assertEquals("123456789", cleaned.strippedDocId)
        assertFalse(cleaned.title.contains("123456789"))
    }

    /** macOS writes NFD. Without normalizing, the same merchant in two files fails to dedupe. */
    @Test fun decomposedAccentsAreNormalisedToNFC() {
        val nfd = "Ação Social" // "Ação Social", decomposed
        assertEquals(Normalizer.normalize("Ação Social", Normalizer.Form.NFC), TitleCleaner.clean(nfd).title)
    }

    /** `title` is required and the main dedupe key, so any non-blank input survives as something. */
    @Test fun anyNonBlankDescriptionYieldsANonEmptyTitle() {
        assertFalse(TitleCleaner.clean("PIX 987654321").title.isEmpty())
        assertFalse(TitleCleaner.clean("TED").title.isEmpty())
        assertFalse(TitleCleaner.clean("123456789").title.isEmpty())
        assertFalse(TitleCleaner.clean("---").title.isEmpty())
    }

    // ---- The Transaction contract ----
    // iOS tests `RowNormalizer.model(...)` directly. Android builds the Transaction in
    // `ImportPlan.resolve`, so the same contract is checked on resolved rows.

    private fun resolvedByTitle(text: String = ptBRStatement): Map<String, Transaction> =
        CsvImportEngine.makePlan(makeInput(text)).resolve(ImportOverrides()).rows.associate { it.transaction.title to it.transaction }

    @Test fun normalizationContract() {
        // iOS passes `.groceries` straight in; here the category arrives as a review-screen override,
        // so the assertion does not depend on the JVM's locale region choosing the pt-BR rules.
        val plan = CsvImportEngine.makePlan(makeInput(ptBRStatement))
        val target = requireNotNull(plan.rows.firstOrNull { it.parsed?.title?.title == "Mercado Extra" })
        val overrides = ImportOverrides().update(target.fingerprint) { it.copy(category = TransactionCategory.Groceries) }
        val model = requireNotNull(plan.resolve(overrides).rows.firstOrNull { it.fingerprint == target.fingerprint }).transaction

        assertEquals("amount is a positive magnitude; direction is in type", 123_456L, model.amount)
        assertEquals(TransactionType.Expense, model.type)
        assertEquals("expense", model.type.key)
        assertEquals("the DB spelling is .key", "groceries", model.category.key)
        assertEquals(YearMonth.from(model.date), model.budgetMonth)
        assertEquals(BusinessDayRule.Exact, model.businessDayRule)

        // Every field that would make this row participate in the series machinery.
        assertFalse(model.isRecurring)
        assertFalse(model.hasInstallments)
        assertNull(model.parentTransactionId)
        assertNull(model.installmentNumber)
        assertNull(model.totalInstallments)
        assertNull(model.originalAmount)
        assertNull(model.creditCardId)
        assertNull(model.statementId)
        assertFalse(model.isCreditCardStatement)
    }

    @Test fun incomeKeepsAPositiveMagnitudeToo() {
        val model = requireNotNull(resolvedByTitle()["Salario"])
        assertEquals(500_000L, model.amount)
        assertEquals("income", model.type.key)
    }

    /** An imported row is a fact that already happened; the business-day adjuster is for scheduling. */
    @Test fun aSaturdayTransactionKeepsItsSaturday() {
        val saturday = requireNotNull(DateFieldParser.parse("04/07/2026", DateFormatSpec("dd/MM/yyyy")))
        assertEquals("fixture is not a Saturday", DayOfWeek.SATURDAY, saturday.dayOfWeek)

        val text = """
            Data;Descrição;Valor;Saldo
            04/07/2026;FEIRA;-50,00;100,00
            15/07/2026;MERCADO;-10,00;90,00
            16/07/2026;PADARIA;-5,00;85,00
        """.trimIndent()
        val model = requireNotNull(resolvedByTitle(text)["Feira"])
        assertEquals(saturday, model.date)
        assertEquals(BusinessDayRule.Exact, model.businessDayRule)
    }

    // ---- Categorization ----

    /** Catches a typo'd category key in CI rather than as a silent "miscellaneous" in production. */
    @Test fun everyShippedRuleResolvesToARealCategory() {
        for (rules in listOf(MerchantRuleData.Base, MerchantRuleData.PtBR)) {
            assertFalse(rules.isEmpty())
            for (rule in rules) {
                assertNotNull(
                    "rule '${rule.id}' names a category that does not exist: ${rule.category}",
                    TransactionCategory.entries.firstOrNull { it.key == rule.category },
                )
                for (pattern in rule.patterns) {
                    assertEquals("pattern '$pattern' in rule '${rule.id}' must be pre-folded", pattern.normalizedForSearch(), pattern)
                }
            }
        }
    }

    @Test fun merchantRulesMatchKnownBrands() {
        val rules = MerchantRuleSet(region = "BR")
        assertEquals(TransactionCategory.Subscriptions, rules.category("netflix.com", TransactionType.Expense))
        assertEquals(TransactionCategory.Groceries, rules.category("supermercado sao jorge", TransactionType.Expense))
        assertEquals(TransactionCategory.Healthcare, rules.category("drogaria pacheco", TransactionType.Expense))
        assertEquals(TransactionCategory.Utilities, rules.category("cemig distribuicao", TransactionType.Expense))
        assertNull(rules.category("algo completamente desconhecido", TransactionType.Expense))
    }

    @Test fun typeConstraintSeparatesIncomeFromExpense() {
        val rules = MerchantRuleSet(region = "BR")
        assertEquals(TransactionCategory.Salary, rules.category("pagamento de salario", TransactionType.Income))
        assertNotEquals(TransactionCategory.Salary, rules.category("pagamento de salario", TransactionType.Expense))
    }

    /** The user's own history beats any shipped list. */
    @Test fun historyBeatsRules() {
        val existing = listOf(
            makeTransaction(title = "NETFLIX.COM", category = TransactionCategory.Entertainment),
            makeTransaction(title = "NETFLIX.COM", category = TransactionCategory.Entertainment),
        )
        val categorizer = DeterministicCategorizer(existing, rules = MerchantRuleSet(region = "BR"))
        val suggestion = categorizer.categorize(TitleCleaner.clean("NETFLIX.COM"), TransactionType.Expense)

        assertEquals("the shipped rule says subscriptions; this user says entertainment", TransactionCategory.Entertainment, suggestion.category)
        assertEquals(CategorySource.History, suggestion.source)
    }

    @Test fun unknownMerchantsFallBackHonestly() {
        val suggestion = DeterministicCategorizer(emptyList()).categorize(TitleCleaner.clean("XPTO 4471 QWERTY"), TransactionType.Expense)
        assertEquals(TransactionCategory.Miscellaneous, suggestion.category)
        assertEquals("labelled as a guess", CategorySource.Fallback, suggestion.source)
    }

    // ---- Similarity and dedupe ----

    /** Jaccard alone scores this 0.5, below threshold; containment catches it. */
    @Test fun containmentCatchesShortenedTitles() {
        assertTrue(TitleSimilarity.score("Netflix", "NETFLIX.COM") >= TitleSimilarity.THRESHOLD)
    }

    @Test fun nearIdenticalMerchantsMatchAndDifferentOnesDoNot() {
        assertTrue(TitleSimilarity.score("PADARIA CENTRAL", "PADARIA CENTRO") >= TitleSimilarity.THRESHOLD)
        assertTrue(TitleSimilarity.score("UBER TRIP", "MERCADO EXTRA") < TitleSimilarity.THRESHOLD)
    }

    private fun padariaRow(plan: ImportPlan) = requireNotNull(plan.rows.firstOrNull { it.parsed?.title?.title == "Padaria Central" })

    @Test fun exactDuplicatesAreExcludedByDefault() {
        val existing = listOf(makeTransaction("Padaria Central", TransactionCategory.Meals, 1_250, TransactionType.Expense, LocalDate.of(2026, 7, 2)))
        val row = padariaRow(CsvImportEngine.makePlan(makeInput(ptBRStatement, existing = existing)))
        assertTrue("expected DuplicateExact, got ${row.disposition}", row.disposition is Disposition.DuplicateExact)
        assertFalse(row.disposition.isIncludedByDefault)
    }

    /** A refund and a charge of the same size on the same day are opposites, not duplicates. */
    @Test fun aRefundDoesNotMatchACharge() {
        val existing = listOf(makeTransaction("Padaria Central", TransactionCategory.Meals, 1_250, TransactionType.Income, LocalDate.of(2026, 7, 2)))
        val row = padariaRow(CsvImportEngine.makePlan(makeInput(ptBRStatement, existing = existing)))
        assertEquals(Disposition.Insert, row.disposition)
    }

    /** Included by default with a badge: a false skip silently loses a real transaction. */
    @Test fun likelyDuplicatesAreIncludedByDefault() {
        val existing = listOf(makeTransaction("Padaria Central Ltda", TransactionCategory.Meals, 1_250, TransactionType.Expense, LocalDate.of(2026, 7, 4)))
        val row = padariaRow(CsvImportEngine.makePlan(makeInput(ptBRStatement, existing = existing)))
        assertTrue("expected DuplicateLikely, got ${row.disposition}", row.disposition is Disposition.DuplicateLikely)
        assertTrue(row.disposition.isIncludedByDefault)
    }

    @Test fun alreadyImportedRowsAreRecognised() {
        val first = CsvImportEngine.makePlan(makeInput(ptBRStatement))
        val fingerprints = first.rows.map { it.fingerprint }.toSet()

        val second = CsvImportEngine.makePlan(makeInput(ptBRStatement, alreadyImported = fingerprints))
        assertEquals(5, second.rows.count { it.disposition == Disposition.AlreadyImported })
        assertTrue(second.insertableRows.isEmpty())
    }

    /** Two identical rows in one file are usually two real transactions. Never collapse them. */
    @Test fun intraFileDuplicatesAreBothKept() {
        // Day 15 proves dd/MM; all-components-under-12 dates would park for a decision instead.
        val text = """
            Data;Descrição;Valor;Saldo
            15/07/2026;CAFE;-5,00;100,00
            15/07/2026;CAFE;-5,00;95,00
            16/07/2026;MERCADO;-50,00;45,00
        """.trimIndent()
        val plan = CsvImportEngine.makePlan(makeInput(text))
        val cafes = plan.rows.filter { it.parsed?.title?.title == "Cafe" }
        assertEquals(2, cafes.size)
        assertTrue(cafes.all { it.disposition.isIncludedByDefault })
        assertEquals(3, plan.insertableRows.size)
    }

    // ---- Plan, overrides and resolve ----

    @Test fun resolveHonoursTheRowCountInvariant() {
        val plan = CsvImportEngine.makePlan(makeInput(ptBRStatement))
        val resolved = plan.resolve(ImportOverrides())
        assertEquals(plan.rows.size, resolved.rows.size + resolved.skippedCount + resolved.failedCount)
    }

    @Test fun aCategoryOverrideWins() {
        val plan = CsvImportEngine.makePlan(makeInput(ptBRStatement))
        val target = padariaRow(plan)

        val overrides = ImportOverrides().update(target.fingerprint) { it.copy(category = TransactionCategory.Gifts) }

        val row = requireNotNull(plan.resolve(overrides).rows.firstOrNull { it.fingerprint == target.fingerprint })
        assertEquals("gifts", row.transaction.category.key)
    }

    @Test fun forcingAnExactDuplicateInWorks() {
        val existing = listOf(makeTransaction("Padaria Central", TransactionCategory.Meals, 1_250, TransactionType.Expense, LocalDate.of(2026, 7, 2)))
        val plan = CsvImportEngine.makePlan(makeInput(ptBRStatement, existing = existing))
        val target = padariaRow(plan)

        assertNull(plan.resolve(ImportOverrides()).rows.firstOrNull { it.fingerprint == target.fingerprint })

        val overrides = ImportOverrides().update(target.fingerprint) { it.copy(isIncluded = true) }
        assertNotNull(plan.resolve(overrides).rows.firstOrNull { it.fingerprint == target.fingerprint })
    }

    @Test fun excludingARowRemovesItEntirely() {
        val plan = CsvImportEngine.makePlan(makeInput(ptBRStatement))
        val target = plan.rows.first()

        val overrides = ImportOverrides().update(target.fingerprint) { it.copy(isIncluded = false) }

        val resolved = plan.resolve(overrides)
        assertNull(resolved.rows.firstOrNull { it.fingerprint == target.fingerprint })
        assertEquals(plan.insertableRows.size - 1, resolved.rows.size)
    }

    /** Fingerprints are over the raw bytes, so they survive re-inference: going back to mapping is lossless. */
    @Test fun fingerprintsAreStableAcrossReplanning() {
        val input = makeInput(ptBRStatement)
        val first = CsvImportEngine.makePlan(input)

        val schema = first.schema.copy(dateFormat = DateFormatSpec("dd/MM/yyyy"))
        val second = CsvImportEngine.replan(input, schema, first)

        assertEquals(first.rows.map { it.fingerprint }.toSet(), second.rows.map { it.fingerprint }.toSet())
    }

    @Test fun overridesForAbsentFingerprintsAreRetained() {
        val overrides = ImportOverrides().update("fingerprint-not-in-this-plan") { it.copy(isIncluded = false) }
        assertNotNull("bouncing between screens must not silently drop the user's edits", overrides.byFingerprint["fingerprint-not-in-this-plan"])
    }

    @Test fun anEmptyOverrideIsDiscarded() {
        val overrides = ImportOverrides()
            .update("fp") { it.copy(category = TransactionCategory.Meals) }
            .update("fp") { it.copy(category = null) }
        assertNull(overrides.byFingerprint["fp"])
    }

    // ---- Helpers ----

    private var nextId = 1L

    private fun makeTransaction(
        title: String,
        category: TransactionCategory,
        amount: Long = 1_000,
        type: TransactionType = TransactionType.Expense,
        date: LocalDate = LocalDate.of(2026, 7, 1),
    ) = Transaction(
        id = nextId++,
        title = title,
        category = category,
        type = type,
        amount = amount,
        date = date,
        budgetMonth = YearMonth.from(date),
    )
}
