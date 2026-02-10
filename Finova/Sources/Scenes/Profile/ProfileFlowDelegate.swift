//
//  ProfileFlowDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 10/02/26.
//

protocol ProfileFlowDelegate: AnyObject {
    func dismissProfile()
    func navigateToSettings()
    func navigateToCreditCards()
    func logout()
}
