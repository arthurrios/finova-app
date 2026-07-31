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
    func fetchAllocationsForGroup(groupId: String) -> [BudgetAllocation]
    func insertAllocation(_ model: BudgetAllocationModel) throws -> Int
    func updateAllocation(_ model: BudgetAllocationModel) throws
    func updateRecurringAllocationAndFuture(id: Int, newAmount: Int) throws
    func updateAllRecurringAllocations(id: Int, newAmount: Int) throws
    func updateRecurringAllocationsThrough(id: Int, newAmount: Int, endMonth: Int) throws
    func deleteAllocation(id: Int) throws
    func deleteRecurringAllocationAndFuture(id: Int) throws
    func deleteAllRecurringAllocations(id: Int) throws
    func updateIsRecurring(allocationId: Int, isRecurring: Bool) throws
    /// Batches a multi-row mutation into one transaction + one change notification.
    func performBulk(_ work: () throws -> Void) throws
    func fetchPersonalAllocationsCount() -> Int
    func fetchImportableAllocationsCount() -> Int
    func migrateAllocationsToGroup(groupId: String) -> Int
}

// MARK: - Implementation

final class BudgetAllocationRepository: BudgetAllocationRepositoryProtocol {

    /// Injectable for two-device tests; production always uses `.shared`.
    private let db: DBHelper
    private static let userDefaultsKey = "budgetAllocations"

    init(db: DBHelper = .shared) { self.db = db }

    // MARK: - Change Notification / Bulk Batching

    // `.allocationDataChanged` observers refresh UIKit directly (see MonthCarouselCell), so the
    // notification MUST be posted on the main thread — allocation writes now run on a background
    // queue. And during a multi-row mutation it must fire ONCE at the end, not per row: a 36-month
    // horizon previously posted 36 times, each triggering a full allocation re-query + table
    // reload on the main thread.
    private static var bulkDepth = 0
    private static let bulkLock = NSLock()

