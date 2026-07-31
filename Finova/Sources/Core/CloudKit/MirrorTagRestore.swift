//
//  MirrorTagRestore.swift
//  Finova
//
//  ONE-SHOT DATA REPAIR — safe to delete this file once every device has run it.
//
//  Mirror Mode published a personal ledger to a group by MOVING it: it stamped `shared_group_id`
//  on every personal Transaction, Budget, CreditCard and BudgetAllocation the user owned. By the
//  app's own rule — `shared_group_id = NULL` means personal — those rows thereby stopped being
//  personal, which is why the personal view and the group view disagreed and why two devices with
//  different mirror state re-tagged each other's rows on every sync.
//
//  Transparent Mode replaces the move with a copy, so nothing needs to be tagged any more. This
//  restores the rows Mirror Mode tagged, and only those.
//
//  Two invariants make it safe to run against real financial data:
//
//  1. **Keyed on `created_by_uid`, never `user_id`.** `executeCloudInsert` stamps the RECEIVER's
//     uid as `user_id` on every inbound record, so another member's transaction has your uid on
//     your device. Un-tagging by `user_id` would strip the group tag off their records — erasing
//     their contribution from the group for everyone.
//  2. **`created_by_uid IS NULL` means unknown, so leave it tagged.** Authorship was only recorded
//     from a certain build onwards. Leaving a row tagged is a cosmetic error the user can fix;
//     un-tagging someone else's row destroys data. The asymmetry decides it.
//
//  Nothing is deleted. Rows are marked pending, so the next sync moves each one back to the
//  personal zone and `staleZoneCopy` withdraws its group-zone copy — and if the user has turned on
//  Transparent Mode for that group, `fanOutProjections` republishes it in the same push, in which
//  case the withdrawal is suppressed and the group keeps seeing it. Either way the personal ledger
//  is whole again.
//

import Foundation

enum MirrorTagRestore {

    private static let hasRunKey = "hasRestoredMirrorTaggedRows_v1"

    private static let tables = ["Transactions", "Budgets", "CreditCards", "BudgetAllocations"]

    /// Runs at most once per install, and only on a device that has completed a verified full pull.
    ///
    /// The hydration gate is not optional. Before the first full pull this device has not yet seen
    /// other members' records, so `created_by_uid` is missing for rows that do have an author —
    /// they would be read as "unknown" and left tagged, and the one-shot flag would then prevent
    /// the migration from ever correcting them.
    static func runOnceIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: hasRunKey) else { return }
        guard UserDefaults.standard.bool(forKey: "syncFullPullVerified_v2") else {
            logWarning("[MirrorRestore] Deferred — full pull not yet verified on this device")
            return
        }
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return }

        let db = DBHelper.shared
        let before = counts(db: db, uid: uid)
        logWarning("""
            [MirrorRestore] Starting. Group-tagged rows authored by this user:
              \(before.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))
            """)

        guard before.values.reduce(0, +) > 0 else {
            UserDefaults.standard.set(true, forKey: hasRunKey)
            logWarning("[MirrorRestore] Nothing to restore — marking done")
            return
        }

        // A restore point taken before the only destructive-looking step in the whole refactor.
        db.snapshotDatabase(tag: "pre-mirror-restore")

        let restored = restore(db: db, uid: uid)

        let after = counts(db: db, uid: uid)
        let stillTagged = after.values.reduce(0, +)
        logWarning("""
            [MirrorRestore] DONE — \(restored) row(s) restored to personal.
              Remaining group-tagged rows authored by this user: \(stillTagged) \
            (expected 0; anything here means the UPDATE did not match)
              Rows with an unknown author are intentionally left tagged.
            """)

        UserDefaults.standard.set(true, forKey: hasRunKey)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
            NotificationCenter.default.post(name: .budgetDataChanged, object: nil)
            NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
        }
        SyncEngine.shared.performFullSync()
    }

    /// The migration itself, with no flags, no snapshot and no sync — separated so it can be tested
    /// directly against a temporary database. Returns the number of rows restored.
    ///
    /// `created_by_uid = ?` is the entire safety story. See the note at the top of this file for
    /// why `user_id` would be catastrophic here, and why NULL means "leave it alone".
    @discardableResult
    static func restore(db: DBHelper, uid: String) -> Int {
        var restored = 0
        for table in tables {
            let sql = """
                UPDATE \(table)
                SET shared_group_id = NULL, sync_status = 'pending'
                WHERE created_by_uid = ?
                  AND shared_group_id IS NOT NULL AND shared_group_id != '';
                """
            let changed = db.executeSyncUpdateCount(sql, textBindings: [uid])
            restored += changed
            logWarning("[MirrorRestore] \(table): restored \(changed) row(s) to personal")
        }
        TransactionRepository.invalidateCache()
        return restored
    }

    /// Group-tagged rows this user authored, per table — the exact set the UPDATE targets.
    private static func counts(db: DBHelper, uid: String) -> [String: Int] {
        var result: [String: Int] = [:]
        for table in tables {
            result[table] = db.fetchSingleInt(
                """
                SELECT COUNT(*) FROM \(table)
                WHERE created_by_uid = ?
                  AND shared_group_id IS NOT NULL AND shared_group_id != '';
                """,
                textBinding: uid
            ) ?? 0
        }
        return result
    }
}
