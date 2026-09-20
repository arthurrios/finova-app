//
//  ImportOrphanSweep.swift
//  Finova
//
//  Belt and braces for the one case a local rollback cannot cover by itself.
//
//  `ImportRollbackService` defers an undo while a push is in flight, precisely because a row that is
//  mid-push still reads `ck_record_id IS NULL` and would be hard-deleted locally while its cloud copy
//  survives. That deferral should make this unnecessary. But the cost of being wrong is a transaction
//  the user explicitly undid quietly reappearing in their ledger — money they did not put there — and
//  the cost of the guard is one indexed probe per sync for users who have never imported anything.
//
//  It works because `ImportBatchRows` outlives the transactions it describes. After a hard delete
//  there is no other record that a returning row was ever ours; the membership table is what makes
//  it recognisable.
//

import Foundation

enum ImportOrphanSweep {

    /// Removes any transaction whose uuid belongs to a batch the user rolled back.
    ///
    /// Idempotent, local-only, and a no-op when no batch has ever been rolled back. Intended to run
    /// after a pull has landed — see `PostSyncActions`.
    @discardableResult
    static func runIfNeeded(db: DBHelper = .shared) -> Int {
        let removed = db.sweepRolledBackImportOrphans()
        if removed > 0 {
            NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
        }
        return removed
    }
}
