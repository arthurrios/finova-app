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
    func didTapNotifications()
    func didTapCurrency()
    func didTapSyncSettings()
    func didToggleMirrorMode(_ isEnabled: Bool)
    func didTapMirrorGroupPicker()
}
