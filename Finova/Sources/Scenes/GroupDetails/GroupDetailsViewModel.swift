//
//  GroupDetailsViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import Foundation

struct MigrationCounts {
    let transactions: Int
    let budgets: Int
    let creditCards: Int
    let allocations: Int
    var total: Int { transactions + budgets + creditCards + allocations }
    var isEmpty: Bool { total == 0 }
}

final class GroupDetailsViewModel {
    private let groupService = BudgetGroupService.shared
    private let repository = BudgetGroupRepository()
    private let allocationRepository = BudgetAllocationRepository()
    private let db = DBHelper.shared

    private(set) var group: BudgetGroup
    var onGroupUpdated: (() -> Void)?
    var onError: ((String) -> Void)?

    var isOwner: Bool { group.isOwner }

    init(group: BudgetGroup) {
        self.group = group
    }

    func loadGroupDetails() {
        guard let updated = repository.fetchGroup(byId: group.id) else { return }
        group = updated
        group.members = repository.fetchMembers(forGroupId: group.id)
        onGroupUpdated?()
    }

    func renameGroup(to name: String) {
        group.name = name
        group.updatedAt = Date()
        repository.updateGroup(group)
        onGroupUpdated?()
    }

    func updateGroupCurrency(to code: String) {
        group.currency = code
        group.updatedAt = Date()
        repository.updateGroup(group)
        onGroupUpdated?()
    }

    func leaveGroup() {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else { return }
        let members = repository.fetchMembers(forGroupId: group.id)
        if let member = members.first(where: { $0.userId == userId }) {
            repository.removeMember(id: member.id)
        }
    }

    func deleteGroup() {
        guard group.isOwner else {
            onError?("sharing.error.onlyOwnerCanDelete".localized)
            return
        }
        repository.softDeleteGroup(id: group.id)
    }

    // MARK: - Migration

    func fetchMigrationCounts() -> MigrationCounts {
        let transactions = db.fetchSingleInt(
            "SELECT COUNT(*) FROM transactions WHERE shared_group_id IS NULL"
        ) ?? 0
        let budgets = db.fetchSingleInt(
            "SELECT COUNT(*) FROM budgets WHERE shared_group_id IS NULL"
        ) ?? 0
        let creditCards = db.fetchSingleInt(
            "SELECT COUNT(*) FROM credit_cards WHERE shared_group_id IS NULL"
        ) ?? 0
        let allocations = allocationRepository.fetchPersonalAllocationsCount()

        return MigrationCounts(
            transactions: transactions,
            budgets: budgets,
            creditCards: creditCards,
            allocations: allocations
        )
    }

    func migratePersonalData(completion: @escaping () -> Void) {
        let groupId = group.id

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            self.db.executeSyncUpdate(
                "UPDATE transactions SET shared_group_id = ?, sync_status = 'pending' WHERE shared_group_id IS NULL",
                textBindings: [groupId]
            )
            self.db.executeSyncUpdate(
                "UPDATE budgets SET shared_group_id = ?, sync_status = 'pending' WHERE shared_group_id IS NULL",
                textBindings: [groupId]
            )
            self.db.executeSyncUpdate(
                "UPDATE credit_cards SET shared_group_id = ?, sync_status = 'pending' WHERE shared_group_id IS NULL",
                textBindings: [groupId]
            )

            _ = self.allocationRepository.migrateAllocationsToGroup(groupId: groupId)

            TransactionRepository.invalidateCache()

            DispatchQueue.main.async {
                completion()
            }
        }
    }
}
