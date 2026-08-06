//
//  RecurringDuplicateCleanup.swift
//  Finova
//

import Foundation

/// Removes duplicate recurring occurrences left behind by concurrent generation.
///
/// `RecurringTransactionManager`'s operation queue and in-flight set used to be per-instance, but
/// managers are created per view model — the Dashboard owns one, the AddTransaction modal another.
/// Two of them could generate at the same time, each reading its own snapshot of a series, each
/// computing the same month as missing, and each inserting it. The result was exact duplicates:
/// same date, same accounting month, same slot.
///
/// The guards are static now, so nothing new is produced. This clears what the old code already
/// wrote, on devices that ran it.
///
/// The invariant is one live occurrence per (series, slot). Anything beyond the first is a row
/// nothing asked for, so this keeps one per slot and removes the rest. It cannot delete a legitimate
/// transaction: only generated recurring children are considered — see
/// `DBHelper.fetchRecurringOccurrenceSlots` for exactly which rows those are — and two identical
/// user-created transactions are never among them.
enum RecurringDuplicateCleanup {

    /// One slot holding more than one occurrence.
    struct Group {
        let parentId: Int
        let slot: Int
        /// The row being kept.
        let keep: Int
        /// The rows being removed, in id order.
        let remove: [Int]
    }

    private static let hasRunKey = "hasCleanedRecurringDuplicatesV1"

    // MARK: - Inspection

    /// What the cleanup *would* remove. Read-only — safe to call at any time.
    static func findDuplicates(db: DBHelper = .shared) -> [Group] {
        var bySlot: [String: [Int]] = [:]
        var order: [String] = []

        for row in db.fetchRecurringOccurrenceSlots() {
            let key = "\(row.parentId)|\(row.slot)"
            if bySlot[key] == nil { order.append(key) }
            bySlot[key, default: []].append(row.id)
        }

        return order.compactMap { key in
            guard let ids = bySlot[key], ids.count > 1 else { return nil }
            let parts = key.split(separator: "|")
            guard parts.count == 2, let parentId = Int(parts[0]), let slot = Int(parts[1])
            else { return nil }

            // The oldest id — the row that was there before the race started duplicating it.
            // The query already returns ids ascending.
            let keep = ids[0]
            return Group(parentId: parentId, slot: slot, keep: keep, remove: Array(ids.dropFirst()))
        }
    }

    // MARK: - Cleanup

    /// Removes the extras. Returns the groups it acted on.
    @discardableResult
    static func run(
        repository: TransactionRepository = TransactionRepository(),
        db: DBHelper = .shared
    ) -> [Group] {
        let groups = findDuplicates(db: db)
        guard !groups.isEmpty else { return [] }

        let doomed = groups.flatMap { $0.remove }
        // Logged before anything is touched, so the "before" state is on record even if the delete
        // throws half way.
        logWarning(
            "[RecurringDuplicateCleanup] \(groups.count) duplicated slot(s), removing \(doomed.count) row(s): \(doomed)"
        )

        do {
            try repository.deleteBatch(ids: doomed)
        } catch {
            logError("[RecurringDuplicateCleanup] Failed to remove duplicates: \(error)")
            return []
        }

        return groups
    }

    /// Runs once per install. Idempotent regardless — `findDuplicates` returns nothing on a clean
    /// database — but gated so a launch does not pay for the scan forever.
    ///
    /// The gate is set BEFORE the work, so a crash part way through cannot leave this re-deleting on
    /// every launch. A pass that dies early just leaves some duplicates behind; the invariant is
    /// "never delete more than intended", not "always finish".
    static func runOnceIfNeeded(
        repository: TransactionRepository = TransactionRepository(),
        db: DBHelper = .shared,
        defaults: UserDefaults = .standard
    ) {
        guard !defaults.bool(forKey: hasRunKey) else { return }
        defaults.set(true, forKey: hasRunKey)
        run(repository: repository, db: db)
    }
}
