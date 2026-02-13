//
//  BudgetGroupsFlowDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

protocol BudgetGroupsFlowDelegate: AnyObject {
    func dismissBudgetGroups()
    func navigateToGroupDetails(group: BudgetGroup)
    func openCreateGroupModal()
}
