//
//  SyncChangeTracker.swift
//  Finova
//
//  Created by Arthur Rios on 23/03/26.
//

import Foundation

/// Centralized interceptor that detects local mutations on syncable DB tables
/// and coalesces them into a single debounced notification for SyncEngine.
///
/// Hooked into `DBHelper` mutation methods so every CRUD operation on sync
/// tables automatically triggers a push — no per-repository notification needed.
final class SyncChangeTracker {
    static let shared = SyncChangeTracker()

    private var debounceItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.5

    /// When true, `markDirty()` is a no-op. Set by SyncEngine during standalone
    /// pushes so that `executeSyncUpdate` calls in `markAsSynced` / `hardDeleteByCKRecordName`
    /// don't re-trigger another push cycle.
    var isSuppressed = false

    private init() {}

    /// Called by DBHelper after any write to a syncable table.
    /// Debounces rapid-fire mutations (e.g., 12 installment inserts) into a
    /// single notification so SyncEngine schedules one push, not twelve.
    func markDirty() {
        // Skip during standalone push completion (markAsSynced, hardDelete calls). These are our
        // own sync bookkeeping, never a user edit — checked FIRST so they can't be mistaken for a
        // concurrent local change below and trigger an endless push/drain loop.
        guard !isSuppressed else { return }

        // A write that lands mid-cycle must NOT be dropped. Posting the notification here would be
        // wrong (handleLocalDataChange would schedule a push concurrent with the in-flight cycle),
        // so instead flag the engine to drain a follow-up push when the cycle finishes.
        //
        // This previously returned outright. The comment claimed handleLocalDataChange deferred via
        // needsPostSyncPush — but that handler only runs in response to the notification this line
        // suppressed, so the flag was never set and drainPostSyncPush no-op'd. Every write made
        // during a sync was stranded as 'pending' until some unrelated later trigger: lazily
        // generated recurring/installment instances, mirror-mode re-tags, and the post-sync credit
        // card repairs (which run AFTER the push and mark many rows pending).
        if SyncEngine.shared.isSyncInProgress {
            SyncEngine.shared.noteLocalChangeDuringSync()
            return
        }

        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.debounceItem = nil
            NotificationCenter.default.post(name: .localSyncableDataDidChange, object: nil)
        }
        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }
}
