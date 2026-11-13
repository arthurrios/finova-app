//
//  ImportRecurringSafetyTests.swift
//  FinovaTests
//
//  The guard that imported rows cannot disturb the recurring-series machinery.
//
//  This is the regression test for a bug the series code has already been fixed for once. The comment
//  on `RecurringTransactionManager.materializeMissingOccurrences` records that `occupiedSlots` used to
//  be keyed on title alone, so an ordinary one-off could silently claim a month belonging to a real
//  series — and the month would then never generate. A bulk import is the largest possible source of
//  one-offs with plausible titles, so it is exactly the thing that would bring that back.
//
//  Imported rows are safe only because every field the series code keys on is nil. If someone later
//  "improves" the importer by detecting recurring patterns and setting `parentTransactionId`, these
//  tests are what should stop them.
//

import XCTest

@testable import Finova

final class ImportRecurringSafetyTests: XCTestCase {

    private var db: DBHelper!
    private var dbPath: URL!
    private var userUID: String!
    private var txRepo: TransactionRepository!
    private var applyService: ImportApplyService!

    override func setUp() {
        super.setUp()
        // The repository cache is static and keyed only on the user uid, not on the
        // DBHelper instance — so whatever ran before in this process can still be sitting
        // in it. Clearing on the way IN as well as out makes these suites independent of
        // execution order.
        TransactionRepository.invalidateCache()
        userUID = "test_import_recurring_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaImportRecurring-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        txRepo = TransactionRepository(db: db)
        let batchRepo = ImportBatchRepository(db: db, currentUserId: { [userUID] in userUID })
        applyService = ImportApplyService(
            db: db, transactionRepo: txRepo, batchRepo: batchRepo,
            currentUserId: { [userUID] in userUID }, isSyncInProgress: { false })
    }

    override func tearDown() {
        TransactionRepository.invalidateCache()
        UIDUserDefaultsManager.shared.signOut()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        super.tearDown()
    }

    // MARK: - Helpers

    /// Imports rows deliberately shaped to look like a subscription: same title, same amount, same
    /// day of month, month after month. This is the worst case for series confusion.
    @discardableResult
    private func importSubscriptionLookalikes(
        title: String = "NETFLIX.COM", amount: Int = 5_590, months: Int = 6
    ) throws -> ImportBatch {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current

        let rows: [ImportableRow] = (0..<months).compactMap { offset in
            var components = DateComponents()
            components.year = 2026
            components.month = 1 + offset
            components.day = 15
            components.hour = 12
            guard let date = calendar.date(from: components) else { return nil }

            return ImportableRow(
                model: RowNormalizer.model(
                    title: title, category: .subscriptions, type: .expense,
                    date: date, cents: -amount),
                fingerprint: "fp-sub-\(offset)",
                sourceLine: offset + 2)
        }

        return try applyService.apply(ImportApplyRequest(
            sourceFilename: "extrato.csv", fileHash: "sha-sub", fileByteCount: 100,
            bankPresetId: nil, columnMapping: "{}", rowsInFile: rows.count,
            rowsSkipped: 0, rowsFailed: 0, rows: rows))
    }

