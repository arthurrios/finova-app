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

    /// Injectable for two-device tests; production always uses `.shared`.
    init(db: DBHelper = .shared) {
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
        return true
    }
}
