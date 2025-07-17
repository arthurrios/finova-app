//
//  SettingsViewDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 17/07/25.
//

protocol SettingsViewDelegate: AnyObject {
    func handleDidTapBackButton()
    func didToggleBiometric(_ isEnabled: Bool)
    func didTapDeleteAccount()
}
