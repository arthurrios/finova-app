//
//  ImportPlanningTests.swift
//  FinovaTests
//
//  Inference, normalization, dedupe and the plan. All pure — no database anywhere in this file.
//

import XCTest

@testable import Finova

final class ImportPlanningTests: XCTestCase {

    // MARK: - Fixtures

    private let ptBRStatement = """
    Data;Descrição;Valor;Saldo
    01/07/2026;COMPRA NO DEBITO - MERCADO EXTRA;-1.234,56;8.765,44
    02/07/2026;PADARIA CENTRAL;-12,50;8.752,94
    05/07/2026;PAGAMENTO DE SALARIO;5.000,00;13.752,94
    10/07/2026;NETFLIX.COM;-55,90;13.697,04
    15/07/2026;UBER *TRIP;-23,40;13.673,64
    """

    private let debitCreditStatement = """
    Date,Description,Debit,Credit
    2026-07-01,Grocery Store,1234.56,
    2026-07-02,Bakery,12.50,
    2026-07-05,Salary,,5000.00
    2026-07-10,Streaming,55.90,
    2026-07-15,Refund,,23.40
    """

    private func makeInput(
        _ text: String, filename: String = "extrato.csv",
        existing: [Transaction] = [], alreadyImported: Set<String> = []
    ) -> CSVImportEngine.Input {
        CSVImportEngine.Input(
            filename: filename, data: Data(text.utf8),
            alreadyImported: alreadyImported, existing: existing)
    }

    // MARK: - End-to-end inference

    func testPtBRStatementIsFullyUnderstood() throws {
        let plan = try CSVImportEngine.makePlan(makeInput(ptBRStatement))

        XCTAssertEqual(plan.schema.dateFormat.pattern, "dd/MM/yyyy")
        XCTAssertEqual(plan.schema.numberFormat.decimalSeparator, ",")
        XCTAssertTrue(plan.schema.hasHeaderRow)
        XCTAssertEqual(plan.rows.count, 5)
        XCTAssertTrue(plan.failedRows.isEmpty, "no row should fail on a clean file")

        // The balance column proves which column is the amount AND which way the signs run.
        XCTAssertEqual(plan.schema.signConvention, .negativeIsExpense)
        XCTAssertEqual(plan.confidence.signConvention.score, 1.0,
                       "a running balance is arithmetic proof, not a guess")
        XCTAssertEqual(plan.schema.roles[3], .balance)
    }

    func testAmountsAndDirectionsAreReadCorrectly() throws {
        let plan = try CSVImportEngine.makePlan(makeInput(ptBRStatement))
        let byTitle = Dictionary(uniqueKeysWithValues: plan.rows.compactMap { row -> (String, ParsedRow)? in
            row.parsed.map { ($0.title.title, $0) }
        })

        XCTAssertEqual(byTitle["Mercado Extra"]?.signedCents, -123_456)
        XCTAssertEqual(byTitle["Padaria Central"]?.signedCents, -1_250)
        // "PAGAMENTO DE SALARIO" loses both its rail prefix and the connector left behind by it.
        XCTAssertEqual(byTitle["Salario"]?.signedCents, 500_000)
        XCTAssertEqual(byTitle["Netflix.com"]?.signedCents, -5_590)
    }

    func testSplitDebitCreditColumnsAreDetectedByMutualExclusivity() throws {
        let plan = try CSVImportEngine.makePlan(makeInput(debitCreditStatement))
        XCTAssertEqual(plan.schema.signConvention, .separateDebitCredit)
        XCTAssertEqual(plan.confidence.signConvention.score, 1.0)

        let amounts = plan.rows.compactMap { $0.parsed?.signedCents }.sorted()
        XCTAssertEqual(amounts, [-123_456, -5_590, -1_250, 2_340, 500_000])
    }

    func testAPreambleBeforeTheHeaderIsSkipped() throws {
        let text = """
        Extrato de Conta Corrente
        Agência 1234 Conta 56789-0
        Período: 01/07/2026 a 31/07/2026

        Data;Descrição;Valor
        01/07/2026;MERCADO;-50,00
        02/07/2026;PADARIA;-10,00
        """
        let plan = try CSVImportEngine.makePlan(makeInput(text))
        XCTAssertEqual(plan.rows.count, 2)
        XCTAssertTrue(plan.failedRows.isEmpty)
    }

