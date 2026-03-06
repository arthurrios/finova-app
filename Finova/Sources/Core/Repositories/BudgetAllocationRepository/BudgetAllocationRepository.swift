//
//  BudgetAllocationRepository.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import Foundation

// MARK: - Protocol

protocol BudgetAllocationRepositoryProtocol {
    func fetchAllocations(for monthDate: Int) -> [BudgetAllocation]
    func fetchAllAllocations() -> [BudgetAllocation]
    func insertAllocation(_ model: BudgetAllocationModel) throws -> Int
    func updateAllocation(_ model: BudgetAllocationModel) throws
    func updateRecurringAllocationAndFuture(id: Int, newAmount: Int) throws
    func updateAllRecurringAllocations(id: Int, newAmount: Int) throws
    func deleteAllocation(id: Int) throws
    func deleteRecurringAllocationAndFuture(id: Int) throws
    func deleteAllRecurringAllocations(id: Int) throws
    func updateIsRecurring(allocationId: Int, isRecurring: Bool) throws
    func fetchPersonalAllocationsCount() -> Int
    func fetchImportableAllocationsCount() -> Int
    func migrateAllocationsToGroup(groupId: String) -> Int
}

// MARK: - Implementation

final class BudgetAllocationRepository: BudgetAllocationRepositoryProtocol {

    private let db = DBHelper.shared
    private static let userDefaultsKey = "budgetAllocations"

    // MARK: - One-Time Migration from UserDefaults to SQLite

    static func migrateFromUserDefaultsIfNeeded() {
        let migrationKey = "budgetAllocations_migrated_to_sqlite"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let models = try? JSONDecoder().decode([BudgetAllocationModel].self, from: data),
              !models.isEmpty
        else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        let db = DBHelper.shared
        for model in models {
            _ = db.insertBudgetAllocation(model)
        }

        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.set(true, forKey: migrationKey)
        logInfo("BudgetAllocationRepository: Migrated \(models.count) allocations from UserDefaults to SQLite")
    }

    // MARK: - Fetch Methods

    func fetchAllocations(for monthDate: Int) -> [BudgetAllocation] {
        let allAllocations = fetchAllAllocations()
        return allAllocations.filter { $0.monthDate == monthDate }
    }

    func fetchAllAllocations() -> [BudgetAllocation] {
        let uid = UIDUserDefaultsManager.shared.currentUserUID
        let models = db.fetchAllBudgetAllocations(userId: uid)
        return models.map { BudgetAllocation(from: $0) }
    }

    // MARK: - Insert

    func insertAllocation(_ model: BudgetAllocationModel) throws -> Int {
        // Check for duplicate (same category and month)
        let allModels = db.fetchAllBudgetAllocations(userId: UIDUserDefaultsManager.shared.currentUserUID)
        if allModels.contains(where: {
            $0.categoryKey == model.categoryKey && $0.monthDate == model.monthDate
        }) {
            throw BudgetAllocationError.duplicateAllocation
        }

        let newId = db.insertBudgetAllocation(model)
        guard newId > 0 else {
            throw BudgetAllocationError.invalidAmount
        }

        if MirrorModeManager.shared.isEnabled,
           let groupId = MirrorModeManager.shared.linkedGroupId,
           model.sharedGroupId == nil {
            updateSharedGroupId(allocationId: newId, groupId: groupId)
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
        }

        return newId
    }

    // MARK: - Update

    func updateAllocation(_ model: BudgetAllocationModel) throws {
        guard let id = model.id else {
            throw BudgetAllocationError.allocationNotFound
        }

        guard db.fetchBudgetAllocation(byId: id) != nil else {
            logError("BudgetAllocationRepository: Could not find allocation with id \(id)")
            throw BudgetAllocationError.allocationNotFound
        }

        updateAllocationRow(model)

        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
    }

    func updateRecurringAllocationAndFuture(id: Int, newAmount: Int) throws {
        guard let allocation = db.fetchBudgetAllocation(byId: id) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for future update")
            throw BudgetAllocationError.allocationNotFound
        }

        let parentId = allocation.parentAllocationId ?? id
        let currentMonthDate = allocation.monthDate

