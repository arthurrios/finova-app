//
//  MirrorModeManager.swift
//  Finova
//
//  Created by Arthur Rios on 13/02/26.
//

import Foundation

final class MirrorModeManager {
    static let shared = MirrorModeManager()
    private init() {}

    private let db = DBHelper.shared

    // MARK: - State

    var isEnabled: Bool {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return false }
        return UserDefaults.standard.bool(forKey: "mirrorMode_enabled_\(uid)")
    }

    var linkedGroupId: String? {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return nil }
        return UserDefaults.standard.string(forKey: "mirrorMode_groupId_\(uid)")
    }

    // MARK: - Enable / Disable

    func enableMirrorMode(groupId: String) {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return }
        UserDefaults.standard.set(true, forKey: "mirrorMode_enabled_\(uid)")
        UserDefaults.standard.set(groupId, forKey: "mirrorMode_groupId_\(uid)")
        performInitialMirrorSync(groupId: groupId)
    }

    func disableMirrorMode() {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return }
        let groupId = linkedGroupId
        UserDefaults.standard.set(false, forKey: "mirrorMode_enabled_\(uid)")
        UserDefaults.standard.removeObject(forKey: "mirrorMode_groupId_\(uid)")
        if let groupId = groupId {
            removeGroupIdFromPersonalData(groupId: groupId)
        }
    }

    // MARK: - Initial Mirror Sync

    private func performInitialMirrorSync(groupId: String) {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return }

        // 1. Transactions: tag all personal transactions with shared_group_id
        db.executeSyncUpdate(
            "UPDATE Transactions SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND (shared_group_id IS NULL);",
            textBindings: [groupId, uid]
        )

        // 2. Budgets: tag all personal budgets
        db.executeSyncUpdate(
            "UPDATE Budgets SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND (shared_group_id IS NULL);",
            textBindings: [groupId, uid]
        )

        // 3. Credit Cards: tag all personal credit cards
        db.executeSyncUpdate(
            "UPDATE CreditCards SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND (shared_group_id IS NULL) AND is_deleted = 0;",
            textBindings: [groupId, uid]
        )

        // 4. Allocations: use existing migration method
        let allocationRepo = BudgetAllocationRepository()
        _ = allocationRepo.migrateAllocationsToGroup(groupId: groupId)

        // 5. Balance offset: copy personal to group
        let personalOffset = UIDUserDefaultsManager.shared.getCurrentUserBalanceOffset()
        UIDUserDefaultsManager.shared.setGroupBalanceOffset(personalOffset, groupId: groupId)

        // 6. Post notifications
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
            NotificationCenter.default.post(name: .budgetDataChanged, object: nil)
            NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
        }

        // 7. Trigger CloudKit sync
        SyncEngine.shared.performFullSync()

        logInfo("MirrorModeManager: Initial mirror sync completed for group \(groupId)")
    }

    // MARK: - Continuous Reconciliation

    /// Ensures all personal data is tagged with the linked group ID.
    /// Call this after sync pull, lazy generation, or any data mutation to keep mirror mode consistent.
    func reconcileMirrorData() {
        guard isEnabled,
              let groupId = linkedGroupId,
              let uid = UIDUserDefaultsManager.shared.currentUserUID
        else { return }

        // Tag any un-tagged transactions belonging to this user
        db.executeSyncUpdate(
            "UPDATE Transactions SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND (shared_group_id IS NULL) AND (is_deleted IS NULL OR is_deleted = 0);",
            textBindings: [groupId, uid]
        )

        // Tag any un-tagged budgets
        db.executeSyncUpdate(
            "UPDATE Budgets SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND (shared_group_id IS NULL);",
            textBindings: [groupId, uid]
        )

        // Tag any un-tagged credit cards
        db.executeSyncUpdate(
            "UPDATE CreditCards SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND (shared_group_id IS NULL) AND is_deleted = 0;",
            textBindings: [groupId, uid]
        )

        // Tag any un-tagged allocations
        db.executeSyncUpdate(
            "UPDATE BudgetAllocations SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND (shared_group_id IS NULL);",
            textBindings: [groupId, uid]
        )

        TransactionRepository.invalidateCache()
        logInfo("MirrorReconcile: reconciliation completed for group \(groupId)")
    }

    // MARK: - Remove Mirror

    private func removeGroupIdFromPersonalData(groupId: String) {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return }

        db.executeSyncUpdate(
            "UPDATE Transactions SET shared_group_id = NULL, sync_status = 'pending' WHERE user_id = ? AND shared_group_id = ?;",
            textBindings: [uid, groupId]
        )

        db.executeSyncUpdate(
            "UPDATE Budgets SET shared_group_id = NULL, sync_status = 'pending' WHERE user_id = ? AND shared_group_id = ?;",
            textBindings: [uid, groupId]
        )

        db.executeSyncUpdate(
            "UPDATE CreditCards SET shared_group_id = NULL, sync_status = 'pending' WHERE user_id = ? AND shared_group_id = ? AND is_deleted = 0;",
            textBindings: [uid, groupId]
        )

        db.executeSyncUpdate(
            "UPDATE BudgetAllocations SET shared_group_id = NULL, sync_status = 'pending' WHERE user_id = ? AND shared_group_id = ?;",
            textBindings: [uid, groupId]
        )

        TransactionRepository.invalidateCache()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
            NotificationCenter.default.post(name: .budgetDataChanged, object: nil)
            NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
        }

        SyncEngine.shared.performFullSync()

        logInfo("MirrorModeManager: Removed mirror for group \(groupId)")
    }
}