    /// A table whose columns we cannot identify is NOT an error — it is a file the user maps by hand.
    /// The plan comes back unusable and at zero confidence, which is what routes them to the mapping
    /// screen instead of a dead-end alert.
    func testAFileWithNoUsableColumnsIsSentToMappingRatherThanRejected() throws {
        let text = "name;city\nJoão;São Paulo\nMaria;Rio"
        let plan = try CSVImportEngine.makePlan(makeInput(text))

        XCTAssertFalse(plan.schema.isUsable)
        XCTAssertEqual(plan.confidence.band, .low)
        XCTAssertEqual(plan.rows.count, 2, "the rows are still carried, so the user can see them")
        XCTAssertTrue(plan.insertableRows.isEmpty, "and nothing may be imported until it is mapped")
    }

    /// A file with no tabular shape at all still fails outright — there is nothing to map. The error
    /// must report what was actually observed, because "no date and amount columns" is a lie here:
    /// the real problem is upstream, and a generic message sends the user hunting in the wrong place.
    func testAFileWithNoColumnsIsRejectedWithDiagnostics() {
        XCTAssertThrowsError(try CSVImportEngine.makePlan(makeInput("just one line of prose"))) { error in
            guard case ImportError.notTabular(let details) = error else {
                return XCTFail("expected .notTabular, got \(error)")
            }
            XCTAssertTrue(details.contains("UTF-8"), "the detected encoding must be reported")
            XCTAssertTrue(details.contains("col"), "the column count must be reported")
            XCTAssertTrue(details.contains("just one line of prose"),
                          "a preview of the first line must be reported")
        }
    }

    /// A delimiter the sniffer scored poorly must still be tried before the file is rejected — a
    /// wrong pick collapses everything into one column and fails the whole import.
    func testAnUnusualDelimiterIsRecoveredByRetrying() throws {
        let text = """
        Data	Descrição	Valor
        15/07/2026	MERCADO EXTRA	-50,00
        16/07/2026	PADARIA	-12,50
        17/07/2026	SALARIO	5.000,00
        """
        let plan = try CSVImportEngine.makePlan(makeInput(text))
        XCTAssertEqual(plan.rows.count, 3)
        XCTAssertTrue(plan.failedRows.isEmpty)
    }

    func testAnEmptyFileIsRejected() {
        XCTAssertThrowsError(try CSVImportEngine.makePlan(makeInput("   \n  \n"))) { error in
            XCTAssertEqual(error as? ImportError, .emptyFile)
        }
    }

    /// Without a balance column, a D/C flag or split columns, nothing in the file proves which sign
    /// means money out — and guessing inverts a month of the ledger. The rows must stop for a
    /// decision rather than sail through.
    func testAnUnprovableSignConventionParksRowsForADecision() throws {
        let text = """
        Data;Descrição;Valor
        01/07/2026;MERCADO;50,00
        02/07/2026;PADARIA;10,00
        05/07/2026;LOJA;20,00
        """
        let plan = try CSVImportEngine.makePlan(makeInput(text))
        XCTAssertLessThan(plan.confidence.signConvention.score, 0.6)
        XCTAssertEqual(plan.undecidedRows.count, 3)
        XCTAssertTrue(plan.insertableRows.isEmpty, "nothing may be imported until the sign is settled")
    }

    /// The weakest link sets the score — a certain date must not average away an unknown sign.
    func testOverallConfidenceIsTheMinimumNotTheMean() {
        let confidence = InferenceConfidence(
            header: .proof("x"), dateFormat: .proof("x"), numberFormat: .proof("x"),
            amountShape: .proof("x"), signConvention: .weak("unknown"), columnRoles: .proof("x"))
        XCTAssertEqual(confidence.overall, 0.4)
        XCTAssertEqual(confidence.band, .low)
        XCTAssertEqual(confidence.weakestAspects, ["signConvention"])
    }

    // MARK: - Title cleaning