        let allModels = db.fetchAllBudgetAllocations(userId: UIDUserDefaultsManager.shared.currentUserUID)
        for model in allModels {
            guard let modelId = model.id else { continue }

            let isCurrentAllocation = modelId == id
            let isParent = modelId == parentId
            let isRelatedChild = model.parentAllocationId == parentId
            let isFutureOrCurrent = model.monthDate >= currentMonthDate

            if isCurrentAllocation || ((isParent || isRelatedChild) && isFutureOrCurrent) {
                db.executeSyncUpdate(
                    "UPDATE BudgetAllocations SET allocated_amount = ?, sync_status = 'pending' WHERE id = ?;",
                    intBindings: [newAmount, modelId]
                )
            }
        }

        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
    }

    func updateAllRecurringAllocations(id: Int, newAmount: Int) throws {
        guard let allocation = db.fetchBudgetAllocation(byId: id) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for all update")
            throw BudgetAllocationError.allocationNotFound
        }

        let parentId = allocation.parentAllocationId ?? id

        let allModels = db.fetchAllBudgetAllocations(userId: UIDUserDefaultsManager.shared.currentUserUID)
        for model in allModels {
            guard let modelId = model.id else { continue }
            if modelId == parentId || model.parentAllocationId == parentId {
                db.executeSyncUpdate(
                    "UPDATE BudgetAllocations SET allocated_amount = ?, sync_status = 'pending' WHERE id = ?;",
                    intBindings: [newAmount, modelId]
                )
            }
        }

        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
    }

    // MARK: - Delete

    func deleteAllocation(id: Int) throws {
        guard let allocationToDelete = db.fetchBudgetAllocation(byId: id) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for deletion")
            throw BudgetAllocationError.allocationNotFound
        }

        if let parentId = allocationToDelete.parentAllocationId {
            db.executeSyncUpdate(
                "UPDATE BudgetAllocations SET is_recurring = 0, sync_status = 'pending' WHERE id = ?;",
                intBindings: [parentId]
            )
        }

        let ckName = fetchCKRecordName(for: id)
        if ckName != nil {
            db.executeSyncUpdate(
                "UPDATE BudgetAllocations SET is_deleted = 1, sync_status = 'pendingDelete' WHERE id = ?;",
                intBindings: [id]
            )
        } else {
            db.executeSyncUpdate(
                "DELETE FROM BudgetAllocations WHERE id = ?;",
                intBindings: [id]
            )
        }

        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
    }

    func deleteRecurringAllocationAndFuture(id: Int) throws {
        guard let allocation = db.fetchBudgetAllocation(byId: id) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for future deletion")
            throw BudgetAllocationError.allocationNotFound
        }

        let parentId = allocation.parentAllocationId ?? id
        let currentMonthDate = allocation.monthDate

        let allModels = db.fetchAllBudgetAllocations(userId: UIDUserDefaultsManager.shared.currentUserUID)
        for model in allModels {
            guard let modelId = model.id else { continue }

            if modelId == id {
                softDeleteOrHardDelete(id: modelId)
                continue
            }

            let isRelated = modelId == parentId || model.parentAllocationId == parentId
            let isFutureOrCurrent = model.monthDate >= currentMonthDate
            if isRelated && isFutureOrCurrent {
                softDeleteOrHardDelete(id: modelId)
            }
        }

        // Stop parent from generating future instances
        if db.fetchBudgetAllocation(byId: parentId) != nil {
            db.executeSyncUpdate(
                "UPDATE BudgetAllocations SET is_recurring = 0, sync_status = 'pending' WHERE id = ?;",
                intBindings: [parentId]
            )
        }

        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
    }

    func deleteAllRecurringAllocations(id: Int) throws {
        guard let allocation = db.fetchBudgetAllocation(byId: id) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for all deletion")
            throw BudgetAllocationError.allocationNotFound
        }

        let parentId = allocation.parentAllocationId ?? id

        let allModels = db.fetchAllBudgetAllocations(userId: UIDUserDefaultsManager.shared.currentUserUID)
        for model in allModels {
            guard let modelId = model.id else { continue }
            if modelId == parentId || model.parentAllocationId == parentId {
                softDeleteOrHardDelete(id: modelId)
            }
        }

        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
    }

    // MARK: - Update Is Recurring

    func updateIsRecurring(allocationId: Int, isRecurring: Bool) throws {
        guard db.fetchBudgetAllocation(byId: allocationId) != nil else {
            logError("BudgetAllocationRepository: Allocation with id \(allocationId) not found for isRecurring update")
            throw BudgetAllocationError.allocationNotFound
        }

        db.executeSyncUpdate(
            "UPDATE BudgetAllocations SET is_recurring = ?, sync_status = 'pending' WHERE id = ?;",
            intBindings: [isRecurring ? 1 : 0, allocationId]
        )
    }

    // MARK: - Mirror Mode

    func updateSharedGroupId(allocationId: Int, groupId: String?) {
        if let groupId = groupId {
            db.executeSyncUpdate(
                "UPDATE BudgetAllocations SET shared_group_id = ?, sync_status = 'pending' WHERE id = ?;",
                textBindings: [groupId],
                intBindings: [allocationId]
            )
        } else {
            db.executeSyncUpdate(
                "UPDATE BudgetAllocations SET shared_group_id = NULL, sync_status = 'pending' WHERE id = ?;",
                intBindings: [allocationId]
            )
        }
    }

    // MARK: - Group Migration

    func fetchPersonalAllocationsCount() -> Int {
        let models = db.fetchAllBudgetAllocations(userId: UIDUserDefaultsManager.shared.currentUserUID)
        return models.filter { $0.sharedGroupId == nil }.count
    }

    func fetchImportableAllocationsCount() -> Int {
        let models = db.fetchAllBudgetAllocations(userId: UIDUserDefaultsManager.shared.currentUserUID)
        let activeGroupIds = Set(BudgetGroupRepository().fetchAllGroups().map { $0.id })
        return models.filter { model in
            model.sharedGroupId == nil || !activeGroupIds.contains(model.sharedGroupId ?? "")
        }.count
    }

    func migrateAllocationsToGroup(groupId: String) -> Int {
        let models = db.fetchAllBudgetAllocations(userId: UIDUserDefaultsManager.shared.currentUserUID)
        let activeGroupIds = Set(BudgetGroupRepository().fetchAllGroups().map { $0.id })
        var migratedCount = 0

        for model in models {
            let isImportable = model.sharedGroupId == nil || !activeGroupIds.contains(model.sharedGroupId ?? "")
            guard isImportable, let id = model.id else { continue }
            db.executeSyncUpdate(
                "UPDATE BudgetAllocations SET shared_group_id = ?, sync_status = 'pending' WHERE id = ?;",
                textBindings: [groupId],
                intBindings: [id]
            )
            migratedCount += 1
        }

        if migratedCount > 0 {
            logDebug("BudgetAllocationRepository: Migrated \(migratedCount) allocations to group \(groupId)")
        }

        return migratedCount
    }

    // MARK: - CloudKit Sync Methods

    func fetchPendingSync() -> [BudgetAllocationModel] {
        return db.fetchPendingSyncAllocations(
            userId: UIDUserDefaultsManager.shared.currentUserUID
        )
    }

    func markAsSynced(ckRecordName: String) {
        // Phase 3C: CK record name is pre-stored before push, so matching by ck_record_id is sufficient
        db.executeSyncUpdate(
            "UPDATE BudgetAllocations SET sync_status = 'synced' WHERE ck_record_id = ?;",
            textBindings: [ckRecordName]
        )
    }

    func insertFromCloud(_ allocation: BudgetAllocationModel, ckRecordName: String) {
        db.executeSyncUpdate(
            "DELETE FROM BudgetAllocations WHERE ck_record_id = ?;",
            textBindings: [ckRecordName]
        )

        db.executeGroupWrite(
            """
            INSERT INTO BudgetAllocations
                (month_date, category_key, allocated_amount, is_recurring,
                 parent_allocation_id, user_id, shared_group_id, ck_record_id, sync_status, ck_modified_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?, ?);
            """,
            orderedBindings: [
                allocation.monthDate,
                allocation.categoryKey,
                allocation.allocatedAmount,
                allocation.isRecurring ? 1 : 0,
                allocation.parentAllocationId,
                UIDUserDefaultsManager.shared.currentUserUID,
                allocation.sharedGroupId,
                ckRecordName,
                Int(Date().timeIntervalSince1970),
                Int((allocation.updatedAt ?? Date()).timeIntervalSince1970)
            ]
        )
    }

    func updateFromCloud(_ allocation: BudgetAllocationModel, ckRecordName: String) {
        db.executeGroupWrite(
            """
            UPDATE BudgetAllocations SET
                month_date = ?, category_key = ?, allocated_amount = ?,
                is_recurring = ?, parent_allocation_id = ?,
                shared_group_id = ?,
                sync_status = 'synced', ck_modified_at = ?, updated_at = ?,
                is_deleted = 0
            WHERE ck_record_id = ?;
            """,
            orderedBindings: [
                allocation.monthDate,
                allocation.categoryKey,
                allocation.allocatedAmount,
                allocation.isRecurring ? 1 : 0,
                allocation.parentAllocationId,
                allocation.sharedGroupId,
                Int(Date().timeIntervalSince1970),
                Int((allocation.updatedAt ?? Date()).timeIntervalSince1970),
                ckRecordName
            ]
        )
    }

    func deleteFromCloud(ckRecordName recordName: String) {
        db.executeSyncUpdate(
            "DELETE FROM BudgetAllocations WHERE ck_record_id = ?;",
            textBindings: [recordName]
        )
    }

    func fetchPendingDeletes() -> [(ckRecordName: String, localId: Int)] {
        let query = "SELECT id, ck_record_id FROM BudgetAllocations WHERE sync_status = 'pendingDelete' AND ck_record_id IS NOT NULL;"
        return db.fetchIdAndCKRecordName(query) ?? []
    }

    func hardDeleteByCKRecordName(_ recordName: String) {
        db.executeSyncUpdate(
            "DELETE FROM BudgetAllocations WHERE ck_record_id = ?;",
            textBindings: [recordName]
        )
    }

    func fetchCKRecordName(for id: Int) -> String? {
        return db.fetchSingleString(
            "SELECT ck_record_id FROM BudgetAllocations WHERE id = ?;",
            intBinding: id
        )
    }

    func fetchAllocation(byCKRecordName recordName: String) -> BudgetAllocationModel? {
        let id = db.fetchSingleInt(
            "SELECT id FROM BudgetAllocations WHERE ck_record_id = ? AND (is_deleted IS NULL OR is_deleted = 0);",
            textBinding: recordName
        )
        guard let id = id else { return nil }
        return db.fetchBudgetAllocation(byId: id)
    }

    /// If a soft-deleted allocation with this CK record name exists (is_deleted=1),
    /// restores its sync_status to 'pendingDelete' so the next push will remove it from
    /// CloudKit. Returns true if such a record was found (caller should skip re-insertion).
    func restorePendingDeleteIfNeeded(ckRecordName: String) -> Bool {
        let check = "SELECT id FROM BudgetAllocations WHERE ck_record_id = ? AND is_deleted = 1;"
        guard db.fetchSingleInt(check, textBinding: ckRecordName) != nil else { return false }
        db.executeSyncUpdate(
            "UPDATE BudgetAllocations SET sync_status = 'pendingDelete' WHERE ck_record_id = ? AND is_deleted = 1;",
            textBindings: [ckRecordName]
        )
        return true
    }

    func lastModifiedDate(for id: Int) -> Date? {
        let query = "SELECT updated_at FROM BudgetAllocations WHERE id = ?;"
        guard let timestamp = db.fetchSingleInt(query, intBinding: id), timestamp > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    func markSyncPending(for id: Int) {
        let now = Int(Date().timeIntervalSince1970)
        db.executeSyncUpdate(
            "UPDATE BudgetAllocations SET sync_status = 'pending', ck_modified_at = ? WHERE id = ?;",
            intBindings: [now, id]
        )
    }

    func setCKRecordId(for localId: Int, ckRecordName: String) {
        db.executeSyncUpdate(
            "UPDATE BudgetAllocations SET ck_record_id = ? WHERE id = ? AND ck_record_id IS NULL;",
            textBindings: [ckRecordName],
            intBindings: [localId]
        )
    }

    // MARK: - Private Helpers

    /// Soft-deletes a synced allocation (marks pendingDelete) or hard-deletes an unsynced one.
    private func softDeleteOrHardDelete(id: Int) {
        let ckName = fetchCKRecordName(for: id)
        if ckName != nil {
            db.executeSyncUpdate(
                "UPDATE BudgetAllocations SET is_deleted = 1, sync_status = 'pendingDelete' WHERE id = ?;",
                intBindings: [id]
            )
        } else {
            db.executeSyncUpdate(
                "DELETE FROM BudgetAllocations WHERE id = ?;",
                intBindings: [id]
            )
        }
    }

    private func updateAllocationRow(_ model: BudgetAllocationModel) {
        guard let id = model.id else { return }
        // Use executeGroupWrite for mixed binding types
        db.executeGroupWrite(
            """
            UPDATE BudgetAllocations SET
                month_date = ?, category_key = ?, allocated_amount = ?,
                is_recurring = ?, parent_allocation_id = ?, shared_group_id = ?,
                sync_status = 'pending'
            WHERE id = ?;
            """,
            orderedBindings: [
                model.monthDate,
                model.categoryKey,
                model.allocatedAmount,
                model.isRecurring ? 1 : 0,
                model.parentAllocationId,
                model.sharedGroupId,
                id
            ]
        )
    }

}

// MARK: - Notification Extension

extension Notification.Name {
    static let allocationDataChanged = Notification.Name("allocationDataChanged")
}
