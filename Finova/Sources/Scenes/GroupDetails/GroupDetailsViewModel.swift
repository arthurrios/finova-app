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
        guard var updated = repository.fetchGroup(byId: group.id) else { return }
        // Clean up any accumulated duplicate members before display
        repository.deduplicateMembers(forGroupId: updated.id)
        updated.members = repository.fetchMembers(forGroupId: updated.id)

        // Refresh owner name from local user data if current user is the owner
        if updated.isOwner, let savedName = UserDefaultsManager.getUser()?.name, !savedName.isEmpty, savedName != "User" {
            if updated.ownerName != savedName {
                updated.ownerName = savedName
                repository.updateGroup(updated)
            }
            // Also update the owner member record
            if let ownerMember = updated.members.first(where: { $0.role == .owner }),
               ownerMember.name != savedName {
                var updatedMember = ownerMember
                updatedMember.name = savedName
                repository.updateMember(updatedMember)
                // Refresh members after update
                updated.members = repository.fetchMembers(forGroupId: updated.id)
            }
        }

        // Populate shared cards from database
        let cardRepo = CreditCardRepository()
        updated.sharedCards = cardRepo.fetchCardsForGroup(groupId: updated.id)

        group = updated
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
        // Clear the GroupMember push flag so it re-pushes if the user rejoins
        UserDefaults.standard.removeObject(forKey: "groupMemberPushed_\(group.id)")

        // Soft-delete the group locally so it disappears from this device
        repository.softDeleteGroup(id: group.id)

        // Disable mirror mode if linked to this group
        if MirrorModeManager.shared.isEnabled,
           MirrorModeManager.shared.linkedGroupId == group.id {
            MirrorModeManager.shared.disableMirrorMode()
        }

        NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
    }

    func deleteGroup() {
        guard group.isOwner else {
            onError?("sharing.error.onlyOwnerCanDelete".localized)
            return
        }
        // Via the service, not the repository: it also deletes the group's CloudKit zone, without
        // which the zone lingers and other devices resurrect the group.
        BudgetGroupService.shared.deleteGroup(id: group.id)

        // Disable mirror mode if linked to this group
        if MirrorModeManager.shared.isEnabled,
           MirrorModeManager.shared.linkedGroupId == group.id {
            MirrorModeManager.shared.disableMirrorMode()
        }

        NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
    }

    // MARK: - Migration

    /// SQL condition that matches records with no group or tagged with a deleted/non-existent group.
    /// These are considered "personal" and available for import into an active group.
    private static let personalDataCondition = """
        (shared_group_id IS NULL \
        OR NOT EXISTS (SELECT 1 FROM BudgetGroups WHERE id = %@.shared_group_id AND is_deleted = 0))
        """

    func fetchMigrationCounts() -> MigrationCounts {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else {
            return MigrationCounts(transactions: 0, budgets: 0, creditCards: 0, allocations: 0)
        }

        let txCond = Self.personalDataCondition.replacingOccurrences(of: "%@", with: "Transactions")
        let transactions = db.fetchSingleInt(
            "SELECT COUNT(*) FROM Transactions WHERE \(txCond) AND user_id = ?",
            textBinding: uid
        ) ?? 0

        let budgetCond = Self.personalDataCondition.replacingOccurrences(of: "%@", with: "Budgets")
        let budgets = db.fetchSingleInt(
            "SELECT COUNT(*) FROM Budgets WHERE \(budgetCond) AND user_id = ?",
            textBinding: uid
        ) ?? 0

        let cardCond = Self.personalDataCondition.replacingOccurrences(of: "%@", with: "CreditCards")
        let creditCards = db.fetchSingleInt(
            "SELECT COUNT(*) FROM CreditCards WHERE \(cardCond) AND user_id = ? AND is_deleted = 0",
            textBinding: uid
        ) ?? 0

        let allocations = allocationRepository.fetchImportableAllocationsCount()

        return MigrationCounts(
            transactions: transactions,
            budgets: budgets,
            creditCards: creditCards,
            allocations: allocations
        )
    }

    func migratePersonalData(completion: @escaping () -> Void) {
        let groupId = group.id
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else {
            completion()
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let txCond = Self.personalDataCondition.replacingOccurrences(of: "%@", with: "Transactions")
            self.db.executeSyncUpdate(
                "UPDATE Transactions SET shared_group_id = ?, sync_status = 'pending' WHERE \(txCond) AND user_id = ?",
                textBindings: [groupId, uid]
            )

            let budgetCond = Self.personalDataCondition.replacingOccurrences(of: "%@", with: "Budgets")
            self.db.executeSyncUpdate(
                "UPDATE Budgets SET shared_group_id = ?, sync_status = 'pending' WHERE \(budgetCond) AND user_id = ?",
                textBindings: [groupId, uid]
            )

            let cardCond = Self.personalDataCondition.replacingOccurrences(of: "%@", with: "CreditCards")
            self.db.executeSyncUpdate(
                "UPDATE CreditCards SET shared_group_id = ?, sync_status = 'pending' WHERE \(cardCond) AND user_id = ? AND is_deleted = 0",
                textBindings: [groupId, uid]
            )

            _ = self.allocationRepository.migrateAllocationsToGroup(groupId: groupId)

            // Copy personal balance offset to the group
            let personalOffset = UIDUserDefaultsManager.shared.getCurrentUserBalanceOffset()
            UIDUserDefaultsManager.shared.setGroupBalanceOffset(personalOffset, groupId: groupId)

            TransactionRepository.invalidateCache()

            DispatchQueue.main.async {
                completion()
            }
        }
    }
}
