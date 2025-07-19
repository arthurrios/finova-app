//
//  SettingsViewModelDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 17/07/25.
//

protocol SettingsViewModelDelegate: AnyObject {
    func didUpdateBiometricUI(isEnabled: Bool, isAvailable: Bool, biometricType: String)
    func didUpdateAppVersion(version: String)
    func didEncounterBiometricError(title: String, message: String)
    func didRequestReAuthentication()
    func didCompleteAccountDeletion()
    func didFailAccountDeletion(title: String, message: String)
    func shouldShowLoading(_ show: Bool, message: String?)
}
