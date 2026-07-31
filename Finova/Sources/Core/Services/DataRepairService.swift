//
//  DataRepairService.swift
//  Finova
//
//  The single place a repair pass may be run from — and it is only ever run because the user asked.
//
//  These passes used to fire automatically: on every launch, on every dashboard load, and inside
//  every sync cycle. Each one rewrites financial rows and marks them `pending`, so two devices
//  would push their own repair results over each other's, forever. The heuristics make that worse
//  rather than better: "the card with the most transactions wins" and "keep the lowest local row
//  id" resolve differently on each device, because local ids and per-device row counts differ. The
//  repairs were not converging on a shared answer; they were each inventing their own and pushing
//  it. That is the largest single source of the divergence this refactor set out to fix.
//
//  Stages 1–3 removed the conditions most of them existed to patch: identity is now stable across
//  devices, so foreign keys no longer dangle, and scope is explicit, so records no longer migrate
//  between ledgers behind the user's back. What remains is a manual tool for data damaged before
//  those landed.
//
//  Two rules for anything added here:
//
//  1. **Never run automatically.** No launch hook, no sync hook, no view-load hook.
//  2. **Only run when hydrated.** A device that has not completed a verified full pull is missing
//     records; "repairing" against a partial view manufactures damage and then uploads it.
//

import Foundation

enum DataRepairService {

    struct Result {
        let ran: Bool
        let summary: String
    }

    /// Runs every repair pass once, in dependency order, and returns what happened.
    ///
    /// Deliberately synchronous and deliberately loud: the user pressed a button and is waiting for
    /// an answer, and a repair that silently does nothing is indistinguishable from one that
    /// silently does harm.
    @discardableResult
    static func repairAll() -> Result {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else {
            return Result(ran: false, summary: "repair.notSignedIn".localized)
        }
        guard UserDefaults.standard.bool(forKey: "syncFullPullVerified_v2") else {
            logWarning("[Repair] Refused — this device has not completed a verified full pull")
            return Result(ran: false, summary: "repair.notHydrated".localized)
        }

        let db = DBHelper.shared
        db.snapshotDatabase(tag: "pre-manual-repair")

        let before = inventory(db: db, uid: uid)
        logWarning("[Repair] Starting manual repair. Before: \(before)")

        let transactionRepo = TransactionRepository()
        let creditCardService = CreditCardService()

        // Order matters: links are rebuilt before duplicates are consolidated, so consolidation
        // sees the corrected picture rather than merging on stale references.
        creditCardService.repairCreditCardLinksFromParents(userId: uid, transactionRepo: transactionRepo)
        creditCardService.deduplicateAndFixCCInstallments(userId: uid, transactionRepo: transactionRepo)
        creditCardService.repairInstallmentStatementLinks(userId: uid, transactionRepo: transactionRepo)
        creditCardService.repairStaleStatementLinks(userId: uid, transactionRepo: transactionRepo)
        creditCardService.repairOrphanedCreditCardTransactions(userId: uid, transactionRepo: transactionRepo)
        creditCardService.consolidateDuplicateStatementsByMonth(userId: uid, transactionRepo: transactionRepo)
        creditCardService.reassignMisplacedTransactions(userId: uid, transactionRepo: transactionRepo)
        creditCardService.recalculateAllStatementTotals()
        creditCardService.repairBudgetMonthForOverriddenTransactions()

        // Consolidate duplicate allocations — one per (scope, month, category), which is the app's
        // own invariant: `insertAllocation` rejects a second one for the same category and month in
        // the same ledger. Inbound sync and lazy generation bypass that check, so duplicates could
        // still form.
        //
        // They did: while allocations were group-tagged, `generateRecurringInstancesIfNeeded` read the
        // now-personal-scoped `fetchAllAllocations()`, could not see them, and re-materialised the
        // months. Un-tagging then left both copies personal. 23 pairs on the reporter's device.
        //
        // It cannot recur — `idx_budgetallocations_uuid` is UNIQUE and generated instances now derive
        // a UUIDv5 from (parent, month), so a second generation collides and is rejected — but the
        // rows already created need clearing.
        let mergedAllocations = deduplicateAllocations(db: db, uid: uid)
        if mergedAllocations > 0 {
            logWarning("[Repair] Consolidated \(mergedAllocations) duplicate allocation(s)")
        }

        // Re-run the mirror-tag restore, bypassing its one-shot flag.
        //
        // Safe to repeat: it only ever un-tags rows THIS user authored, and a row already personal is
        // a no-op. It is here because the one-shot flag lives in UserDefaults while the rows live in
        // the database — so restoring a snapshot brings back tagged rows the flag says were already
        // handled, and without this there would be no way to ask for it again.
        // `includeUnknownAuthorship: true` ONLY here. The automatic pass cannot distinguish the
        // user's own pre-authorship rows from a member's un-attributed one; the user can, and pressing
        // this button is them saying so.
        let restored = MirrorTagRestore.restore(db: db, uid: uid, includeUnknownAuthorship: true)
        if restored > 0 {
            logWarning("[Repair] Re-ran mirror-tag restore — \(restored) row(s) returned to personal")
        }

        // Normalisation, not new truth: rebuild the integer foreign keys from the uuid pointers.
        let relinked = db.resolveUuidForeignKeys()

        TransactionRepository.invalidateCache()

        let after = inventory(db: db, uid: uid)
        logWarning("[Repair] DONE. After: \(after), uuid FKs relinked: \(relinked)")

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
            NotificationCenter.default.post(name: .budgetDataChanged, object: nil)
            NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
        }

