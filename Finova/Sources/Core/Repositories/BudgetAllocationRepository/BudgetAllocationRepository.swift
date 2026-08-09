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
    /// Months each series had deleted, so generation never recreates them.
    func deletedMonthsBySeries() -> [Int: Set<Int>]
    func insertAllocation(_ model: BudgetAllocationModel) throws -> Int
    func updateAllocation(_ model: BudgetAllocationModel) throws
    func updateRecurringAllocationAndFuture(id: Int, newAmount: Int) throws
    func updateAllRecurringAllocations(id: Int, newAmount: Int) throws
    func deleteAllocation(id: Int) throws
    func deleteRecurringAllocationAndFuture(id: Int) throws
    func deleteAllRecurringAllocations(id: Int) throws
    func updateIsRecurring(allocationId: Int, isRecurring: Bool) throws
    func updateParentAllocationId(id: Int, parentId: Int) throws
}

// MARK: - Implementation

final class BudgetAllocationRepository: BudgetAllocationRepositoryProtocol {

    private let db = DBHelper.shared
    private let userDefaultsKey = "budgetAllocations"

    // MARK: - Fetch Methods

    func fetchAllocations(for monthDate: Int) -> [BudgetAllocation] {
        let allAllocations = fetchAllAllocations()
        return allAllocations.filter { $0.monthDate == monthDate }
    }

    func fetchAllAllocations() -> [BudgetAllocation] {
        liveModels().map { BudgetAllocation(from: $0) }
    }

    /// Months this series had deleted, keyed by series. Consulted by generation so a month the user
    /// removed is never recreated.
    ///
    /// SERIES-keyed rather than (month, category): keying on the category alone would suppress that
    /// month for every FUTURE series of the same category too, leaving each new series born with a
    /// permanent hole wherever an older one had been deleted.
    func deletedMonthsBySeries() -> [Int: Set<Int>] {
        var result: [Int: Set<Int>] = [:]
        for model in loadModels() where !model.isLive {
            guard let seriesId = model.seriesId else { continue }
            result[seriesId, default: []].insert(model.monthDate)
        }
        return result
    }

    // MARK: - Insert

    func insertAllocation(_ model: BudgetAllocationModel) throws -> Int {
        var models = loadModels()

        // Check for duplicate (same category and month) among LIVE rows only. A tombstone is a
        // record that the user removed that month, not a row occupying it — counting it here would
        // make re-creating a deleted month impossible.
        if models.contains(where: {
            $0.isLive && $0.categoryKey == model.categoryKey && $0.monthDate == model.monthDate
        }) {
            throw BudgetAllocationError.duplicateAllocation
        }

        // Generate new ID
        let newId = (models.map { $0.id ?? 0 }.max() ?? 0) + 1
        let modelWithId = BudgetAllocationModel(
            id: newId,
            monthDate: model.monthDate,
            categoryKey: model.categoryKey,
            allocatedAmount: model.allocatedAmount,
            isRecurring: model.isRecurring,
            parentAllocationId: model.parentAllocationId
        )

        models.append(modelWithId)
        saveModels(models)

        // Notify that data has changed (ensure on main thread for UI updates)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
        }

