//
//  RecurringDuplicateCleanup.swift
//  Finova
//

import Foundation

/// Removes duplicate occurrences left behind by the first version of business-day adjustment.
///
/// That version anchored a series' identity to `budget_month_date`. When a rule moved an occurrence's
/// date into an adjacent month, its own slot appeared empty, so the generator "filled the gap" and
/// created another row for a month that already had one - repeatedly, once per generation pass.
///
/// The invariant is one live occurrence per (series, slot). Anything beyond the first is a row nothing
/// asked for, so this keeps one per slot and removes the rest. It cannot delete a legitimate
/// transaction: only generated recurring children are considered (`parent_transaction_id` set, not the
/// parent itself, no `installment_number`), and a user-created transaction is never one of those.
///
/// Deletion goes through `TransactionRepository.deleteBatch`, not raw SQL, so a row CloudKit knows
/// about is soft-deleted and queued as `pendingDelete`. Deleting it locally would leave the cloud copy
/// intact and the next pull would bring the duplicate straight back.
enum RecurringDuplicateCleanup {

    /// One slot holding more than one live occurrence.
    struct Group {
        let parentId: Int
        let slot: Int
        /// The row being kept.
        let keep: Int
        /// The rows being removed, in the order they were found.
        let remove: [Int]
    }

    // Bumped on each corrective pass so devices that already ran an earlier one get the new one.
    // V1 removed duplicates; V2 added the accounting repair; V3 re-runs both with diagnostics, because
    // V2 reported "nothing found" on real data and the reason was not visible from the outside.
    private static let hasRunKey = "hasCleanedRecurringDuplicatesV3"

    // MARK: - Inspection

    /// What the cleanup *would* remove. Read-only - safe to call at any time, including to report a
    /// count before asking the user to confirm.
    static func findDuplicates(db: DBHelper = .shared) -> [Group] {
        var bySlot: [String: [(id: Int, isSynced: Bool)]] = [:]
        var order: [String] = []

        for row in db.fetchRecurringOccurrenceSlots() {
            let key = "\(row.parentId)|\(row.slot)"
            if bySlot[key] == nil { order.append(key) }
            bySlot[key, default: []].append((row.id, row.isSynced))
        }

        return order.compactMap { key in
            guard let rows = bySlot[key], rows.count > 1 else { return nil }
            let parts = key.split(separator: "|")
            guard parts.count == 2, let parentId = Int(parts[0]), let slot = Int(parts[1])
            else { return nil }

            // Prefer a row CloudKit already knows: it is the one peers have, so keeping it avoids a
            // needless delete-then-recreate round trip. Among equals, the oldest id - it is the row
            // that was there before the bug started duplicating.
            let keep = rows.first(where: { $0.isSynced })?.id ?? rows[0].id
            return Group(
                parentId: parentId,
                slot: slot,
                keep: keep,
                remove: rows.map(\.id).filter { $0 != keep }
            )
        }
    }

    // MARK: - Cleanup

    /// Removes the extras. Returns the groups it acted on.
    @discardableResult
    static func run(
        repository: TransactionRepository = TransactionRepository(),
        db: DBHelper = .shared
    ) -> [Group] {
        // Logged before anything is touched, so the "before" state is always on record even when the
        // repair matches nothing. Remove once the series data is confirmed healthy.
        db.logRecurringOccurrenceDiagnostics()

        // Accounting first: a row sitting in the wrong month is not a duplicate, but leaving it
        // there is the thing that made two occurrences look like one repeated twice.
        let moved = db.repairSeriesAccountingMonths()
        if moved > 0 {
            logWarning(
                "[DuplicateCleanup] Moved \(moved) occurrence(s) back to the month they are "
                    + "scheduled for")
        }

        let groups = findDuplicates(db: db)
        guard !groups.isEmpty else {
            logInfo("[DuplicateCleanup] No duplicate recurring occurrences found")
            return []
        }

        let doomed = groups.flatMap(\.remove)
        logWarning(
            "[DuplicateCleanup] Removing \(doomed.count) duplicate occurrence(s) across "
                + "\(groups.count) slot(s)")
        for group in groups {
            logWarning(
                "[DuplicateCleanup] series \(group.parentId) slot \(group.slot): "
                    + "keeping \(group.keep), removing \(group.remove)")
        }

        do {
            // One batch: a single cache invalidation, one statement recalculation pass and one UI
            // refresh, rather than one of each per row.
            try repository.deleteBatch(ids: doomed)
        } catch {
            logError("[DuplicateCleanup] Failed to remove duplicates: \(error)")
            return []
        }

        return groups
    }