        return Result(
            ran: true,
            summary: String(
                format: "repair.summary".localized,
                after.transactions, after.statements, relinked + restored
            )
        )
    }

    /// Consolidates duplicate rows and nothing else.
    ///
    /// Separate from `repairAll` because the nine credit-card repairs it runs REWRITE rows —
    /// reassigning transactions between statements and months — and seven of the eight do not check
    /// `is_statement_overridden`. A user who has corrected a statement assignment by hand can have
    /// that correction silently undone. On the reporter's device 24 transactions carried an override.
    ///
    /// So when the need is "remove the duplicates", this does exactly that: the allocation invariant
    /// (one per scope/month/category) and the uuid-keyed foreign-key rebuild, both of which key on
    /// IDENTITY and cannot disagree with a manual edit.
    @discardableResult
    static func consolidateDuplicates() -> Result {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else {
            return Result(ran: false, summary: "repair.notSignedIn".localized)
        }
        guard UserDefaults.standard.bool(forKey: "syncFullPullVerified_v2") else {
            logWarning("[Repair] Refused — this device has not completed a verified full pull")
            return Result(ran: false, summary: "repair.notHydrated".localized)
        }

        let db = DBHelper.shared
        db.snapshotDatabase(tag: "pre-consolidate")

        let merged = deduplicateAllocations(db: db, uid: uid)
        let relinked = db.resolveUuidForeignKeys()
        TransactionRepository.invalidateCache()
        logWarning("[Repair] Consolidate only: \(merged) duplicate allocation(s), \(relinked) link(s) rebuilt")

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
            NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
        }
        return Result(
            ran: true,
            summary: String(format: "repair.consolidated".localized, merged)
        )
    }

    /// Takes a restore point on demand, without repairing anything.
    ///
    /// The migrations and the repair action already snapshot before they touch data, but nothing
    /// covered "I am about to test a new feature" — which is when the interesting damage happens.
    /// Returns the filename so it can be reported, and nil if the copy failed.
    ///
    /// Note snapshots are marked excluded from iCloud backup: they are local recovery state, so a
    /// lost device loses them. Pull the container if a snapshot needs to survive the device.
    static func createBackup() -> String? {
        guard let url = DBHelper.shared.snapshotDatabase(tag: "manual") else {
            logError("[Repair] Backup failed")
            return nil
        }
        logWarning("[Repair] Backup written: \(url.lastPathComponent)")
        return url.lastPathComponent
    }

    /// Soft-deletes all but one allocation per (scope, month, category) and queues the losers for
    /// deletion in CloudKit, so a duplicate cannot simply return on the next pull.
    ///
    /// The survivor is the highest `(rev, rev_device, id)` — the same convergent tie-break the
    /// `ck_record_id` dedupe uses. `rev` is a logical clock, so two devices cleaning up the same pair
    /// independently keep the SAME row; keeping the lowest local id would have them keep different
    /// ones and push them over each other, which is the defect that made the old repair passes worse
    /// than the damage they addressed.
    private static func deduplicateAllocations(db: DBHelper, uid: String) -> Int {
        db.executeSyncUpdateCount(
            """
            UPDATE BudgetAllocations
               SET is_deleted = 1, sync_status = 'pendingDelete'
             WHERE user_id = ?
               AND (is_deleted IS NULL OR is_deleted = 0)
               AND id NOT IN (
                 SELECT keep FROM (
                   SELECT id AS keep, ROW_NUMBER() OVER (
                            PARTITION BY user_id, COALESCE(shared_group_id, ''), month_date, category_key
                            ORDER BY COALESCE(rev, 0) DESC, COALESCE(rev_device, '') DESC, id DESC
                          ) AS rn
                     FROM BudgetAllocations
                    WHERE user_id = ? AND (is_deleted IS NULL OR is_deleted = 0)
                 ) WHERE rn = 1
               );
            """,
            textBindings: [uid, uid]
        )
    }

    private struct Inventory: CustomStringConvertible {
        let transactions: Int
        let statements: Int
        let orphanTransactions: Int

        var description: String {
            "transactions=\(transactions), statements=\(statements), orphanCCTransactions=\(orphanTransactions)"
        }
    }

    private static func inventory(db: DBHelper, uid: String) -> Inventory {
        Inventory(
            transactions: db.fetchSingleInt(
                "SELECT COUNT(*) FROM Transactions WHERE user_id = ? AND (is_deleted IS NULL OR is_deleted = 0);",
                textBinding: uid) ?? -1,
            statements: db.fetchSingleInt(
                "SELECT COUNT(*) FROM CreditCardStatements WHERE (is_deleted IS NULL OR is_deleted = 0);") ?? -1,
            orphanTransactions: db.fetchSingleInt(
                """
                SELECT COUNT(*) FROM Transactions
                WHERE credit_card_id IS NOT NULL
                  AND credit_card_id NOT IN (SELECT id FROM CreditCards)
                  AND (is_deleted IS NULL OR is_deleted = 0);
                """) ?? -1
        )
    }
}