    func testRailPrefixIsSplitOffRatherThanDeleted() {
        let cleaned = TitleCleaner.clean("COMPRA NO DEBITO - MERCADO EXTRA")
        XCTAssertEqual(cleaned.railHint, "Débito")
        XCTAssertEqual(cleaned.title, "Mercado Extra")
    }

    func testAcronymsSurviveRecasing() {
        XCTAssertEqual(TitleCleaner.clean("PIX ENVIADO PADARIA").railHint, "PIX")
        XCTAssertTrue(TitleCleaner.recase("TED PARA JOAO S/A").contains("TED"))
        XCTAssertTrue(TitleCleaner.recase("TED PARA JOAO S/A").contains("S/A"))
    }

    func testMixedCaseTitlesAreLeftAlone() {
        XCTAssertEqual(TitleCleaner.clean("Netflix.com").title, "Netflix.com")
    }

    func testInstallmentMarkerIsRecordedNotActedOn() {
        let cleaned = TitleCleaner.clean("LOJA AMERICANAS 3/12")
        XCTAssertEqual(cleaned.installmentHint, InstallmentHint(index: 3, total: 12))
        XCTAssertFalse(cleaned.title.contains("3/12"))
    }

    func testTrailingDocumentNumberIsStrippedButKept() {
        let cleaned = TitleCleaner.clean("TRANSFERENCIA ENVIADA 123456789")
        XCTAssertEqual(cleaned.strippedDocId, "123456789")
        XCTAssertFalse(cleaned.title.contains("123456789"))
    }

    /// macOS writes NFD. Without normalizing, the same merchant in two files fails to dedupe against
    /// itself.
    func testDecomposedAccentsAreNormalisedToNFC() {
        let nfd = "Ac\u{0327}a\u{0303}o Social"   // "Ação Social", decomposed
        let cleaned = TitleCleaner.clean(nfd)
        XCTAssertEqual(cleaned.title, "Ação Social".precomposedStringWithCanonicalMapping)
    }

    /// `title` is NOT NULL in the schema and is the primary dedupe key, so any non-blank input must
    /// survive cleaning as something.
    func testAnyNonBlankDescriptionYieldsANonEmptyTitle() {
        // Nothing left after stripping the rail and the doc number — must fall back, not vanish.
        XCTAssertFalse(TitleCleaner.clean("PIX 987654321").title.isEmpty)
        XCTAssertFalse(TitleCleaner.clean("TED").title.isEmpty)
        XCTAssertFalse(TitleCleaner.clean("123456789").title.isEmpty)
        XCTAssertFalse(TitleCleaner.clean("---").title.isEmpty)
    }

    // MARK: - The TransactionModel contract

    func testNormalizationContract() {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let model = RowNormalizer.model(
            title: "Mercado", category: .groceries, type: .expense, date: date, cents: -12_345)

        XCTAssertEqual(model.data.amount, 12_345, "amount is a positive magnitude; direction is in type")
        XCTAssertEqual(model.data.type, "expense")
        XCTAssertEqual(model.data.category, "groceries", "the DB spelling is .key, not .rawValue")
        XCTAssertEqual(model.data.budgetMonthDate, date.monthAnchor)
        XCTAssertEqual(model.data.businessDayRule, .exact)

        // Every field that would make this row participate in the series machinery.
        XCTAssertNil(model.data.isRecurring)
        XCTAssertNil(model.data.hasInstallments)
        XCTAssertNil(model.data.parentTransactionId)
        XCTAssertNil(model.data.installmentNumber)
        XCTAssertNil(model.data.totalInstallments)
        XCTAssertNil(model.data.originalAmount)
        XCTAssertNil(model.data.creditCardId)
        XCTAssertNil(model.data.statementId)
        XCTAssertNil(model.data.isCreditCardStatement)
    }

    func testIncomeKeepsAPositiveMagnitudeToo() {
        let model = RowNormalizer.model(
            title: "Salário", category: .salary, type: .income, date: Date(), cents: 500_000)
        XCTAssertEqual(model.data.amount, 500_000)
        XCTAssertEqual(model.data.type, "income")
    }

