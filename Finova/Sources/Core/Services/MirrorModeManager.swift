//
//  MirrorModeManager.swift
//  Finova
//
//  Created by Arthur Rios on 13/02/26.
//

import Foundation

final class MirrorModeManager {
    static let shared = MirrorModeManager()

    private let db = DBHelper.shared
    private let cloud = NSUbiquitousKeyValueStore.default

    private init() {
        observeCloudChanges()
        cloud.synchronize()
    }

    // MARK: - State

    var isEnabled: Bool {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return false }
        return UserDefaults.standard.bool(forKey: "mirrorMode_enabled_\(uid)")
    }

    var linkedGroupId: String? {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return nil }
        return UserDefaults.standard.string(forKey: "mirrorMode_groupId_\(uid)")
    }

    /// Returns true only if the current user is the owner of the given group.
    /// Mirror mode is exclusively an owner feature — members must never mirror personal data into the group.
    private func isOwnerOfGroup(_ groupId: String) -> Bool {
        guard let group = BudgetGroupRepository().fetchGroup(byId: groupId) else { return false }
        return group.isOwner
    }

    // MARK: - Enable / Disable

    func enableMirrorMode(groupId: String) {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return }
        guard isOwnerOfGroup(groupId) else {
            logWarning("[MirrorMode] enableMirrorMode BLOCKED — current user is not owner of group \(groupId)")
            return
        }
        UserDefaults.standard.set(true, forKey: "mirrorMode_enabled_\(uid)")
        UserDefaults.standard.set(groupId, forKey: "mirrorMode_groupId_\(uid)")
        syncStateToCloud(enabled: true, groupId: groupId, uid: uid)
        performInitialMirrorSync(groupId: groupId)
    }

    func disableMirrorMode() {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return }
        let groupId = linkedGroupId
        UserDefaults.standard.set(false, forKey: "mirrorMode_enabled_\(uid)")
        UserDefaults.standard.removeObject(forKey: "mirrorMode_groupId_\(uid)")
        syncStateToCloud(enabled: false, groupId: nil, uid: uid)
        if let groupId = groupId {
            removeGroupIdFromPersonalData(groupId: groupId)
        }
    }

    // MARK: - iCloud Key-Value Sync

    private func syncStateToCloud(enabled: Bool, groupId: String?, uid: String) {
        cloud.set(enabled, forKey: "mirrorMode_enabled_\(uid)")
        if let groupId = groupId {
            cloud.set(groupId, forKey: "mirrorMode_groupId_\(uid)")
        } else {
            cloud.removeObject(forKey: "mirrorMode_groupId_\(uid)")
        }
        cloud.synchronize()
    }

    private func observeCloudChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudStoreDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud
        )
    }

    @objc private func cloudStoreDidChange(_ notification: Notification) {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return }

        let cloudEnabled = cloud.bool(forKey: "mirrorMode_enabled_\(uid)")
        let cloudGroupId = cloud.string(forKey: "mirrorMode_groupId_\(uid)")
        let localEnabled = isEnabled
        let localGroupId = linkedGroupId

        guard cloudEnabled != localEnabled || cloudGroupId != localGroupId else { return }

        logWarning("[MirrorMode] Cloud state changed: enabled=\(cloudEnabled), groupId=\(cloudGroupId ?? "nil") (local was enabled=\(localEnabled), groupId=\(localGroupId ?? "nil"))")

        if cloudEnabled, let groupId = cloudGroupId {
            guard isOwnerOfGroup(groupId) else {
                logWarning("[MirrorMode] Cloud state enable BLOCKED — current user is not owner of group \(groupId)")
                return
            }
            UserDefaults.standard.set(true, forKey: "mirrorMode_enabled_\(uid)")
            UserDefaults.standard.set(groupId, forKey: "mirrorMode_groupId_\(uid)")
            performInitialMirrorSync(groupId: groupId)
        } else if !cloudEnabled {
            // Only disable if cloud explicitly has the enabled key set to false.
            // cloud.bool(forKey:) returns false for MISSING keys too — a fresh device
            // that never wrote mirror mode state should NOT disable it on other devices.
            guard cloud.object(forKey: "mirrorMode_enabled_\(uid)") != nil else {
                logWarning("[MirrorMode] Cloud state change: ignoring disable — key not explicitly set in cloud (fresh device?)")
                // Seed cloud from local state so the fresh device picks up the correct value
                if localEnabled, let groupId = localGroupId {
                    syncStateToCloud(enabled: true, groupId: groupId, uid: uid)
                }
                return
            }
            let previousGroupId = localGroupId
            UserDefaults.standard.set(false, forKey: "mirrorMode_enabled_\(uid)")
            UserDefaults.standard.removeObject(forKey: "mirrorMode_groupId_\(uid)")
            if let groupId = previousGroupId {
                removeGroupIdFromPersonalData(groupId: groupId)
            }
        }
    }

    /// Checks iCloud key-value store on launch and reconciles with local state.
    /// Uses the groupId key as the source of truth — if nil in cloud, cloud was never written to
    /// and we push local state instead of overriding it.
    func reconcileCloudState() {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return }
        cloud.synchronize()

        let cloudGroupId = cloud.string(forKey: "mirrorMode_groupId_\(uid)")
        let cloudHasData = cloudGroupId != nil || cloud.object(forKey: "mirrorMode_enabled_\(uid)") != nil

        if !cloudHasData {
            // Cloud was never written to — seed it from local state
            if isEnabled, let groupId = linkedGroupId {
                logWarning("[MirrorMode] Seeding cloud state from local: enabled for group \(groupId)")
                syncStateToCloud(enabled: true, groupId: groupId, uid: uid)
            }
            return
        }

        let cloudEnabled = cloud.bool(forKey: "mirrorMode_enabled_\(uid)")

        if cloudEnabled, let groupId = cloudGroupId, !isEnabled {
            guard isOwnerOfGroup(groupId) else {
                logWarning("[MirrorMode] Reconcile enable BLOCKED — current user is not owner of group \(groupId)")
                return
            }
            logWarning("[MirrorMode] Reconciling cloud state: enabling mirror mode for group \(groupId)")
            UserDefaults.standard.set(true, forKey: "mirrorMode_enabled_\(uid)")
            UserDefaults.standard.set(groupId, forKey: "mirrorMode_groupId_\(uid)")
            performInitialMirrorSync(groupId: groupId)
        } else if !cloudEnabled && isEnabled {
            logWarning("[MirrorMode] Reconciling cloud state: disabling mirror mode")
            let previousGroupId = linkedGroupId
            UserDefaults.standard.set(false, forKey: "mirrorMode_enabled_\(uid)")
            UserDefaults.standard.removeObject(forKey: "mirrorMode_groupId_\(uid)")
            if let groupId = previousGroupId {
                removeGroupIdFromPersonalData(groupId: groupId)
            }
        }
    }

    // MARK: - Initial Mirror Sync

    private func performInitialMirrorSync(groupId: String) {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return }
        guard isOwnerOfGroup(groupId) else {
            logWarning("[MirrorMode] performInitialMirrorSync BLOCKED — current user is not owner of group \(groupId)")
            return
        }

        // 1. Transactions: tag all personal transactions with shared_group_id
        db.executeSyncUpdate(
            "UPDATE Transactions SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND (shared_group_id IS NULL OR shared_group_id = '');",
            textBindings: [groupId, uid]
        )

        // 2. Budgets: tag all personal budgets
        db.executeSyncUpdate(
            "UPDATE Budgets SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND (shared_group_id IS NULL OR shared_group_id = '');",
            textBindings: [groupId, uid]
        )

        // 3. Credit Cards: tag all personal credit cards
        db.executeSyncUpdate(
            "UPDATE CreditCards SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND (shared_group_id IS NULL OR shared_group_id = '') AND is_deleted = 0;",
            textBindings: [groupId, uid]
        )

        // 4. Credit Card Statements: mark pending for group-tagged cards
        db.executeSyncUpdate(
            "UPDATE CreditCardStatements SET sync_status = 'pending' WHERE sync_status = 'synced' AND credit_card_id IN (SELECT id FROM CreditCards WHERE user_id = ? AND shared_group_id IS NOT NULL AND shared_group_id != '');",
            textBindings: [uid]
        )

        // 5. Allocations: use existing migration method
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

        logWarning("[MirrorMode] Initial mirror sync completed for group \(groupId)")
    }

    // MARK: - Continuous Reconciliation

    /// Ensures all personal data is tagged with the linked group ID.
    /// Call this after sync pull, lazy generation, or any data mutation to keep mirror mode consistent.
    /// Returns the total number of rows that were actually changed (0 = nothing needed fixing).
    @discardableResult
    func reconcileMirrorData() -> Int {
        guard isEnabled,
              let groupId = linkedGroupId,
              let uid = UIDUserDefaultsManager.shared.currentUserUID
        else {
            logWarning("[MirrorReconcile] SKIPPED — isEnabled=\(isEnabled), linkedGroupId=\(linkedGroupId ?? "nil"), uid=\(UIDUserDefaultsManager.shared.currentUserUID ?? "nil")")
            return 0
        }
        guard isOwnerOfGroup(groupId) else {
            logWarning("[MirrorReconcile] BLOCKED — current user is not owner of group \(groupId), disabling mirror mode")
            disableMirrorMode()
            return 0
        }

        var totalChanged = 0

        // Tag transactions: fix untagged OR wrong group ID (stale from recovery/previous sync)
        totalChanged += db.executeSyncUpdateCount(
            "UPDATE Transactions SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND (shared_group_id IS NULL OR shared_group_id = '' OR shared_group_id != ?) AND (is_deleted IS NULL OR is_deleted = 0);",
            textBindings: [groupId, uid, groupId]
        )

        // Tag budgets: fix untagged OR wrong group ID
        totalChanged += db.executeSyncUpdateCount(
            "UPDATE Budgets SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND (shared_group_id IS NULL OR shared_group_id = '' OR shared_group_id != ?);",
            textBindings: [groupId, uid, groupId]
        )

        // Tag credit cards: fix untagged OR wrong group ID
        totalChanged += db.executeSyncUpdateCount(
            "UPDATE CreditCards SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND (shared_group_id IS NULL OR shared_group_id = '' OR shared_group_id != ?) AND is_deleted = 0;",
            textBindings: [groupId, uid, groupId]
        )

        // Tag allocations: fix untagged OR wrong group ID
        totalChanged += db.executeSyncUpdateCount(
            "UPDATE BudgetAllocations SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND (shared_group_id IS NULL OR shared_group_id = '' OR shared_group_id != ?);",
            textBindings: [groupId, uid, groupId]
        )

        // Mark credit card statements pending ONLY when their parent card was just re-tagged
        // (card sync_status is still 'pending' from the UPDATE above — means it was changed this pass)
        totalChanged += db.executeSyncUpdateCount(
            "UPDATE CreditCardStatements SET sync_status = 'pending' WHERE sync_status = 'synced' AND credit_card_id IN (SELECT id FROM CreditCards WHERE user_id = ? AND sync_status = 'pending' AND shared_group_id IS NOT NULL AND shared_group_id != '');",
            textBindings: [uid]
        )

        // Ensure balance offset stays in sync: personal → group
        // Always call setGroupBalanceOffset to ensure the offset is pushed to the group zone
        // (members need this record to see the correct balance)
        let personalOffset = UIDUserDefaultsManager.shared.getCurrentUserBalanceOffset()
        let groupOffset = UIDUserDefaultsManager.shared.getGroupBalanceOffset(groupId: groupId)
        if personalOffset != groupOffset {
            logInfo("MirrorReconcile: fixed group balance offset \(groupOffset) → \(personalOffset)")
        }
        UIDUserDefaultsManager.shared.setGroupBalanceOffset(personalOffset, groupId: groupId)

        if totalChanged > 0 {
            TransactionRepository.invalidateCache()
        }
        logWarning("[MirrorReconcile] reconciliation completed for group \(groupId) — \(totalChanged) rows changed")
        return totalChanged
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

        logWarning("[MirrorMode] Removed mirror for group \(groupId)")
    }
}
