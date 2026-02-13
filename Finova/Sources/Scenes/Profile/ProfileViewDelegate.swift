//
//  ProfileViewDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 10/02/26.
//

protocol ProfileViewDelegate: AnyObject {
    func handleDidTapBackButton()
    func didTapAvatar()
    func didTapCreditCards()
    func didTapBudgetGroups()
    func didTapSettings()
    func didTapLogout()
}