    /// An imported row is a fact that already happened; the business-day adjuster is for scheduling.
    func testASaturdayTransactionKeepsItsSaturday() throws {
        let saturday = try XCTUnwrap(
            DateFieldParser.parse("04/07/2026", spec: DateFormatSpec(pattern: "dd/MM/yyyy")))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        try XCTSkipUnless(calendar.component(.weekday, from: saturday) == 7, "fixture is not a Saturday")

        let model = RowNormalizer.model(
            title: "Feira", category: .groceries, type: .expense, date: saturday, cents: -5_000)
        XCTAssertEqual(model.data.dateTimestamp, Int(saturday.timeIntervalSince1970))
    }

    // MARK: - Categorization

    func testEveryShippedRuleResolvesToARealCategory() throws {
        // Catches a typo'd category key at CI rather than as a silent "miscellaneous" in production.
        for json in [MerchantRuleData.baseJSON, MerchantRuleData.ptBRJSON] {
            let rules = try JSONDecoder().decode([MerchantRule].self, from: Data(json.utf8))
            XCTAssertFalse(rules.isEmpty)
            for rule in rules {
                XCTAssertNotNil(
                    TransactionCategory.allCases.first { $0.key == rule.category },
                    "rule '\(rule.id)' names a category that does not exist: \(rule.category)")
                for pattern in rule.patterns {
                    XCTAssertEqual(pattern, pattern.normalizedForSearch(),
                                   "pattern '\(pattern)' in rule '\(rule.id)' must be pre-folded")
                }
            }
        }
    }

    func testMerchantRulesMatchKnownBrands() {
        let rules = MerchantRuleSet(forcedLocaleRegion: "BR")
        XCTAssertEqual(rules.category(for: "netflix.com", type: .expense), .subscriptions)
        XCTAssertEqual(rules.category(for: "supermercado sao jorge", type: .expense), .groceries)
        XCTAssertEqual(rules.category(for: "drogaria pacheco", type: .expense), .healthcare)
        XCTAssertEqual(rules.category(for: "cemig distribuicao", type: .expense), .utilities)
        XCTAssertNil(rules.category(for: "algo completamente desconhecido", type: .expense))
    }

    func testTypeConstraintSeparatesIncomeFromExpense() {
        let rules = MerchantRuleSet(forcedLocaleRegion: "BR")
        XCTAssertEqual(rules.category(for: "pagamento de salario", type: .income), .salary)
        XCTAssertNotEqual(rules.category(for: "pagamento de salario", type: .expense), .salary)
    }

    /// The user's own history beats any shipped list, because it is built from merchants they
    /// actually visit.
    func testHistoryBeatsRules() {
        let existing = [
            makeTransaction(title: "NETFLIX.COM", category: .entertainment),
            makeTransaction(title: "NETFLIX.COM", category: .entertainment),
        ]
        let categorizer = DeterministicCategorizer(
            existing: existing, rules: MerchantRuleSet(forcedLocaleRegion: "BR"))
        let suggestion = categorizer.categorize(
            title: TitleCleaner.clean("NETFLIX.COM"), type: .expense)

        XCTAssertEqual(suggestion.category, .entertainment,
                       "the shipped rule says subscriptions; this user says entertainment")
        XCTAssertEqual(suggestion.source, .history)
    }

    func testUnknownMerchantsFallBackHonestly() {
        let categorizer = DeterministicCategorizer(existing: [])
        let suggestion = categorizer.categorize(
            title: TitleCleaner.clean("XPTO 4471 QWERTY"), type: .expense)
        XCTAssertEqual(suggestion.category, .miscellaneous)
        XCTAssertEqual(suggestion.source, .fallback,
                       "labelled as a guess, which is what lets the model layer improve on it")
    }

    // MARK: - Similarity and dedupe

    /// Jaccard alone scores this 0.5 — below threshold — and it is the single most common real
    /// duplicate. Containment is what catches it.
    func testContainmentCatchesShortenedTitles() {
        XCTAssertGreaterThanOrEqual(
            TitleSimilarity.score("Netflix", "NETFLIX.COM"), TitleSimilarity.threshold)
    }

