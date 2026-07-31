//
//  TransparencyManager.swift
//  Finova
//
//  Transparent Mode — the replacement for Mirror Mode.
//
//  Mirror Mode published a personal ledger to a group by MOVING it: every personal row was tagged
//  with the group id and re-zoned into the group's CloudKit zone. By the app's own rule
//  (`shared_group_id = NULL` means personal) those rows thereby stopped being personal. Two devices
//  that disagreed about the mirror state then tagged and untagged the same rows on every sync.
//
//  Transparent Mode publishes by COPYING instead. The personal row stays personal, in the personal
//  zone, untouched; the sync engine additionally writes a projection of it into the group zone.
//  Turning transparency on or off creates or removes projections and never alters a personal row's
//  `shared_group_id`, so the whole corruption class is gone by construction.
//
//  State lives on the member's own `GroupMember.permissions` blob, which means it travels on the
//  same pull as the data it describes and can never be observed out of order — unlike Mirror Mode's
//  `NSUbiquitousKeyValueStore` channel, whose reconciliation logic existed purely to paper over
//  being a second, unordered transport.
//

import Foundation

final class TransparencyManager {
    static let shared = TransparencyManager()

    private let repository: BudgetGroupRepository
    private let db: DBHelper

    /// Injectable for two-device tests; production always uses `.shared`.
    init(db: DBHelper = .shared) {
        self.db = db
        self.repository = BudgetGroupRepository(db: db)
    }

    // MARK: - Reading state

    /// Whether `userId` publishes their personal ledger to `groupId`.
    ///
    /// Note this consults the member row directly rather than `BudgetGroupService.currentUserCan`,
    /// which short-circuits to `true` for the group owner. Owners publish only if they chose to.
    func isPublishing(userId: String, toGroup groupId: String) -> Bool {
        repository.fetchMembers(forGroupId: groupId)
            .first { $0.userId == userId }?
            .permissions.publishesPersonalLedger ?? false
    }

    func isPublishing(toGroup groupId: String) -> Bool {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return false }
        return isPublishing(userId: uid, toGroup: groupId)
    }

    /// Every live group the current user publishes into. This is the fan-out set the push path
    /// projects each personal row to.
    func publishedGroupIds() -> [String] {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return [] }
        return repository.fetchAllGroups()
            .filter { isPublishing(userId: uid, toGroup: $0.id) }
            .map(\.id)
    }

    // MARK: - Changing state

    /// Turns publishing on or off for the current user in `groupId`.
    ///
    /// Returns false when there is no member row to record the decision on — a group the user has
    /// not actually joined yet. Deliberately touches no financial row: the only consequence is
    /// which zones the push path fans out to on the next sync.
    @discardableResult
    func setPublishing(_ publishing: Bool, forGroup groupId: String) -> Bool {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return false }
        guard var member = repository.fetchMembers(forGroupId: groupId)
            .first(where: { $0.userId == uid })
        else {
            logWarning("[Transparency] No member row for \(uid) in group \(groupId) — cannot set publishing")
            return false
        }
        guard member.permissions.publishesPersonalLedger != publishing else { return true }

        member.permissions.publishesPersonalLedger = publishing
        repository.updateMember(member)

        // Without this the member record is considered already pushed and the new flag never
        // leaves the device (SyncEngine skips the save when the flag is set).
        UserDefaults.standard.removeObject(forKey: "groupMemberPushed_\(groupId)")

        logWarning("[Transparency] \(publishing ? "ENABLED" : "DISABLED") publishing for group \(groupId)")
        if publishing { queueExistingRecordsForPublication() }
        return true
    }

    /// Queues the personal ledger for publication after transparency is switched on.
    ///
    /// Projections are produced by the PUSH path, per record, from the pending queue — so a ledger
    /// that is already fully synced generates nothing, and enabling transparency appears to do
    /// nothing at all until the user happens to edit something. This marks the personal rows pending
    /// so the next push fans them out.
    ///
    /// It sets `sync_status` ONLY. It deliberately does not touch `updated_at` or `rev`: those say
    /// "the user changed this", and nothing here changes any value. Bumping them would make every row
    /// look freshly edited to every other device and would win conflicts it has no business winning.
    ///
    /// Scoped to `shared_group_id IS NULL` — group records are already in a group zone and are not
    /// projections of anything.
    private func queueExistingRecordsForPublication() {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return }
        let db = self.db
        var queued = 0
        for table in ["Transactions", "Budgets", "CreditCards", "BudgetAllocations"] {
            queued += db.executeSyncUpdateCount(
                """
                UPDATE \(table) SET sync_status = 'pending'
                 WHERE user_id = ? AND shared_group_id IS NULL
                   AND (is_deleted IS NULL OR is_deleted = 0)
                   AND COALESCE(sync_status, '') <> 'pendingDelete';
                """,
                textBindings: [uid]
            )
        }
        TransactionRepository.invalidateCache()
        logWarning("[Transparency] Queued \(queued) existing personal record(s) for publication")
    }
}
