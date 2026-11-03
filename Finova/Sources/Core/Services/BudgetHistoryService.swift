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
    /// Every expense the bars are built from, early-paid installments removed - read once per screen
    /// load, so moving between months filters in memory instead of reading the table again.
    func expenses(in scope: LedgerScope) -> [Transaction]
    /// The months ahead of the open one. Read with the history, once per screen load.
    func forecast(in scope: LedgerScope, asOf reference: Date) -> BudgetForecast
}

extension BudgetHistoryReading {
    func forecast(in scope: LedgerScope, asOf reference: Date) -> BudgetForecast { .empty }
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
    private let statementRepo: StatementRepository
    /// The ledger the forecast reads. Nil builds one from the repositories above.
    private let ledger: TransactionLedgerService?

    init(
        allocationRepo: BudgetAllocationRepositoryProtocol = BudgetAllocationRepository(),
        transactionRepo: TransactionRepository = TransactionRepository(),
        budgetRepo: BudgetRepository = BudgetRepository(),
        statementRepo: StatementRepository = StatementRepository(),
        ledger: TransactionLedgerService? = nil
    ) {
        self.allocationRepo = allocationRepo
        self.transactionRepo = transactionRepo
        self.budgetRepo = budgetRepo
        self.statementRepo = statementRepo
        self.ledger = ledger
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

    func expenses(in scope: LedgerScope) -> [Transaction] {
        let expenses = transactionRepo.fetchAllTransactions().filter { $0.type == .expense }
        return expenses.isEmpty ? [] : expenses.excludingEarlyPaidInstallments()
    }

    /// The next months through the services the dashboard's budget card reads them from, so a month
    /// shows the same figures in both places. Nothing is summed here that the card does not sum.
    func forecast(in scope: LedgerScope, asOf reference: Date = Date()) -> BudgetForecast {
        let ledger = ledger
            ?? TransactionLedgerService(transactionRepo: transactionRepo, budgetRepo: budgetRepo)
        let allocationService = BudgetAllocationService(
            allocationRepo: allocationRepo, transactionRepo: transactionRepo, budgetRepo: budgetRepo,
            statementRepo: statementRepo)

        let statementsDue = ledger.statementsDueByMonth()
        let commitments = allocationService.balanceCommitments(
            monthsAhead: BudgetForecast.monthsAhead, statementsDue: statementsDue, in: scope,
            asOf: reference)

        let months = ledger.calculateMonthlyData(
            for: 1...BudgetForecast.monthsAhead, referenceDate: reference
        ).map { month -> BudgetForecastMonth in
            let anchor = month.date.monthAnchor
            return BudgetForecastMonth(
                monthAnchor: anchor,
                allocations: allocationService.getAllocationsWithUsage(forMonth: anchor, in: scope),
                summary: allocationService.getUnallocatedSummary(forMonth: anchor, in: scope),
                unallocatedSpending: allocationService.getUnallocatedCategoriesWithSpending(
                    forMonth: anchor, in: scope),
                closingBalance: month.finalBalance,
                deferredCardSpending: commitments[anchor]?.outstandingCard ?? 0,
                statementsDue: statementsDue[anchor] ?? 0,
                reservedPlan: commitments[anchor]?.reservedPlan)
        }
        return BudgetForecast(months: months)
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
