//
//  MemberPermissionsViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit
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
        case "canEditOwnTransactions": member.permissions.canEditOwnTransactions = value
        case "canDeleteOwnTransactions": member.permissions.canDeleteOwnTransactions = value
        case "canEditOwnBudgets": member.permissions.canEditOwnBudgets = value
        case "canEditOwnAllocations": member.permissions.canEditOwnAllocations = value
        default: break
        }
    }

    func savePermissions() {
        repository.updateMember(member)

        // Push updated permissions to CloudKit so the member's device picks them up
        BudgetGroupService.shared.pushGroupMemberRecord(
            member: member,
            groupId: group.id,
            zoneOwner: CKCurrentUserDefaultName
        ) { result in
            if case .failure(let error) = result {
                logError("Failed to push permission update to CloudKit: \(error.localizedDescription)")
            }
        }

        GroupNotificationService.shared.logActivity(
            action: .permissionsChanged,
            groupId: group.id,
            detail: member.name
        )

        SyncEngine.shared.performFullSync()
    }

    func removeMember() {
        repository.removeMember(id: member.id)

        // Push removal to CloudKit so the member's device discovers it
        BudgetGroupService.shared.pushGroupMemberRemoval(
            member: member,
            groupId: group.id
        ) { result in
            if case .failure(let error) = result {
                logError("Failed to push member removal to CloudKit: \(error.localizedDescription)")
            }
        }

        SyncEngine.shared.performFullSync()
    }
}
