//
//  SettingsViewModelDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 17/07/25.
//

protocol SettingsViewModelDelegate: AnyObject {
  func didUpdateBiometricUI(isEnabled: Bool, biometricType: String)
  func didRequestOpenSettings(title: String, message: String)
  func didUpdateAppVersion(version: String)
  func didUpdateCurrency(displayText: String)
  func didEncounterBiometricError(title: String, message: String)
  func didRequestReAuthentication()
  func didCompleteAccountDeletion()
  func didFailAccountDeletion(title: String, message: String)
  func shouldShowLoading(_ show: Bool, message: String?)
  func didCompleteDataRecovery(success: Bool, message: String)
  func didUpdateMirrorMode(isEnabled: Bool, groupName: String?)
  func didRequestGroupSelection(groups: [BudgetGroup])
}
