//
//  BudgetHistoryService.swift
//  Finova
//
//  Created by Arthur Rios on 17/10/26.
//

import Foundation

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
final class BudgetHistoryService {

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
        let count = BudgetHistory.windowMonths
        let anchors = (0..<count).reversed().map { reference.monthAnchor(offsetByMonths: -$0) }
        let current = reference.monthAnchor
        let window = Set(anchors)

        let allocations = (scope.groupId.map { allocationRepo.fetchAllocationsForGroup(groupId: $0) }
            ?? allocationRepo.fetchAllAllocations())
            .filter { window.contains($0.monthDate) }

        let transactions = scope.groupId.map { transactionRepo.fetchTransactionsForGroup(groupId: $0) }
            ?? transactionRepo.fetchAllTransactions()
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

    /// The month card's own numbers, from the service that renders it.
    private func monthTotals(
        in scope: LedgerScope, count: Int, reference: Date
    ) -> [Int: BudgetHistory.MonthTotal] {
        let ledger = TransactionLedgerService(transactionRepo: transactionRepo, budgetRepo: budgetRepo)
        let range = -(count - 1)...0
        let months = scope.groupId.map {
            ledger.calculateMonthlyDataForGroup(groupId: $0, for: range, referenceDate: reference)
        } ?? ledger.calculateMonthlyData(for: range, referenceDate: reference)

        return months.reduce(into: [:]) { totals, month in
            totals[month.date.monthAnchor] = BudgetHistory.MonthTotal(
                budget: month.budgetLimit, used: month.usedValue)
        }
    }
}
