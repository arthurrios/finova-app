//
//  GroupDetailsFlowDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

protocol GroupDetailsFlowDelegate: AnyObject {
    func dismissGroupDetails()
    func navigateToMemberPermissions(member: GroupMember, group: BudgetGroup)
    func openInviteMemberModal(group: BudgetGroup)
}
