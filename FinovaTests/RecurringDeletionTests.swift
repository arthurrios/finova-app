//
//  RecurringDeletionTests.swift
//  FinovaTests
//
//  Deleting a recurring series: every option has to act on the whole batch it names, not just the
//  instance the user happened to open.
//

import Foundation
import XCTest

@testable import Finova

final class RecurringDeletionTests: XCTestCase {
    private var transactionRepo: TransactionRepository!
    private var addViewModel: AddTransactionModalViewModel!
    private var recurringManager: RecurringTransactionManager!

    override func setUp() {
        super.setUp()
        UIDUserDefaultsManager.shared.currentUserUID = "test_recurring_delete_\(UUID().uuidString)"
        transactionRepo = TransactionRepository()
        addViewModel = AddTransactionModalViewModel(transactionRepo: transactionRepo)
        recurringManager = RecurringTransactionManager(transactionRepo: transactionRepo)
        transactionRepo.clearAllTransactionsForTesting()
    }

    override func tearDown() {
        transactionRepo.clearAllTransactionsForTesting()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Helpers

    /// A recurring series with instances materialised from 3 months back to 6 months ahead.
    /// - Returns: (parent, instances sorted by month)
    private func makeRecurringSeries(
        title: String = "Rent",
        amount: Int = 150000
    ) throws -> (parent: Transaction, instances: [Transaction]) {
        let start = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
        let result = addViewModel.addTransaction(
            title: title,
            amount: amount,
            dateString: DateFormatter.fullDateFormatter.string(from: start),
            categoryKey: "utilities",
            typeRaw: "expense",
            isRecurring: true
        )
        guard case .success = result else {
            throw XCTSkip("Could not create the recurring fixture: \(result)")
        }
        TransactionRepository.invalidateCache()

        let parent = try XCTUnwrap(
            transactionRepo.fetchAllTransactions().first { $0.title == title && $0.isRecurring == true },
            "Recurring parent should exist")

        recurringManager.generateInstancesForTransaction(
            parent, in: -3...6, referenceDate: Date(), transactionStartDate: start)
        TransactionRepository.invalidateCache()

        return (parent, instances(titled: title))
    }

    private func instances(titled title: String) -> [Transaction] {
        TransactionRepository.invalidateCache()
        return transactionRepo.fetchAllTransactions()
            .filter { $0.title == title && $0.parentTransactionId != nil }
            .sorted { $0.budgetMonthDate < $1.budgetMonthDate }
    }

    /// Which of `ids` still exist.
    ///
    /// Scoped to the rows the fixture created rather than matched on title: the simulator's database
    /// survives between runs and the cleanup helper only ever sees the current user's rows, so rows
    /// titled "Rent" pile up across runs and a title-based count drifts from one run to the next.
    /// Asking about specific ids is stable no matter what else is in the database.
    private func stillPresent(_ ids: [Int]) -> [Int] {
        TransactionRepository.invalidateCache()
        let live = Set(transactionRepo.fetchAllTransactions().compactMap { $0.id })
        return ids.filter(live.contains)
    }

    // MARK: - Delete this and remaining

    func testDeletingThisAndRemainingRemovesEveryLaterInstance() throws {
        let (_, series) = try makeRecurringSeries(title: "Rent")
        try XCTSkipIf(series.count < 3, "Fixture materialised too few instances: \(series.count)")

        let cutoff = series[series.count / 2]
        let cutoffAnchor = cutoff.budgetMonthDate
        let fromCutoff = series.filter { $0.budgetMonthDate >= cutoffAnchor }.compactMap { $0.id }

        try transactionRepo.deleteTransactionWithOption(
            id: try XCTUnwrap(cutoff.id), option: .futureOnly)

        let survivors = stillPresent(fromCutoff)
        XCTAssertTrue(
            survivors.isEmpty,
            "\"This and remaining\" removed \(fromCutoff.count - survivors.count) of "
                + "\(fromCutoff.count) — ids \(survivors) survived")
    }

    func testDeletingThisAndRemainingKeepsEarlierInstances() throws {
        let (_, series) = try makeRecurringSeries(title: "Gym")
        try XCTSkipIf(series.count < 3, "Fixture materialised too few instances: \(series.count)")

        let cutoff = series[series.count / 2]
        let cutoffAnchor = cutoff.budgetMonthDate
        let earlier = series.filter { $0.budgetMonthDate < cutoffAnchor }.compactMap { $0.id }
        try XCTSkipIf(earlier.isEmpty, "Fixture produced no months before the cutoff")

        try transactionRepo.deleteTransactionWithOption(
            id: try XCTUnwrap(cutoff.id), option: .futureOnly)

        XCTAssertEqual(
            Set(stillPresent(earlier)), Set(earlier),
            "Deleting forward must not touch months before the cutoff")
    }

    /// Regression: the series' parent row is gone.
    ///
    /// Instances are regenerated with new ids, parents get deleted, and sync can land instances whose
    /// parent never arrived. The instance still carries `parentTransactionId`, but nothing else shares
    /// it — so filtering on that id matched only the row the user opened and "this and remaining"
    /// removed exactly one occurrence.
    func testDeletingThisAndRemainingWorksWhenTheParentRowIsMissing() throws {
        let (parent, series) = try makeRecurringSeries(title: "Orphaned")
        try XCTSkipIf(series.count < 3, "Fixture materialised too few instances: \(series.count)")

        // Remove the parent behind the repository's back, leaving the instances stranded — the state
        // the production log showed (group id 161 with no live parent).
        let parentId = try XCTUnwrap(parent.id)
        try DBHelper.shared.deleteTransaction(id: parentId)
        TransactionRepository.invalidateCache()

        let stranded = instances(titled: "Orphaned")
        try XCTSkipIf(stranded.count < 3, "Fixture lost too many rows: \(stranded.count)")

        let cutoff = stranded[stranded.count / 2]
        let cutoffAnchor = cutoff.budgetMonthDate
        let fromCutoff = stranded.filter { $0.budgetMonthDate >= cutoffAnchor }.compactMap { $0.id }
        let earlier = stranded.filter { $0.budgetMonthDate < cutoffAnchor }.compactMap { $0.id }
        try XCTSkipIf(fromCutoff.count < 2, "Need at least two rows at/after the cutoff")

        try transactionRepo.deleteTransactionWithOption(
            id: try XCTUnwrap(cutoff.id), option: .futureOnly)

        let survivors = stillPresent(fromCutoff)
        XCTAssertTrue(
            survivors.isEmpty,
            "With the parent missing, \"this and remaining\" removed "
                + "\(fromCutoff.count - survivors.count) of \(fromCutoff.count) — ids \(survivors) "
                + "survived")
        XCTAssertEqual(
            Set(stillPresent(earlier)), Set(earlier),
            "Months before the cutoff must still be left alone")
    }

    // MARK: - Delete all

    func testDeletingAllOccurrencesLeavesNothingBehind() throws {
        let (parent, series) = try makeRecurringSeries(title: "Netflix")
        try XCTSkipIf(series.isEmpty, "Fixture materialised no instances")

        let everything = (series.compactMap { $0.id } + [parent.id].compactMap { $0 })
        let anyInstanceId = try XCTUnwrap(series.first?.id)

        try transactionRepo.deleteTransactionWithOption(id: anyInstanceId, option: .all)

        let survivors = stillPresent(everything)
        XCTAssertTrue(
            survivors.isEmpty, "\"All occurrences\" left ids \(survivors) behind")
    }

    // MARK: - Plain delete

    func testDeleteAndRelatedRemovesTheWholeRecurringSeries() throws {
        // `deleteTransactionAndRelated` is what the details screen's plain Delete calls, and what the
        // statement and allocation screens call. Its name promises the related rows go too — it used
        // to delete only the row it was handed.
        let (parent, series) = try makeRecurringSeries(title: "Spotify")
        try XCTSkipIf(series.isEmpty, "Fixture materialised no instances")

        let everything = (series.compactMap { $0.id } + [parent.id].compactMap { $0 })
        let anyInstanceId = try XCTUnwrap(series.first?.id)

        try transactionRepo.deleteTransactionAndRelated(id: anyInstanceId)

        let survivors = stillPresent(everything)
        XCTAssertTrue(
            survivors.isEmpty,
            "deleteTransactionAndRelated left \(survivors.count) row(s) of the series behind: "
                + "ids \(survivors)")
    }

    // MARK: - Delete just this one

    func testDeletingOnlyThisOccurrenceLeavesTheRestAlone() throws {
        let (_, series) = try makeRecurringSeries(title: "Water")
        try XCTSkipIf(series.count < 3, "Fixture materialised too few instances: \(series.count)")

        let target = series[series.count / 2]
        let targetId = try XCTUnwrap(target.id)
        let others = series.compactMap { $0.id }.filter { $0 != targetId }

        try transactionRepo.deleteTransactionWithOption(id: targetId, option: .currentSelection)

        XCTAssertTrue(
            stillPresent([targetId]).isEmpty, "The selected occurrence should be gone")
        XCTAssertEqual(
            Set(stillPresent(others)), Set(others),
            "Every other occurrence must be left alone")
    }
}
