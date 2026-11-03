//
//  BalanceCommitmentsCache.swift
//  Finova
//

import Foundation

/// `BalanceCommitments` for the dashboard, worked out once per load.
///
/// The carousel configures a cell per month, each with its own `BudgetAllocationService`, and every
/// month needs the plans of the months before it. Reading them per cell would scan the ledger once per
/// month per month, and generate the statement synthetics each time.
///
/// Shared, so it locks: `.allocationDataChanged` is posted from background threads by `SyncEngine`,
/// `MirrorTagRestore` and `DataRepairService`, and `.transactionDataChanged` on the writing thread.
/// Keyed by scope, which carries the signed-in user, and by month, so a sign-out or a new month cannot
/// be served the old table.
final class BalanceCommitmentsCache {

    static let shared = BalanceCommitmentsCache()

    private let lock = NSLock()
    private var cached: (scope: LedgerScope, month: Int, commitments: BalanceCommitments)?
    /// Bumped by every invalidation, so a table read before a change is never stored after it.
    private var generation = 0
    private let load: (LedgerScope, Date) -> BalanceCommitments

    init(
        load: @escaping (LedgerScope, Date) -> BalanceCommitments = { scope, reference in
            BudgetAllocationService().balanceCommitments(
                monthsAhead: SeriesMonths.carouselRange.upperBound,
                statementsDue: TransactionLedgerService().statementsDueByMonth(),
                in: scope, asOf: reference)
        }
    ) {
        self.load = load
        for name in [Notification.Name.transactionDataChanged, .allocationDataChanged, .creditCardDataChanged] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(dataChanged), name: name, object: nil)
        }
    }

    @objc private func dataChanged() { invalidate() }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
        generation += 1
    }

    func commitments(in scope: LedgerScope, asOf reference: Date = Date()) -> BalanceCommitments {
        let month = reference.monthAnchor

        lock.lock()
        if let cached, cached.scope == scope, cached.month == month {
            defer { lock.unlock() }
            return cached.commitments
        }
        let startedAt = generation
        lock.unlock()

        let commitments = load(scope, reference)

        lock.lock()
        defer { lock.unlock() }
        if generation == startedAt {
            cached = (scope, month, commitments)
        }
        return commitments
    }
}
