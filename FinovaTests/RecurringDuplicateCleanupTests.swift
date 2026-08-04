//
//  RecurringDuplicateCleanupTests.swift
//  FinovaTests
//
//  This cleanup deletes rows the user cannot get back, so what it selects matters more than that it
//  runs. These pin the selection: one survivor per slot, the synced row preferred, and nothing
//  touched that isn't a generated recurring child.
//

import XCTest

@testable import Finova

final class RecurringDuplicateCleanupTests: XCTestCase {

    private var dbPath: URL!
    private var db: DBHelper!
    private var repo: TransactionRepository!

    override func setUp() {
        super.setUp()
        UIDUserDefaultsManager.shared.currentUserUID = "test_dupe_\(UUID().uuidString)"
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("dupe-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        repo = TransactionRepository(db: db)
        TransactionRepository.invalidateCache()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dbPath)
        TransactionRepository.invalidateCache()
        super.tearDown()
    }

    // MARK: - Helpers

    private let october = 1_759_276_800  // 2025-10-01
    private let november = 1_761_955_200  // 2025-11-01

    @discardableResult
    private func insertOccurrence(
        parentId: Int?,
        slot: Int,
        accountingMonth: Int? = nil,
        installmentNumber: Int? = nil,
        title: String = "Salary"
    ) -> Int {
        let model = TransactionModel(
            title: title,
            category: "salary",
            amount: 1000,
            type: "income",
            dateTimestamp: slot,
            budgetMonthDate: accountingMonth ?? slot,
            isRecurring: parentId == nil ? true : nil,
            parentTransactionId: parentId,
            installmentNumber: installmentNumber,
            totalInstallments: installmentNumber == nil ? nil : 6,
            seriesPeriod: slot
        )
        return (try? repo.insertTransactionAndGetId(model)) ?? -1
    }

    private func liveIds() -> [Int] {
        TransactionRepository.invalidateCache()
        return repo.fetchAllTransactions().compactMap(\.id).sorted()
    }

    // MARK: - Selection

    func testKeepsExactlyOneOccurrencePerSlot() {
        let parent = insertOccurrence(parentId: nil, slot: october)
        let first = insertOccurrence(parentId: parent, slot: november)
        let second = insertOccurrence(parentId: parent, slot: november)
        let third = insertOccurrence(parentId: parent, slot: november)

        let groups = RecurringDuplicateCleanup.findDuplicates(db: db)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.keep, first, "the oldest row survives")
        XCTAssertEqual(groups.first?.remove.sorted(), [second, third].sorted())

        RecurringDuplicateCleanup.run(repository: repo, db: db)