    private func notifyAllocationDataChanged() {
        Self.bulkLock.lock()
        let suppressed = Self.bulkDepth > 0
        Self.bulkLock.unlock()
        guard !suppressed else { return }

        // Always deliver asynchronously on main: guarantees UIKit-thread safety, and avoids
        // re-entering an in-flight UIKit update (the observer calls reloadData()) when a write
        // happens to originate on the main thread.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
        }
    }

    /// Runs a multi-row allocation mutation as ONE database transaction (one commit instead of one
    /// per row) and ONE UI notification, emitted after the batch completes. Nesting is safe.
    func performBulk(_ work: () throws -> Void) throws {
        Self.bulkLock.lock(); Self.bulkDepth += 1; Self.bulkLock.unlock()
        defer {
            Self.bulkLock.lock(); Self.bulkDepth -= 1; Self.bulkLock.unlock()
            notifyAllocationDataChanged()
        }
        try db.inTransaction(work)
    }

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

    /// Fix 5a: Fetches only allocations tagged with the given group ID.
    func fetchAllocationsForGroup(groupId: String) -> [BudgetAllocation] {
        let models = db.fetchBudgetAllocationsForGroup(groupId: groupId)
        return models.map { BudgetAllocation(from: $0) }
    }

    // MARK: - Insert

    func insertAllocation(_ model: BudgetAllocationModel) throws -> Int {
        // Check for duplicate (same category and month) WITHIN THE SAME SCOPE.
        //
        // Scope was missing from this predicate, so a group allocation was rejected as a duplicate
        // of the user's personal one for the same category and month — and vice versa. They are
        // separate records in separate ledgers; only a collision inside one ledger is a duplicate.
        // (Same defect family as Budgets' global `month_date` primary key, fixed in Stage 2.)
        let allModels = db.fetchAllBudgetAllocations(userId: UIDUserDefaultsManager.shared.currentUserUID)
        if allModels.contains(where: {
            $0.categoryKey == model.categoryKey
                && $0.monthDate == model.monthDate
                && ($0.sharedGroupId ?? "") == (model.sharedGroupId ?? "")
        }) {
            throw BudgetAllocationError.duplicateAllocation
        }

        let newId = db.insertBudgetAllocation(model)
        guard newId > 0 else {
            throw BudgetAllocationError.invalidAmount
        }

        notifyAllocationDataChanged()

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

        notifyAllocationDataChanged()
    }

    func updateRecurringAllocationAndFuture(id: Int, newAmount: Int) throws {
        guard let allocation = db.fetchBudgetAllocation(byId: id) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for future update")
            throw BudgetAllocationError.allocationNotFound
        }

        let parentId = allocation.parentAllocationId ?? id
        let currentMonthDate = allocation.monthDate
        let now = Int(Date().timeIntervalSince1970)

        let allModels = db.fetchAllBudgetAllocations(userId: UIDUserDefaultsManager.shared.currentUserUID)
        // One transaction + one UI notification for the whole series (was: a commit and a full
        // main-thread allocation refresh per updated row).
        try performBulk {
            for model in allModels {
                guard let modelId = model.id else { continue }

                let isCurrentAllocation = modelId == id
                let isParent = modelId == parentId
                let isRelatedChild = model.parentAllocationId == parentId
                let isFutureOrCurrent = model.monthDate >= currentMonthDate

                if isCurrentAllocation || ((isParent || isRelatedChild) && isFutureOrCurrent) {
                    db.executeSyncUpdate(
                        "UPDATE BudgetAllocations SET allocated_amount = ?, sync_status = 'pending', ck_modified_at = ?, updated_at = ? WHERE id = ?;",
                        intBindings: [newAmount, now, now, modelId]
                    )
                }
            }
        }
    }

    /// Updates this occurrence and every later one in the series UP TO AND INCLUDING `endMonth`.
    /// Occurrences after `endMonth` keep their current amount — this is the "this through <month>"
    /// bounded edit.
    func updateRecurringAllocationsThrough(id: Int, newAmount: Int, endMonth: Int) throws {
        guard let allocation = db.fetchBudgetAllocation(byId: id) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for bounded update")
            throw BudgetAllocationError.allocationNotFound
        }

        let parentId = allocation.parentAllocationId ?? id
        let currentMonthDate = allocation.monthDate
        let now = Int(Date().timeIntervalSince1970)

        let allModels = db.fetchAllBudgetAllocations(userId: UIDUserDefaultsManager.shared.currentUserUID)
        try performBulk {
            for model in allModels {
                guard let modelId = model.id else { continue }

                let isCurrentAllocation = modelId == id
                let isRelated = modelId == parentId || model.parentAllocationId == parentId
                let inRange = model.monthDate >= currentMonthDate && model.monthDate <= endMonth

                if isCurrentAllocation || (isRelated && inRange) {
                    db.executeSyncUpdate(
                        "UPDATE BudgetAllocations SET allocated_amount = ?, sync_status = 'pending', ck_modified_at = ?, updated_at = ? WHERE id = ?;",
                        intBindings: [newAmount, now, now, modelId]
                    )
                }
            }
        }
    }

    func updateAllRecurringAllocations(id: Int, newAmount: Int) throws {
        guard let allocation = db.fetchBudgetAllocation(byId: id) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for all update")
            throw BudgetAllocationError.allocationNotFound
        }

        let parentId = allocation.parentAllocationId ?? id
        let now = Int(Date().timeIntervalSince1970)

        let allModels = db.fetchAllBudgetAllocations(userId: UIDUserDefaultsManager.shared.currentUserUID)
        // One transaction + one UI notification for the whole series.
        try performBulk {
            for model in allModels {
                guard let modelId = model.id else { continue }
                if modelId == parentId || model.parentAllocationId == parentId {
                    db.executeSyncUpdate(
                        "UPDATE BudgetAllocations SET allocated_amount = ?, sync_status = 'pending', ck_modified_at = ?, updated_at = ? WHERE id = ?;",
                        intBindings: [newAmount, now, now, modelId]
                    )
                }
            }
        }
    }

    // MARK: - Delete

    func deleteAllocation(id: Int) throws {
        guard let allocationToDelete = db.fetchBudgetAllocation(byId: id) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for deletion")
            throw BudgetAllocationError.allocationNotFound
        }

        let now = Int(Date().timeIntervalSince1970)

        if let parentId = allocationToDelete.parentAllocationId {
            db.executeSyncUpdate(
                "UPDATE BudgetAllocations SET is_recurring = 0, sync_status = 'pending', ck_modified_at = ?, updated_at = ? WHERE id = ?;",
                intBindings: [now, now, parentId]
            )
        }

        let ckName = fetchCKRecordName(for: id)
        if ckName != nil {
            db.executeSyncUpdate(
                "UPDATE BudgetAllocations SET is_deleted = 1, sync_status = 'pendingDelete', ck_modified_at = ?, updated_at = ? WHERE id = ?;",
                intBindings: [now, now, id]
            )
        } else {
            db.executeSyncUpdate(
                "DELETE FROM BudgetAllocations WHERE id = ?;",
                intBindings: [id]
            )
        }

        notifyAllocationDataChanged()
    }

    func deleteRecurringAllocationAndFuture(id: Int) throws {
        guard let allocation = db.fetchBudgetAllocation(byId: id) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for future deletion")
            throw BudgetAllocationError.allocationNotFound
        }

        let parentId = allocation.parentAllocationId ?? id
        let currentMonthDate = allocation.monthDate

        let allModels = db.fetchAllBudgetAllocations(userId: UIDUserDefaultsManager.shared.currentUserUID)
        // Whole delete-future operation (deletes + backfill inserts + parent update) as ONE
        // transaction and ONE UI notification.
        try performBulk {
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

            // Preserve months between the parent and the cutoff that were never materialized,
            // BEFORE disabling the parent's recurrence below (which stops all future
            // generation — including pre-cutoff months that lazy generation never created).
            backfillRecurringAllocationMonths(parentId: parentId, cutoffMonth: currentMonthDate)

            // Stop parent from generating future instances
            if db.fetchBudgetAllocation(byId: parentId) != nil {
                db.executeSyncUpdate(
                    "UPDATE BudgetAllocations SET is_recurring = 0, sync_status = 'pending' WHERE id = ?;",
                    intBindings: [parentId]
                )
            }
        }
    }

    /// Materializes any missing recurring allocation instances for months strictly
    /// between the parent's own month and `cutoffMonth`, inheriting the amount from the
    /// occurrence in effect at each month. Called by "delete future" before the parent's
    /// recurrence is disabled, so pre-cutoff months that were never lazily generated
    /// aren't lost. Mirrors the recurring-transaction backfill.
    private func backfillRecurringAllocationMonths(parentId: Int, cutoffMonth: Int) {
        let all = db.fetchAllBudgetAllocations(userId: UIDUserDefaultsManager.shared.currentUserUID)
        guard let parent = all.first(where: { $0.id == parentId }) else { return }
        let startMonth = parent.monthDate
        guard startMonth < cutoffMonth else { return }

        // Occurrences of this series, ascending, for picking the in-effect template.
        let series = all
            .filter { $0.id == parentId || $0.parentAllocationId == parentId }
            .sorted { $0.monthDate < $1.monthDate }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        var date = Date(timeIntervalSince1970: TimeInterval(startMonth))
        var steps = 0
        while steps < 600 {  // safety bound (~50 years)
            steps += 1
            guard let next = cal.date(byAdding: .month, value: 1, to: date) else { break }
            date = next
            let monthAnchor = next.monthAnchor
            if monthAnchor >= cutoffMonth { break }

            // Skip if any allocation already exists for this month+category.
            let exists = all.contains {
                $0.monthDate == monthAnchor && $0.categoryKey == parent.categoryKey
            }
            if exists { continue }

            let template = series.last(where: { $0.monthDate <= monthAnchor }) ?? parent
            let instance = BudgetAllocationModel(
                monthDate: monthAnchor,
                categoryKey: parent.categoryKey,
                allocatedAmount: template.allocatedAmount,
                isRecurring: true,
                parentAllocationId: parentId,
                sharedGroupId: parent.sharedGroupId
            )
            _ = try? insertAllocation(instance)
        }
    }

    func deleteAllRecurringAllocations(id: Int) throws {
        guard let allocation = db.fetchBudgetAllocation(byId: id) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for all deletion")
            throw BudgetAllocationError.allocationNotFound
        }

        let parentId = allocation.parentAllocationId ?? id

        let allModels = db.fetchAllBudgetAllocations(userId: UIDUserDefaultsManager.shared.currentUserUID)
        // One transaction + one UI notification for the whole series.
        try performBulk {
            for model in allModels {
                guard let modelId = model.id else { continue }
                if modelId == parentId || model.parentAllocationId == parentId {
                    softDeleteOrHardDelete(id: modelId)
                }
            }
        }
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

    /// See `TransactionRepository.markAsSynced` for why `pushedUpdatedAt` matters: without it, an
    /// edit made while the push was in flight is marked synced and never pushed.
    func markAsSynced(ckRecordName: String, pushedUpdatedAt: Date? = nil) {
        if let pushedUpdatedAt = pushedUpdatedAt {
            db.executeSyncUpdate(
                "UPDATE BudgetAllocations SET sync_status = 'synced' WHERE ck_record_id = ? AND COALESCE(updated_at, 0) <= ?;",
                textBindings: [ckRecordName],
                intBindings: [Int(pushedUpdatedAt.timeIntervalSince1970)]
            )
            return
        }
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
                 parent_allocation_id, user_id, shared_group_id, ck_record_id, sync_status, ck_modified_at, updated_at, created_by_uid)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?, ?, ?);
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
                Int((allocation.updatedAt ?? Date()).timeIntervalSince1970),
                allocation.createdByUid
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
                created_by_uid = COALESCE(?, created_by_uid), is_deleted = 0
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
                allocation.createdByUid,
                ckRecordName
            ]
        )
    }

    /// Updates an allocation matched by local ID (natural-key dedup) and links it to a CK record.
    func updateFromCloud(_ allocation: BudgetAllocationModel, localId: Int, ckRecordName: String) {
        db.executeGroupWrite(
            """
            UPDATE BudgetAllocations SET
                month_date = ?, category_key = ?, allocated_amount = ?,
                is_recurring = ?, parent_allocation_id = ?,
                shared_group_id = ?, ck_record_id = ?,
                sync_status = 'synced', ck_modified_at = ?, updated_at = ?,
                created_by_uid = COALESCE(?, created_by_uid), is_deleted = 0
            WHERE id = ?;
            """,
            orderedBindings: [
                allocation.monthDate,
                allocation.categoryKey,
                allocation.allocatedAmount,
                allocation.isRecurring ? 1 : 0,
                allocation.parentAllocationId,
                allocation.sharedGroupId,
                ckRecordName,
                Int(Date().timeIntervalSince1970),
                Int((allocation.updatedAt ?? Date()).timeIntervalSince1970),
                allocation.createdByUid,
                localId
            ]
        )
    }

    /// Links a CK record name to a local allocation (local data wins, mark pending for next push).
    func linkCKRecordName(_ ckRecordName: String, toLocalId localId: Int) {
        db.executeGroupWrite(
            "UPDATE BudgetAllocations SET ck_record_id = ?, sync_status = 'pending' WHERE id = ?;",
            orderedBindings: [ckRecordName, localId]
        )
    }

    func deleteFromCloud(ckRecordName recordName: String) {
        // RECREATION-WINS guard: keep a row with unpushed local edits rather than applying a
        // remote delete (it re-pushes, preserving the newer local change).
        if db.fetchSingleString("SELECT sync_status FROM BudgetAllocations WHERE ck_record_id = ?;", textBinding: recordName) == "pending" {
            return
        }
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

    /// Finds an active allocation matching the natural key (monthDate + categoryKey)
    /// within the same group context. Used as a deduplication fallback when the CK
    /// record name doesn't match any local row.
    func fetchAllocation(byMonthDate monthDate: Int, categoryKey: String, sharedGroupId: String?) -> BudgetAllocationModel? {
        let query: String
        let bindings: [Any?]
        if let groupId = sharedGroupId, !groupId.isEmpty {
            query = "SELECT id FROM BudgetAllocations WHERE month_date = ? AND category_key = ? AND shared_group_id = ? AND (is_deleted IS NULL OR is_deleted = 0) LIMIT 1;"
            bindings = [monthDate, categoryKey, groupId]
        } else {
            query = "SELECT id FROM BudgetAllocations WHERE month_date = ? AND category_key = ? AND (shared_group_id IS NULL OR shared_group_id = '') AND (is_deleted IS NULL OR is_deleted = 0) LIMIT 1;"
            bindings = [monthDate, categoryKey]
        }
        guard let id = db.fetchSingleInt(query, orderedBindings: bindings) else { return nil }
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
        let now = Int(Date().timeIntervalSince1970)
        if ckName != nil {
            db.executeSyncUpdate(
                "UPDATE BudgetAllocations SET is_deleted = 1, sync_status = 'pendingDelete', ck_modified_at = ?, updated_at = ? WHERE id = ?;",
                intBindings: [now, now, id]
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
        let now = Int(Date().timeIntervalSince1970)
        // Use executeGroupWrite for mixed binding types
        db.executeGroupWrite(
            """
            UPDATE BudgetAllocations SET
                month_date = ?, category_key = ?, allocated_amount = ?,
                is_recurring = ?, parent_allocation_id = ?, shared_group_id = ?,
                sync_status = 'pending', ck_modified_at = ?, updated_at = ?
            WHERE id = ?;
            """,
            orderedBindings: [
                model.monthDate,
                model.categoryKey,
                model.allocatedAmount,
                model.isRecurring ? 1 : 0,
                model.parentAllocationId,
                model.sharedGroupId,
                now,
                now,
                id
            ]
        )
    }

}

// MARK: - Notification Extension

extension Notification.Name {
    static let allocationDataChanged = Notification.Name("allocationDataChanged")
}
