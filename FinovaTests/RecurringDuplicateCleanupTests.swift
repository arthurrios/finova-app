//
//  RecurringDuplicateCleanupTests.swift
//  FinovaTests
//

import XCTest

@testable import Finova

/// The cleanup deletes rows, so these tests are mostly about what it must NOT touch.
final class RecurringDuplicateCleanupTests: XCTestCase {
    private var transactionRepo: TransactionRepository!
    private var db: DBHelper!

    private let jan = 1_767_225_600  // 2026-01-01
    private let feb = 1_769_904_000  // 2026-02-01

    override func setUp() {
        super.setUp()
        SecureLocalDataManager.shared.authenticateUser(
            firebaseUID: "test_dup_cleanup_\(UUID().uuidString)")
        transactionRepo = TransactionRepository()
        db = DBHelper.shared
        transactionRepo.clearAllTransactionsForTesting()
    }

    override func tearDown() {
        transactionRepo.clearAllTransactionsForTesting()
        SecureLocalDataManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func insert(
        _ title: String,
        parentId: Int? = nil,
        slot: Int? = nil,
        budgetMonth: Int? = nil,
        installmentNumber: Int? = nil
    ) -> Int {
        let month = budgetMonth ?? slot ?? jan
        let model = TransactionModel(
            title: title,
            category: "other",
            amount: 1000,
            type: "expense",
            dateTimestamp: month,
            budgetMonthDate: month,
            parentTransactionId: parentId,
            installmentNumber: installmentNumber,
            seriesPeriod: slot
        )
        return (try? transactionRepo.insertTransactionAndGetId(model)) ?? -1
    }

    private func liveIds(titled title: String) -> [Int] {
        transactionRepo.fetchAllTransactions()
            .filter { $0.title == title }
            .compactMap { $0.id }
            .sorted()
    }

    /// Groups for one parent only. These tests share the app database with every other suite, so a
    /// global group count says nothing about this fixture.
    private func groups(
        _ all: [RecurringDuplicateCleanup.Group], for parentId: Int
    ) -> [RecurringDuplicateCleanup.Group] {
        all.filter { $0.parentId == parentId }
    }

    // MARK: - Removes what it should

    func testTwoOccurrencesInOneSlotLoseTheNewerOne() {
        let parent = insert("Series", slot: nil)
        let first = insert("Occ", parentId: parent, slot: feb)
        let second = insert("Occ", parentId: parent, slot: feb)
        XCTAssertNotEqual(first, second, "fixture should have produced two distinct rows")

        let mine = groups(
            RecurringDuplicateCleanup.run(repository: transactionRepo, db: db), for: parent)

        XCTAssertEqual(mine.count, 1)
        XCTAssertEqual(mine.first?.keep, first, "the oldest id is the row that predates the race")
        XCTAssertEqual(mine.first?.remove, [second])
        XCTAssertEqual(liveIds(titled: "Occ"), [first])
    }

    func testASlotWithOneOccurrenceIsUntouched() {
        let parent = insert("Series")
        let only = insert("Occ", parentId: parent, slot: feb)

        XCTAssertTrue(RecurringDuplicateCleanup.findDuplicates(db: db).isEmpty)
        RecurringDuplicateCleanup.run(repository: transactionRepo, db: db)

        XCTAssertEqual(liveIds(titled: "Occ"), [only])
    }

    func testOccurrencesInDifferentSlotsAreNotDuplicates() {
        let parent = insert("Series")
        let a = insert("Occ", parentId: parent, slot: jan)
        let b = insert("Occ", parentId: parent, slot: feb)

        RecurringDuplicateCleanup.run(repository: transactionRepo, db: db)

        XCTAssertEqual(liveIds(titled: "Occ"), [a, b].sorted())
    }

    // MARK: - Never removes what it must not

    func testTwoIdenticalUserCreatedTransactionsBothSurvive() {
        // No parent id, so neither is a generated occurrence — a user really did enter this twice.
        let a = insert("Coffee")
        let b = insert("Coffee")

        RecurringDuplicateCleanup.run(repository: transactionRepo, db: db)

        XCTAssertEqual(liveIds(titled: "Coffee"), [a, b].sorted())
    }

    func testTwoInstallmentsInTheSameMonthBothSurvive() {
        // Early payment legitimately puts more than one installment in a single month, and
        // installments are identified by number rather than slot.
        let parent = insert("Laptop")
        let one = insert("Laptop inst", parentId: parent, slot: feb, installmentNumber: 1)
        let two = insert("Laptop inst", parentId: parent, slot: feb, installmentNumber: 2)

        XCTAssertTrue(RecurringDuplicateCleanup.findDuplicates(db: db).isEmpty)
        RecurringDuplicateCleanup.run(repository: transactionRepo, db: db)

        XCTAssertEqual(liveIds(titled: "Laptop inst"), [one, two].sorted())
    }

    func testSameSlotUnderDifferentParentsIsNotADuplicate() {
        let parentA = insert("A")
        let parentB = insert("B")
        let a = insert("Occ", parentId: parentA, slot: feb)
        let b = insert("Occ", parentId: parentB, slot: feb)

        RecurringDuplicateCleanup.run(repository: transactionRepo, db: db)

        XCTAssertEqual(liveIds(titled: "Occ"), [a, b].sorted())
    }

    // MARK: - Legacy rows

    func testRowsWithoutSeriesPeriodFallBackToTheirAccountingMonth() {
        // Rows written before the business-day migration have no series_period; for those the
        // accounting month IS the slot, so two of them in one month are still duplicates.
        let parent = insert("Series")
        let first = insert("Legacy", parentId: parent, slot: nil, budgetMonth: feb)
        let second = insert("Legacy", parentId: parent, slot: nil, budgetMonth: feb)

        let mine = groups(
            RecurringDuplicateCleanup.run(repository: transactionRepo, db: db), for: parent)

        XCTAssertEqual(mine.count, 1)
        XCTAssertEqual(liveIds(titled: "Legacy"), [min(first, second)])
    }

    // MARK: - Idempotence

    func testASecondPassFindsNothing() {
        let parent = insert("Series")
        insert("Occ", parentId: parent, slot: feb)
        insert("Occ", parentId: parent, slot: feb)

        let first = RecurringDuplicateCleanup.run(repository: transactionRepo, db: db)
        XCTAssertEqual(groups(first, for: parent).count, 1)

        let second = RecurringDuplicateCleanup.run(repository: transactionRepo, db: db)
        XCTAssertTrue(groups(second, for: parent).isEmpty)
    }

    func testTheGateIsSetEvenWhenThereIsNothingToDo() {
        let defaults = UserDefaults(suiteName: "dup_cleanup_gate_\(UUID().uuidString)")!

        RecurringDuplicateCleanup.runOnceIfNeeded(
            repository: transactionRepo, db: db, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: "hasCleanedRecurringDuplicatesV1"))

        // And a second call is a no-op rather than a second scan.
        let parent = insert("Series")
        insert("Occ", parentId: parent, slot: feb)
        insert("Occ", parentId: parent, slot: feb)
        RecurringDuplicateCleanup.runOnceIfNeeded(
            repository: transactionRepo, db: db, defaults: defaults)
        XCTAssertEqual(liveIds(titled: "Occ").count, 2, "gated out, so the duplicate remains")
    }
}