    /// Runs once per install, on launch.
    ///
    /// Kept for the launch path. The standing invariant check is `sweepIfDirty` below.
    static func runOnceIfNeeded(
        repository: TransactionRepository = TransactionRepository(),
        db: DBHelper = .shared,
        defaults: UserDefaults = .standard
    ) {
        guard !defaults.bool(forKey: hasRunKey) else { return }
        // Set first: a crash midway through must not leave this re-running and re-deleting on every
        // subsequent launch. `deleteBatch` is per-row, so a partial run is safe to leave partial -
        // and anything it missed can be swept by calling `run` explicitly.
        defaults.set(true, forKey: hasRunKey)
        run(repository: repository, db: db)
    }

    /// The standing invariant check: one live occurrence per (series, slot), each sitting in the
    /// month it is scheduled for. Returns how many rows it removed.
    ///
    /// This used to be a one-shot migration, on the theory that slot keying made duplicates
    /// impossible to create. That was wrong — the edit path rebuilt an occurrence's date from the
    /// row rather than from its slot, and day 31 in February rolls forward to 3 March rather than
    /// failing, so every edit of a long-anchored series moved February's occurrence onto March's.
    /// The generation rule being correct does not make the invariant self-enforcing, so it is
    /// checked continuously instead of assumed.
    ///
    /// **Detects read-only and writes only when something is actually wrong.** A repair that rewrites
    /// rows on every dashboard load marks them `pending` and makes two devices push their own repair
    /// results over each other's — see the note at the top of `DashboardViewModel.loadMonthlyCards`.
    /// When the ledger is clean this costs one query and touches nothing.
    ///
    /// Callers MUST gate on a verified full pull: `deleteBatch` soft-deletes synced rows and queues
    /// them as `pendingDelete`, so running it on a half-hydrated device deletes from the cloud rows
    /// it simply has not pulled yet.
    @discardableResult
    static func sweepIfDirty(
        repository: TransactionRepository = TransactionRepository(),
        db: DBHelper = .shared
    ) -> Int {
        let groups = findDuplicates(db: db)
        let drifted = db.countSeriesAccountingMonthDrift()

        guard !groups.isEmpty || drifted > 0 else { return 0 }

        logWarning(
            "[DuplicateCleanup] Invariant broken: \(groups.count) slot(s) hold more than one "
                + "occurrence, \(drifted) row(s) sit outside their scheduled month — repairing")

        let moved = db.repairSeriesAccountingMonths()
        if moved > 0 {
            logWarning("[DuplicateCleanup] Moved \(moved) occurrence(s) back to their own month")
        }

        // Re-detect: moving rows back into their slots can reveal, or resolve, collisions.
        let doomed = findDuplicates(db: db).flatMap(\.remove)
        guard !doomed.isEmpty else { return 0 }

        do {
            try repository.deleteBatch(ids: doomed)
            logWarning("[DuplicateCleanup] Removed \(doomed.count) duplicate occurrence(s)")
            return doomed.count
        } catch {
            logError("[DuplicateCleanup] Failed to remove duplicates: \(error)")
            return 0
        }
    }

    /// Clears the once-only gate, so `runOnceIfNeeded` will act again. For tests and for a manual
    /// re-sweep if a duplicate ever turns up from a peer that has not upgraded.
    static func resetOnceFlag(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: hasRunKey)
    }
}