    func testNearIdenticalMerchantsMatchAndDifferentOnesDoNot() {
        XCTAssertGreaterThanOrEqual(
            TitleSimilarity.score("PADARIA CENTRAL", "PADARIA CENTRO"), TitleSimilarity.threshold)
        XCTAssertLessThan(
            TitleSimilarity.score("UBER TRIP", "MERCADO EXTRA"), TitleSimilarity.threshold)
    }

    func testExactDuplicatesAreExcludedByDefault() throws {
        let existing = [makeTransaction(
            title: "Padaria Central", category: .meals, amount: 1_250, type: .expense,
            date: dateOf("02/07/2026"))]

        let plan = try CSVImportEngine.makePlan(makeInput(ptBRStatement, existing: existing))
        let row = try XCTUnwrap(plan.rows.first { $0.parsed?.title.title == "Padaria Central" })
        guard case .duplicateExact = row.disposition else {
            return XCTFail("expected .duplicateExact, got \(row.disposition)")
        }
        XCTAssertFalse(row.disposition.isIncludedByDefault)
    }

    /// A refund and a charge of the same size on the same day are opposites, not duplicates. Without
    /// signing the key, one of them silently disappears.
    func testARefundDoesNotMatchACharge() throws {
        let existing = [makeTransaction(
            title: "Padaria Central", category: .meals, amount: 1_250, type: .income,
            date: dateOf("02/07/2026"))]

        let plan = try CSVImportEngine.makePlan(makeInput(ptBRStatement, existing: existing))
        let row = try XCTUnwrap(plan.rows.first { $0.parsed?.title.title == "Padaria Central" })
        XCTAssertEqual(row.disposition, .insert)
    }

    /// Included by default with a badge: a false skip silently loses a real transaction, which is
    /// strictly worse than a visible duplicate the user removes in two taps.
    func testLikelyDuplicatesAreIncludedByDefault() throws {
        let existing = [makeTransaction(
            title: "Padaria Central Ltda", category: .meals, amount: 1_250, type: .expense,
            date: dateOf("04/07/2026"))]   // two days later

        let plan = try CSVImportEngine.makePlan(makeInput(ptBRStatement, existing: existing))
        let row = try XCTUnwrap(plan.rows.first { $0.parsed?.title.title == "Padaria Central" })
        guard case .duplicateLikely = row.disposition else {
            return XCTFail("expected .duplicateLikely, got \(row.disposition)")
        }
        XCTAssertTrue(row.disposition.isIncludedByDefault)
    }

    func testAlreadyImportedRowsAreRecognised() throws {
        let first = try CSVImportEngine.makePlan(makeInput(ptBRStatement))
        let fingerprints = Set(first.rows.map(\.fingerprint))

        let second = try CSVImportEngine.makePlan(
            makeInput(ptBRStatement, alreadyImported: fingerprints))
        XCTAssertEqual(second.rows.filter { $0.disposition == .alreadyImported }.count, 5)
        XCTAssertTrue(second.insertableRows.isEmpty)
    }

    /// Two identical rows in one file are usually two real transactions. Never collapse them.
    func testIntraFileDuplicatesAreBothKept() throws {
        // Day 15 proves dd/MM. Dates where every component is ≤ 12 are genuinely ambiguous and the
        // engine correctly parks them for a decision instead — which is a different test.
        let text = """
        Data;Descrição;Valor;Saldo
        15/07/2026;CAFE;-5,00;100,00
        15/07/2026;CAFE;-5,00;95,00
        16/07/2026;MERCADO;-50,00;45,00
        """
        let plan = try CSVImportEngine.makePlan(makeInput(text))
        let cafes = plan.rows.filter { $0.parsed?.title.title == "Cafe" }
        XCTAssertEqual(cafes.count, 2)
        XCTAssertTrue(cafes.allSatisfy { $0.disposition.isIncludedByDefault })
        XCTAssertEqual(plan.insertableRows.count, 3)
    }

    // MARK: - Plan, overrides and resolve

    func testResolveHonoursTheRowCountInvariant() throws {
        let plan = try CSVImportEngine.makePlan(makeInput(ptBRStatement))
        let resolved = plan.resolve(with: ImportOverrides())
        XCTAssertEqual(resolved.rows.count + resolved.skippedCount + resolved.failedCount,
                       plan.rows.count)
    }

