//
//  BudgetHistoryService.swift
//  Finova
//
//  Created by Arthur Rios on 17/10/26.
//

import Foundation

/// What the budget history screen reads its months through. A seam so the screen's navigation can be
/// tested against a fixed history instead of the database.
protocol BudgetHistoryReading: AnyObject {
    func history(in scope: LedgerScope, includeWholeMonth: Bool, asOf reference: Date) -> BudgetHistory
}

/// Reads a ledger's past months for the budget history screen.
///
/// Every figure comes from the same source the dashboard already shows for that month, so a bar here
/// never disagrees with the card the user just came from:
/// - the whole-month bar is the month card's budget and "used" figure, read from
///   `TransactionLedgerService` itself rather than recomputed;
/// - a category bar is the allocation card's `allocatedAmount` and `usedAmount` - the row filter below
///   mirrors `BudgetAllocationService.calculateUsageByCategory`. Change one and change both.
///
/// Read once on screen open, never on a render path.
final class BudgetHistoryService: BudgetHistoryReading {

    private let allocationRepo: BudgetAllocationRepositoryProtocol
    private let transactionRepo: TransactionRepository
    private let budgetRepo: BudgetRepository

    init(
        allocationRepo: BudgetAllocationRepositoryProtocol = BudgetAllocationRepository(),
        transactionRepo: TransactionRepository = TransactionRepository(),
        budgetRepo: BudgetRepository = BudgetRepository()
    ) {
        self.allocationRepo = allocationRepo
        self.transactionRepo = transactionRepo
        self.budgetRepo = budgetRepo
    }

    /// - Parameters:
    ///   - includeWholeMonth: false skips the month totals, which run the full balance pass. The
    ///     allocation details preview shows one category and has no use for them.
    ///   - reference: seam for tests, so the window is deterministic.
    func history(
        in scope: LedgerScope, includeWholeMonth: Bool = true, asOf reference: Date = Date()
    ) -> BudgetHistory {
        let current = reference.monthAnchor
        let scopedAllocations = allocationRepo.fetchAllAllocations()
        let budgets = budgetRepo.fetchBudgets()

        // Back to the first month that had a plan, so savings "since the start" are complete.
        // Future months are ignored: recurring allocations are materialised years ahead.
        let firstPlanned = (scopedAllocations.filter { $0.allocatedAmount > 0 }.map(\.monthDate)
            + budgets.filter { $0.amount > 0 }.map(\.monthDate))
            .filter { $0 <= current }
            .min()
        let count = min(
            max(BudgetHistory.minimumWindowMonths, firstPlanned.map { Self.months(from: $0, to: current) + 1 } ?? 0),
            BudgetHistory.maximumWindowMonths)
        let anchors = (0..<count).reversed().map { reference.monthAnchor(offsetByMonths: -$0) }
        let window = Set(anchors)

        let allocations = scopedAllocations.filter { window.contains($0.monthDate) }

        let transactions = transactionRepo.fetchAllTransactions()
        let expenses = transactions.filter {
            $0.type == .expense && window.contains($0.budgetMonthDate)
        }

        var spentByCategory: [String: [Int: Int]] = [:]
        // The membership test costs a query, so it runs after the cheap predicate.
        for transaction in expenses.isEmpty ? [] : expenses.excludingEarlyPaidInstallments() {
            spentByCategory[transaction.category.key, default: [:]][
                transaction.budgetMonthDate, default: 0] += transaction.amount
        }

        return BudgetHistory(
            monthAnchors: anchors,
            currentAnchor: current,
            allocations: allocations,
            spentByCategory: spentByCategory,
            monthTotals: includeWholeMonth
                ? monthTotals(in: scope, count: count, reference: reference) : [:])
    }

    /// Whole months from one anchor to another, in the calendar every anchor is written with.
    private static func months(from start: Int, to end: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar.dateComponents(
            [.month], from: Date.fromMonthAnchor(start), to: Date.fromMonthAnchor(end)
        ).month ?? 0
    }

    /// The month card's own numbers, from the service that renders it.
    private func monthTotals(
        in scope: LedgerScope, count: Int, reference: Date
    ) -> [Int: BudgetHistory.MonthTotal] {
        let ledger = TransactionLedgerService(transactionRepo: transactionRepo, budgetRepo: budgetRepo)
        let range = -(count - 1)...0
        let months = ledger.calculateMonthlyData(for: range, referenceDate: reference)

        return months.reduce(into: [:]) { totals, month in
            totals[month.date.monthAnchor] = BudgetHistory.MonthTotal(
                budget: month.budgetLimit, used: month.usedValue)
        }
    }
}