        return newId
    }

    // MARK: - Update

    func updateAllocation(_ model: BudgetAllocationModel) throws {
        var models = loadModels()

        logDebug("BudgetAllocationRepository: updateAllocation called for id \(String(describing: model.id))")
        logDebug("BudgetAllocationRepository: Looking for model with id \(String(describing: model.id)) in \(models.count) models")
        logDebug("BudgetAllocationRepository: Available IDs: \(models.compactMap { $0.id })")

        guard let index = models.firstIndex(where: { $0.id != nil && $0.id! == model.id && $0.isLive }) else {
            logError("BudgetAllocationRepository: Could not find allocation with id \(String(describing: model.id))")
            throw BudgetAllocationError.allocationNotFound
        }

        logDebug("BudgetAllocationRepository: Found allocation at index \(index), updating ONLY this one")
        logDebug("BudgetAllocationRepository: Before - amount: \(models[index].allocatedAmount), After - amount: \(model.allocatedAmount)")

        models[index] = model
        saveModels(models)

        // Notify that data has changed
        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
    }

    func updateRecurringAllocationAndFuture(id: Int, newAmount: Int) throws {
        var models = loadModels()

        logDebug("BudgetAllocationRepository: updateRecurringAllocationAndFuture called with id: \(id), newAmount: \(newAmount)")
        logDebug("BudgetAllocationRepository: Total models in storage: \(models.count)")

        guard let allocation = models.first(where: { $0.id != nil && $0.id! == id && $0.isLive }) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for future update")
            throw BudgetAllocationError.allocationNotFound
        }

        // Get the parent allocation ID
        let parentId = allocation.parentAllocationId ?? id
        logDebug("BudgetAllocationRepository: Current allocation parentAllocationId: \(String(describing: allocation.parentAllocationId)), using parentId: \(parentId)")

        // Find the current allocation's month date
        let currentMonthDate = allocation.monthDate
        logDebug("BudgetAllocationRepository: Current allocation monthDate: \(currentMonthDate)")

        var updatedCount = 0
        var updatedIds: [Int] = []

        // Update all allocations with the same parent that are >= current month
        // ALSO update the parent allocation so future lazily-generated instances use the new amount
        for i in models.indices {
            // Tombstones are skipped: editing one would both revive a month the user deleted (the
            // rebuild below drops the flag) and count towards the edit.
            guard let modelId = models[i].id, models[i].isLive else { continue }

            // Check if this is the allocation being updated
            let isCurrentAllocation = modelId == id

            // Check if this is the parent (must update parent so future instances get new amount)
            let isParent = modelId == parentId

            // Check if this is a child allocation in the future
            let isRelatedChild = models[i].parentAllocationId == parentId
            let isFutureOrCurrent = models[i].monthDate >= currentMonthDate

            if isCurrentAllocation || isParent || (isRelatedChild && isFutureOrCurrent) {
                logDebug("BudgetAllocationRepository: Updating allocation id=\(modelId), monthDate=\(models[i].monthDate), reason: isCurrentAllocation=\(isCurrentAllocation), isParent=\(isParent), isRelatedChild=\(isRelatedChild), isFutureOrCurrent=\(isFutureOrCurrent)")
                // `with` rather than a field-by-field rebuild, which silently dropped `isDeleted`.
                models[i] = models[i].with(allocatedAmount: newAmount)
                updatedCount += 1
                updatedIds.append(modelId)
            }
        }

        logDebug("BudgetAllocationRepository: Updated \(updatedCount) allocations (future+current+parent), IDs: \(updatedIds)")

        saveModels(models)

        // Notify that data has changed
        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
    }

    func updateAllRecurringAllocations(id: Int, newAmount: Int) throws {
        var models = loadModels()

        logDebug("BudgetAllocationRepository: updateAllRecurringAllocations called with id: \(id), newAmount: \(newAmount)")

        guard let allocation = models.first(where: { $0.id != nil && $0.id! == id && $0.isLive }) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for all update")
            throw BudgetAllocationError.allocationNotFound
        }

        // Get the parent allocation ID (use this allocation's ID if it's the parent)
        let parentId = allocation.parentAllocationId ?? id
        logDebug("BudgetAllocationRepository: Using parentId: \(parentId)")

        var updatedCount = 0
        var updatedIds: [Int] = []

        // Update ALL allocations in this recurring series (past, present, future)
        for i in models.indices {
            // Tombstones skipped — see the note in updateRecurringAllocationAndFuture.
            guard let modelId = models[i].id, models[i].isLive else { continue }

            if modelId == parentId || models[i].parentAllocationId == parentId {
                logDebug("BudgetAllocationRepository: Updating allocation id=\(modelId), monthDate=\(models[i].monthDate)")
                models[i] = models[i].with(allocatedAmount: newAmount)
                updatedCount += 1
                updatedIds.append(modelId)
            }
        }

        logDebug("BudgetAllocationRepository: Updated \(updatedCount) allocations (all occurrences), IDs: \(updatedIds)")

        saveModels(models)

        // Notify that data has changed
        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
    }

    // MARK: - Delete

    func deleteAllocation(id: Int) throws {
        var models = loadModels()

        logDebug("BudgetAllocationRepository: deleteAllocation called with id: \(id)")
        logDebug("BudgetAllocationRepository: Current models count: \(models.count)")
        logDebug("BudgetAllocationRepository: Model IDs: \(models.compactMap { $0.id })")

        // Explicitly unwrap optional ID for comparison
        guard let index = models.firstIndex(where: { $0.id != nil && $0.id! == id && $0.isLive }) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for deletion. Available IDs: \(models.compactMap { $0.id })")
            throw BudgetAllocationError.allocationNotFound
        }

        let allocationToDelete = models[index]

        // Deleting ONE occurrence must not stop the series.
        //
        // This used to clear the PARENT's `isRecurring`, so removing a single month silently killed
        // every future month of that series. It was standing in for a tombstone — the only way to
        // stop regeneration was to stop the series entirely. The tombstone below does exactly and
        // only what is wanted: suppress this one month. Stopping a whole series remains the job of
        // `deleteRecurringAllocationAndFuture`.
        let isSeriesOccurrence =
            allocationToDelete.isRecurring || allocationToDelete.parentAllocationId != nil

        if isSeriesOccurrence {
            models[index] = allocationToDelete.with(isDeleted: true)
            logDebug("BudgetAllocationRepository: Tombstoned occurrence \(id) (month \(allocationToDelete.monthDate))")
        } else {
            // A plain one-off is regenerated by nothing, so it can go for good.
            models.remove(at: index)
            logDebug("BudgetAllocationRepository: Removed one-off allocation \(id)")
        }
        saveModels(models)

        // Notify that data has changed
        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
        logDebug("BudgetAllocationRepository: Notification posted for allocation deletion")
    }

    func deleteRecurringAllocationAndFuture(id: Int) throws {
        var models = loadModels()

        guard let allocation = models.first(where: { $0.id != nil && $0.id! == id && $0.isLive }) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for future deletion")
            throw BudgetAllocationError.allocationNotFound
        }

        // Get the parent allocation ID
        let parentId = allocation.parentAllocationId ?? id

        // Find the current allocation's month date
        let currentMonthDate = allocation.monthDate

        // Tombstone this occurrence and every later one in the series, rather than removing them:
        // the parent stops recurring below, but a device that re-materializes from an older parent
        // state would otherwise refill exactly these months.
        var tombstoned = 0
        for (index, model) in models.enumerated() {
            guard let modelId = model.id, model.isLive else { continue }

            let isRelated = modelId == id || modelId == parentId
                || model.parentAllocationId == parentId
            let isFutureOrCurrent = modelId == id || model.monthDate >= currentMonthDate
            guard isRelated && isFutureOrCurrent else { continue }

            models[index] = model.with(isDeleted: true)
            tombstoned += 1
        }

        logDebug("BudgetAllocationRepository: Tombstoned \(tombstoned) allocations (future+current)")

        // IMPORTANT: Stop the parent from generating new future instances via lazy generation
        // Check if the parent allocation still exists (wasn't deleted because it's in the past)
        if let parentIndex = models.firstIndex(where: { $0.id != nil && $0.id! == parentId && $0.isLive }) {
            // Parent still exists (in a past month) - stop it generating anything further.
            // `with` preserves the tombstone flag; rebuilding the model field by field dropped it.
            models[parentIndex] = models[parentIndex].with(isRecurring: false)
            logDebug("BudgetAllocationRepository: Stopped recurrence on parent \(parentId)")
        }

        saveModels(models)

        // Notify that data has changed
        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
    }

    func deleteAllRecurringAllocations(id: Int) throws {
        var models = loadModels()

        guard let allocation = models.first(where: { $0.id != nil && $0.id! == id && $0.isLive }) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for all deletion")
            throw BudgetAllocationError.allocationNotFound
        }

        // Get the parent allocation ID (use this allocation's ID if it's the parent)
        let parentId = allocation.parentAllocationId ?? id

        // Tombstone every occurrence in this series (past, present, future).
        var tombstoned = 0
        for (index, model) in models.enumerated() {
            guard let modelId = model.id, model.isLive else { continue }
            guard modelId == parentId || model.parentAllocationId == parentId else { continue }
            models[index] = model.with(isDeleted: true)
            tombstoned += 1
        }

        logDebug("BudgetAllocationRepository: Tombstoned \(tombstoned) allocations (all occurrences)")

        saveModels(models)

        // Notify that data has changed
        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
    }

    // MARK: - Update Is Recurring

    func updateIsRecurring(allocationId: Int, isRecurring: Bool) throws {
        var models = loadModels()

        guard let index = models.firstIndex(where: { $0.id != nil && $0.id! == allocationId && $0.isLive }) else {
            logError("BudgetAllocationRepository: Allocation with id \(allocationId) not found for isRecurring update")
            throw BudgetAllocationError.allocationNotFound
        }

        models[index] = models[index].with(isRecurring: isRecurring)

        logDebug("BudgetAllocationRepository: Updated isRecurring to \(isRecurring) for allocation \(allocationId)")
        saveModels(models)
    }

    /// Re-parents one allocation into another's series.
    ///
    /// The single writer for `parentAllocationId` after insert — `RecurringSeriesLinker` uses it to
    /// adopt occurrences whose pointer references a row that no longer exists. Deliberately narrow:
    /// nothing else may rewrite a series link, so a careless bulk update cannot orphan a series.
    func updateParentAllocationId(id: Int, parentId: Int) throws {
        var models = loadModels()

        guard let index = models.firstIndex(where: { $0.id != nil && $0.id! == id && $0.isLive })
        else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for relink")
            throw BudgetAllocationError.allocationNotFound
        }

        models[index] = models[index].with(parentAllocationId: .some(parentId))
        saveModels(models)
    }

    // MARK: - Private Helpers

    /// EVERY stored row, including tombstones. Mutation paths use this — writing back a filtered
    /// list would erase the tombstones and undo every delete.
    private func loadModels() -> [BudgetAllocationModel] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let models = try? JSONDecoder().decode([BudgetAllocationModel].self, from: data)
        else {
            return []
        }
        return models
    }

    /// The rows that still exist as far as the rest of the app is concerned.
    private func liveModels() -> [BudgetAllocationModel] {
        loadModels().filter { $0.isLive }
    }

    private func saveModels(_ models: [BudgetAllocationModel]) {
        do {
            let data = try JSONEncoder().encode(models)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            logDebug("BudgetAllocationRepository: Saved \(models.count) allocations to UserDefaults")
        } catch {
            logError("BudgetAllocationRepository: Failed to encode models: \(error)")
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let allocationDataChanged = Notification.Name("allocationDataChanged")
}
