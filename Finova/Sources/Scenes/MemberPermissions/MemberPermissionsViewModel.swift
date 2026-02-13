//
//  MemberPermissionsViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import Foundation

final class MemberPermissionsViewModel {
    private(set) var member: GroupMember
    private let group: BudgetGroup
    private let repository = BudgetGroupRepository()

    var onPermissionsUpdated: (() -> Void)?
    var onError: ((String) -> Void)?

    init(member: GroupMember, group: BudgetGroup) {
        self.member = member
        self.group = group
    }

    func updatePermission(key: String, value: Bool) {
        switch key {
        case "canCreateTransactions": member.permissions.canCreateTransactions = value
        case "canEditTransactions": member.permissions.canEditTransactions = value
        case "canDeleteTransactions": member.permissions.canDeleteTransactions = value
        case "canEditBudgets": member.permissions.canEditBudgets = value
        case "canEditAllocations": member.permissions.canEditAllocations = value
        case "canViewCreditCards": member.permissions.canViewCreditCards = value
        case "canManageCreditCards": member.permissions.canManageCreditCards = value
        case "canInviteMembers": member.permissions.canInviteMembers = value
        default: break
        }
    }

    func savePermissions() {
        repository.updateMember(member)
        SyncEngine.shared.performFullSync()
    }

    func removeMember() {
        repository.removeMember(id: member.id)
        SyncEngine.shared.performFullSync()
    }
}