        let live = liveIds()
        XCTAssertTrue(live.contains(first))
        XCTAssertFalse(live.contains(second))
        XCTAssertFalse(live.contains(third))
    }

    /// The duplicates the bug produced share a slot but sit in DIFFERENT accounting months - that is
    /// the whole shape of the defect. Keying on `budget_month_date` would miss them entirely.
    func testFindsDuplicatesThatLandedInDifferentAccountingMonths() {
        let parent = insertOccurrence(parentId: nil, slot: october)
        insertOccurrence(parentId: parent, slot: november, accountingMonth: october)
        insertOccurrence(parentId: parent, slot: november, accountingMonth: november)

        XCTAssertEqual(
            RecurringDuplicateCleanup.findDuplicates(db: db).count, 1,
            "same slot, different months, still one occurrence")
    }

    func testPrefersTheRowCloudKitAlreadyKnows() {
        let parent = insertOccurrence(parentId: nil, slot: october)
        let older = insertOccurrence(parentId: parent, slot: november)
        let synced = insertOccurrence(parentId: parent, slot: november)
        repo.setCKRecordId(for: synced, ckRecordName: "transaction-\(UUID().uuidString)")

        let groups = RecurringDuplicateCleanup.findDuplicates(db: db)
        XCTAssertEqual(
            groups.first?.keep, synced,
            "keeping the row peers already have avoids a delete-then-recreate round trip")
        XCTAssertEqual(groups.first?.remove, [older])
    }

    // MARK: - What it must never touch

    func testLeavesDistinctSlotsAlone() {
        let parent = insertOccurrence(parentId: nil, slot: october)
        insertOccurrence(parentId: parent, slot: october)
        insertOccurrence(parentId: parent, slot: november)

        XCTAssertTrue(RecurringDuplicateCleanup.findDuplicates(db: db).isEmpty)
    }

    func testIgnoresTheSeriesParentItself() {
        let parent = insertOccurrence(parentId: nil, slot: october)
        try? db.updateTransactionParentId(transactionId: parent, parentId: parent)
        insertOccurrence(parentId: parent, slot: october)

        XCTAssertTrue(
            RecurringDuplicateCleanup.findDuplicates(db: db).isEmpty,
            "a parent pointing at itself is not a duplicate of its own child")
    }

    func testIgnoresInstallmentChildren() {
        let parent = insertOccurrence(parentId: nil, slot: october)
        insertOccurrence(parentId: parent, slot: november, installmentNumber: 1)
        insertOccurrence(parentId: parent, slot: november, installmentNumber: 2)

        XCTAssertTrue(
            RecurringDuplicateCleanup.findDuplicates(db: db).isEmpty,
            "installments are keyed by number, not by month")
    }

    func testIgnoresStandaloneTransactions() {
        insertOccurrence(parentId: nil, slot: october, title: "Coffee")
        insertOccurrence(parentId: nil, slot: october, title: "Coffee")

        XCTAssertTrue(
            RecurringDuplicateCleanup.findDuplicates(db: db).isEmpty,
            "two identical user-created transactions are legitimate and must survive")
    }

    // MARK: - Accounting repair

    /// The state your October/November cards were left in: November's occurrence had been pulled back
    /// to 30 October and was counting in October, so October showed two salaries and November none.
    func testMovesOccurrencesBackToTheMonthTheyAreScheduledFor() {
        let parent = insertOccurrence(parentId: nil, slot: october)
        let octobers = insertOccurrence(parentId: parent, slot: october, accountingMonth: october)
        // November's occurrence, mis-counted in October.
        let novembers = insertOccurrence(parentId: parent, slot: november, accountingMonth: october)

        RecurringDuplicateCleanup.run(repository: repo, db: db)
        TransactionRepository.invalidateCache()

        let rows = repo.fetchAllTransactions()
        XCTAssertEqual(
            rows.first(where: { $0.id == novembers })?.budgetMonthDate, november,
            "November's occurrence must count in November again")
        XCTAssertEqual(
            rows.first(where: { $0.id == octobers })?.budgetMonthDate, october,
            "October's own occurrence is untouched")
        // Neither is deleted: two occurrences that merely landed on the same day are not duplicates.
        XCTAssertTrue(liveIds().contains(octobers))
        XCTAssertTrue(liveIds().contains(novembers))
    }

    func testRepairLeavesCorrectlyAnchoredRowsAlone() {
        let parent = insertOccurrence(parentId: nil, slot: october)
        let ok = insertOccurrence(parentId: parent, slot: november, accountingMonth: november)

        XCTAssertEqual(db.repairSeriesAccountingMonths(), 0)
        TransactionRepository.invalidateCache()
        XCTAssertEqual(
            repo.fetchAllTransactions().first(where: { $0.id == ok })?.budgetMonthDate, november)
    }

    // MARK: - Idempotency

    func testRunningTwiceRemovesNothingFurther() {
        let parent = insertOccurrence(parentId: nil, slot: october)
        insertOccurrence(parentId: parent, slot: november)
        insertOccurrence(parentId: parent, slot: november)

        RecurringDuplicateCleanup.run(repository: repo, db: db)
        let after = liveIds()

        RecurringDuplicateCleanup.run(repository: repo, db: db)
        XCTAssertEqual(liveIds(), after)
        XCTAssertTrue(RecurringDuplicateCleanup.findDuplicates(db: db).isEmpty)
    }

    func testOnceGateRunsOnlyOnce() {
        let defaults = UserDefaults(suiteName: "dupe-gate-\(UUID().uuidString)")!
        let parent = insertOccurrence(parentId: nil, slot: october)
        insertOccurrence(parentId: parent, slot: november)
        insertOccurrence(parentId: parent, slot: november)

        RecurringDuplicateCleanup.runOnceIfNeeded(repository: repo, db: db, defaults: defaults)
        XCTAssertTrue(RecurringDuplicateCleanup.findDuplicates(db: db).isEmpty)

        // A duplicate appearing later is NOT swept again — the gate is deliberately one-shot.
        insertOccurrence(parentId: parent, slot: november)
        RecurringDuplicateCleanup.runOnceIfNeeded(repository: repo, db: db, defaults: defaults)
        XCTAssertEqual(RecurringDuplicateCleanup.findDuplicates(db: db).count, 1)

        // ...until the gate is cleared.
        RecurringDuplicateCleanup.resetOnceFlag(defaults: defaults)
        RecurringDuplicateCleanup.runOnceIfNeeded(repository: repo, db: db, defaults: defaults)
        XCTAssertTrue(RecurringDuplicateCleanup.findDuplicates(db: db).isEmpty)
    }
}