    /// `materializeAllSeries` is asynchronous with a completion carrying the number generated.
    private func materialize(with manager: RecurringTransactionManager) -> Int {
        let expectation = expectation(description: "materialize")
        var generated = 0
        manager.materializeAllSeries { count in
            generated = count
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
        return generated
    }

    // MARK: - Field-shape invariants

    /// Everything below depends on these being nil. If this test fails, the rest are meaningless.
    func testImportedRowsCarryNoSeriesFields() throws {
        try importSubscriptionLookalikes()

        let offenders = db.fetchSingleInt("""
            SELECT COUNT(*) FROM Transactions
             WHERE parent_transaction_id IS NOT NULL
                OR is_recurring = 1
                OR has_installments = 1
                OR installment_number IS NOT NULL
                OR total_installments IS NOT NULL;
            """)
        XCTAssertEqual(offenders, 0)
    }

    /// `Transaction.mode` is derived purely from field shape, and `.normal` is what keeps a row out of
    /// every series code path.
    func testImportedRowsReadAsNormalMode() throws {
        try importSubscriptionLookalikes()
        let imported = txRepo.fetchAllTransactions()
        XCTAssertEqual(imported.count, 6)
        XCTAssertTrue(imported.allSatisfy { $0.mode == .normal })
    }

    func testImportedRowsAreNotRecurringTransactions() throws {
        try importSubscriptionLookalikes()
        XCTAssertTrue(
            txRepo.fetchRecurringTransactions().isEmpty,
            "six identical monthly charges are still six one-offs until the user says otherwise")
    }

    /// `fetchTransactions` hides series PARENTS. Imported rows must all remain visible.
    func testImportedRowsAreAllVisibleInTheLedger() throws {
        try importSubscriptionLookalikes()
        XCTAssertEqual(txRepo.fetchTransactions().count, 6)
    }

    // MARK: - The occupied-slot regression

    /// The bug this file exists for. A genuine recurring series must generate exactly the same
    /// occurrences whether or not a lookalike import happened first.
    func testAnImportDoesNotBlockMonthsOfARealSeries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        components.hour = 12
        let anchor = try XCTUnwrap(calendar.date(from: components))

        // A real series, created the way the app creates one.
        let parentId = try db.insertTransaction(TransactionModel(
            title: "NETFLIX.COM",
            category: TransactionCategory.subscriptions.key,
            amount: 5_590,
            type: TransactionType.expense.key,
            dateTimestamp: Int(anchor.timeIntervalSince1970),
            budgetMonthDate: anchor.monthAnchor,
            isRecurring: true,
            parentTransactionId: nil))
        db.executeSyncUpdate(
            "UPDATE Transactions SET parent_transaction_id = ? WHERE id = ?;",
            intBindings: [parentId, parentId])
        TransactionRepository.invalidateCache()

        let manager = RecurringTransactionManager(transactionRepo: txRepo, db: db)
        let generatedWithoutImport = materialize(with: manager)
        XCTAssertGreaterThan(
            generatedWithoutImport, 0, "sanity: the series generated its own occurrences")

        let seriesRowsBefore = db.fetchSingleInt(
            "SELECT COUNT(*) FROM Transactions WHERE parent_transaction_id IS NOT NULL;")

        // Same series, plus an import of rows that look exactly like its occurrences.
        try importSubscriptionLookalikes()
        TransactionRepository.invalidateCache()
        let generatedAfterImport = materialize(with: manager)

        XCTAssertEqual(
            generatedAfterImport, 0,
            "the series was already fully materialised; the import must not change that")
        XCTAssertEqual(
            db.fetchSingleInt(
                "SELECT COUNT(*) FROM Transactions WHERE parent_transaction_id IS NOT NULL;"),
            seriesRowsBefore,
            "the import neither added to nor removed from the series")

        // And the series still owns its own occurrences, none of which are the imported rows.
        let seriesRows = txRepo.fetchAllTransactions().filter { $0.parentTransactionId != nil }
        XCTAssertTrue(
            seriesRows.allSatisfy { $0.mode == .recurring },
            "no imported row was adopted into the series")
    }

    /// `RecurringSeriesLinker` guards on `mode == .recurring`, so an imported one-off can never be
    /// adopted even when it shares every visible attribute with a series.
    func testTheSeriesLinkerAdoptsNoImportedRows() throws {
        try importSubscriptionLookalikes()
        let before = db.fetchSingleInt(
            "SELECT COUNT(*) FROM Transactions WHERE parent_transaction_id IS NOT NULL;")

        let linker = RecurringSeriesLinker(transactionRepo: txRepo)
        for transaction in txRepo.fetchAllTransactions() {
            guard let id = transaction.id else { continue }
            XCTAssertEqual(
                linker.repairTransactionSeries(around: id), 0,
                "an imported one-off is not a series parent and must adopt nothing")
        }
        TransactionRepository.invalidateCache()

        let after = db.fetchSingleInt(
            "SELECT COUNT(*) FROM Transactions WHERE parent_transaction_id IS NOT NULL;")
        XCTAssertEqual(after, before, "no imported row gained a parent")
        XCTAssertEqual(after, 0)
    }
}
