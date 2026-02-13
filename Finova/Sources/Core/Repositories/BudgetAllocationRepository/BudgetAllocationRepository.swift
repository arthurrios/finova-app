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
    func migrateAllocationsToGroup(groupId: String) -> Int
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
        // Load from UserDefaults for now (can be migrated to DB later)
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let models = try? JSONDecoder().decode([BudgetAllocationModel].self, from: data)
        else {
            return []
        }

        return models.map { BudgetAllocation(from: $0) }
    }

    // MARK: - Insert

    func insertAllocation(_ model: BudgetAllocationModel) throws -> Int {
        var models = loadModels()

        // Check for duplicate (same category and month)
        if models.contains(where: {
            $0.categoryKey == model.categoryKey && $0.monthDate == model.monthDate
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
            parentAllocationId: model.parentAllocationId,
            sharedGroupId: model.sharedGroupId
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

        guard let index = models.firstIndex(where: { $0.id != nil && $0.id! == model.id }) else {
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

        guard let allocation = models.first(where: { $0.id != nil && $0.id! == id }) else {
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
            guard let modelId = models[i].id else { continue }

            // Check if this is the allocation being updated
            let isCurrentAllocation = modelId == id

            // Check if this is the parent (must update parent so future instances get new amount)
            let isParent = modelId == parentId

            // Check if this is a child allocation in the future
            let isRelatedChild = models[i].parentAllocationId == parentId
            let isFutureOrCurrent = models[i].monthDate >= currentMonthDate

            if isCurrentAllocation || isParent || (isRelatedChild && isFutureOrCurrent) {
                logDebug("BudgetAllocationRepository: Updating allocation id=\(modelId), monthDate=\(models[i].monthDate), reason: isCurrentAllocation=\(isCurrentAllocation), isParent=\(isParent), isRelatedChild=\(isRelatedChild), isFutureOrCurrent=\(isFutureOrCurrent)")
                models[i] = BudgetAllocationModel(
                    id: models[i].id,
                    monthDate: models[i].monthDate,
                    categoryKey: models[i].categoryKey,
                    allocatedAmount: newAmount,
                    isRecurring: models[i].isRecurring,
                    parentAllocationId: models[i].parentAllocationId,
                    sharedGroupId: models[i].sharedGroupId
                )
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

        guard let allocation = models.first(where: { $0.id != nil && $0.id! == id }) else {
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
            guard let modelId = models[i].id else { continue }

            if modelId == parentId || models[i].parentAllocationId == parentId {
                logDebug("BudgetAllocationRepository: Updating allocation id=\(modelId), monthDate=\(models[i].monthDate)")
                models[i] = BudgetAllocationModel(
                    id: models[i].id,
                    monthDate: models[i].monthDate,
                    categoryKey: models[i].categoryKey,
                    allocatedAmount: newAmount,
                    isRecurring: models[i].isRecurring,
                    parentAllocationId: models[i].parentAllocationId,
                    sharedGroupId: models[i].sharedGroupId
                )
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
        guard let index = models.firstIndex(where: { $0.id != nil && $0.id! == id }) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for deletion. Available IDs: \(models.compactMap { $0.id })")
            throw BudgetAllocationError.allocationNotFound
        }

        let allocationToDelete = models[index]

        // If this is a recurring child instance, stop the parent from regenerating it
        // by setting isRecurring=false on the parent
        if let parentId = allocationToDelete.parentAllocationId {
            if let parentIndex = models.firstIndex(where: { $0.id != nil && $0.id! == parentId }) {
                let parentModel = models[parentIndex]
                models[parentIndex] = BudgetAllocationModel(
                    id: parentModel.id,
                    monthDate: parentModel.monthDate,
                    categoryKey: parentModel.categoryKey,
                    allocatedAmount: parentModel.allocatedAmount,
                    isRecurring: false,
                    parentAllocationId: parentModel.parentAllocationId,
                    sharedGroupId: parentModel.sharedGroupId
                )
                logDebug("BudgetAllocationRepository: Set isRecurring=false on parent \(parentId) to prevent lazy regeneration")
            }
        }
        // If this is a parent allocation being deleted, also check if it's recurring
        // and update to prevent any orphan-related issues
        else if allocationToDelete.isRecurring {
            // Parent being deleted - no need to modify isRecurring as it's being removed
            logDebug("BudgetAllocationRepository: Deleting recurring parent allocation \(id)")
        }

        logDebug("BudgetAllocationRepository: Found allocation at index \(index), removing...")
        models.remove(at: index)
        logDebug("BudgetAllocationRepository: Models count after removal: \(models.count)")
        saveModels(models)

        // Notify that data has changed
        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
        logDebug("BudgetAllocationRepository: Notification posted for allocation deletion")
    }

    func deleteRecurringAllocationAndFuture(id: Int) throws {
        var models = loadModels()

        guard let allocation = models.first(where: { $0.id != nil && $0.id! == id }) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for future deletion")
            throw BudgetAllocationError.allocationNotFound
        }

        // Get the parent allocation ID
        let parentId = allocation.parentAllocationId ?? id

        // Find the current allocation's month date
        let currentMonthDate = allocation.monthDate

        let countBefore = models.count

        // Remove all allocations with the same parent that are >= current month
        // Also remove the current allocation itself
        models.removeAll { model in
            guard let modelId = model.id else { return false }

            // Check if this is the allocation being deleted
            if modelId == id {
                return true
            }

            // Check if related to the recurring series and in future/current month
            let isRelated = modelId == parentId || model.parentAllocationId == parentId
            let isFutureOrCurrent = model.monthDate >= currentMonthDate
            return isRelated && isFutureOrCurrent
        }

        let countAfter = models.count
        logDebug("BudgetAllocationRepository: Deleted \(countBefore - countAfter) allocations (future+current)")

        // IMPORTANT: Stop the parent from generating new future instances via lazy generation
        // Check if the parent allocation still exists (wasn't deleted because it's in the past)
        if let parentIndex = models.firstIndex(where: { $0.id != nil && $0.id! == parentId }) {
            // Parent still exists (in a past month) - set isRecurring to false to stop future generation
            let parentModel = models[parentIndex]
            models[parentIndex] = BudgetAllocationModel(
                id: parentModel.id,
                monthDate: parentModel.monthDate,
                categoryKey: parentModel.categoryKey,
                allocatedAmount: parentModel.allocatedAmount,
                isRecurring: false,
                parentAllocationId: parentModel.parentAllocationId,
                sharedGroupId: parentModel.sharedGroupId
            )
            logDebug("BudgetAllocationRepository: Set isRecurring=false on parent \(parentId) to prevent lazy regeneration")
        }

        saveModels(models)

        // Notify that data has changed
        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
    }

    func deleteAllRecurringAllocations(id: Int) throws {
        var models = loadModels()

        guard let allocation = models.first(where: { $0.id != nil && $0.id! == id }) else {
            logError("BudgetAllocationRepository: Allocation with id \(id) not found for all deletion")
            throw BudgetAllocationError.allocationNotFound
        }

        // Get the parent allocation ID (use this allocation's ID if it's the parent)
        let parentId = allocation.parentAllocationId ?? id

        let countBefore = models.count

        // Remove ALL allocations in this recurring series (past, present, future)
        models.removeAll { model in
            guard let modelId = model.id else { return false }
            return modelId == parentId || model.parentAllocationId == parentId
        }

        let countAfter = models.count
        logDebug("BudgetAllocationRepository: Deleted \(countBefore - countAfter) allocations (all occurrences)")

        saveModels(models)

        // Notify that data has changed
        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
    }

    // MARK: - Update Is Recurring

    func updateIsRecurring(allocationId: Int, isRecurring: Bool) throws {
        var models = loadModels()

        guard let index = models.firstIndex(where: { $0.id != nil && $0.id! == allocationId }) else {
            logError("BudgetAllocationRepository: Allocation with id \(allocationId) not found for isRecurring update")
            throw BudgetAllocationError.allocationNotFound
        }

        let existingModel = models[index]
        models[index] = BudgetAllocationModel(
            id: existingModel.id,
            monthDate: existingModel.monthDate,
            categoryKey: existingModel.categoryKey,
            allocatedAmount: existingModel.allocatedAmount,
            isRecurring: isRecurring,
            parentAllocationId: existingModel.parentAllocationId,
            sharedGroupId: existingModel.sharedGroupId
        )

        logDebug("BudgetAllocationRepository: Updated isRecurring to \(isRecurring) for allocation \(allocationId)")
        saveModels(models)
    }

    // MARK: - Migration

    func fetchPersonalAllocationsCount() -> Int {
        let models = loadModels()
        return models.filter { $0.sharedGroupId == nil }.count
    }

    func migrateAllocationsToGroup(groupId: String) -> Int {
        var models = loadModels()
        var migratedCount = 0

        for i in models.indices {
            guard models[i].sharedGroupId == nil else { continue }
            models[i] = BudgetAllocationModel(
                id: models[i].id,
                monthDate: models[i].monthDate,
                categoryKey: models[i].categoryKey,
                allocatedAmount: models[i].allocatedAmount,
                isRecurring: models[i].isRecurring,
                parentAllocationId: models[i].parentAllocationId,
                sharedGroupId: groupId
            )
            migratedCount += 1
        }

        if migratedCount > 0 {
            saveModels(models)
            logDebug("BudgetAllocationRepository: Migrated \(migratedCount) allocations to group \(groupId)")
        }

        return migratedCount
    }

    // MARK: - Private Helpers

    private func loadModels() -> [BudgetAllocationModel] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let models = try? JSONDecoder().decode([BudgetAllocationModel].self, from: data)
        else {
            return []
        }
        return models
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