    func testACategoryOverrideWins() throws {
        let plan = try CSVImportEngine.makePlan(makeInput(ptBRStatement))
        let target = try XCTUnwrap(plan.rows.first { $0.parsed?.title.title == "Padaria Central" })

        var overrides = ImportOverrides()
        overrides.update(target.fingerprint) { $0.categoryKey = TransactionCategory.gifts.key }

        let resolved = plan.resolve(with: overrides)
        let row = try XCTUnwrap(resolved.rows.first { $0.fingerprint == target.fingerprint })
        XCTAssertEqual(row.model.data.category, "gifts")
    }

    func testForcingAnExactDuplicateInWorks() throws {
        let existing = [makeTransaction(
            title: "Padaria Central", category: .meals, amount: 1_250, type: .expense,
            date: dateOf("02/07/2026"))]
        let plan = try CSVImportEngine.makePlan(makeInput(ptBRStatement, existing: existing))
        let target = try XCTUnwrap(plan.rows.first { $0.parsed?.title.title == "Padaria Central" })

        XCTAssertNil(plan.resolve(with: ImportOverrides()).rows
            .first { $0.fingerprint == target.fingerprint })

        var overrides = ImportOverrides()
        overrides.update(target.fingerprint) { $0.isIncluded = true }
        XCTAssertNotNil(plan.resolve(with: overrides).rows
            .first { $0.fingerprint == target.fingerprint })
    }

    func testExcludingARowRemovesItEntirely() throws {
        let plan = try CSVImportEngine.makePlan(makeInput(ptBRStatement))
        let target = try XCTUnwrap(plan.rows.first)

        var overrides = ImportOverrides()
        overrides.update(target.fingerprint) { $0.isIncluded = false }

        let resolved = plan.resolve(with: overrides)
        XCTAssertNil(resolved.rows.first { $0.fingerprint == target.fingerprint })
        XCTAssertEqual(resolved.rows.count, plan.insertableRows.count - 1)
    }

    /// Fingerprints are computed over the raw bytes, so they survive re-inference. That is what makes
    /// going back to the mapping screen lossless.
    func testFingerprintsAreStableAcrossReplanning() throws {
        let input = makeInput(ptBRStatement)
        let first = try CSVImportEngine.makePlan(input)

        var schema = first.schema
        schema.dateFormat = DateFormatSpec(pattern: "dd/MM/yyyy")
        let second = try CSVImportEngine.replan(input, schema: schema)

        XCTAssertEqual(Set(first.rows.map(\.fingerprint)), Set(second.rows.map(\.fingerprint)))
    }

    func testOverridesForAbsentFingerprintsAreRetained() {
        var overrides = ImportOverrides()
        overrides.update("fingerprint-not-in-this-plan") { $0.isIncluded = false }
        XCTAssertNotNil(overrides.override(for: "fingerprint-not-in-this-plan"),
                        "bouncing between screens must not silently drop the user's edits")
    }

    func testAnEmptyOverrideIsDiscarded() {
        var overrides = ImportOverrides()
        overrides.update("fp") { $0.categoryKey = "meals" }
        overrides.update("fp") { $0.categoryKey = nil }
        XCTAssertNil(overrides.override(for: "fp"))
    }

    // MARK: - Helpers

    private func dateOf(_ text: String) -> Date {
        DateFieldParser.parse(text, spec: DateFormatSpec(pattern: "dd/MM/yyyy")) ?? Date()
    }

    private func makeTransaction(
        title: String,
        category: TransactionCategory,
        amount: Int = 1_000,
        type: TransactionType = .expense,
        date: Date = Date()
    ) -> Transaction {
        Transaction(data: UITransactionData(
            id: Int.random(in: 1...100_000),
            title: title,
            amount: amount,
            dateTimestamp: Int(date.timeIntervalSince1970),
            budgetMonthDate: date.monthAnchor,
            isRecurring: nil,
            hasInstallments: nil,
            parentTransactionId: nil,
            installmentNumber: nil,
            totalInstallments: nil,
            originalAmount: nil,
            category: category,
            type: type
        ))
    }
}
