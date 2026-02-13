//
//  BudgetGroupsViewDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

protocol BudgetGroupsViewDelegate: AnyObject {
    func handleDidTapBackButton()
    func didTapCreateGroup()
    func didSelectGroup(_ group: BudgetGroup)
}
