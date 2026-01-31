//
//  SettingsViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 17/07/25.
//

import FirebaseAuth
import Foundation
import LocalAuthentication
import UIKit

final class SettingsViewModel {
  weak var delegate: SettingsViewModelDelegate?

  // MARK: - Properties

  var isBiometricEnabled: Bool {
    get { UserDefaultsManager.getBiometricEnabled() }
    set { UserDefaultsManager.setBiometricEnabled(newValue) }
  }

  var biometricTypeString: String {
    return FaceIDManager.shared.biometricTypeString
  }

  var isBiometricAvailable: Bool {
    return FaceIDManager.shared.isFaceIDAvailable
  }

  var appVersionString: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    let _ = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    return "\(version)"
  }

  // MARK: - Initialization

  init() {
    configureInitialSettings()
  }

  // MARK: - Configuration

  private func configureInitialSettings() {
    updateBiometricUI()
    delegate?.didUpdateAppVersion(version: appVersionString)
  }

  private func updateBiometricUI() {
    let isAvailable = isBiometricAvailable

    if !isAvailable {
      isBiometricEnabled = false
    }

    delegate?.didUpdateBiometricUI(
      isEnabled: isBiometricEnabled,
      isAvailable: isAvailable,
      biometricType: biometricTypeString
    )
  }

  // MARK: - Emergency Data Recovery

  func attemptEmergencyDataRecovery(completion: @escaping (Bool, String) -> Void) {
    guard let currentUser = AuthenticationManager.shared.currentUser else {
      completion(false, "No authenticated user found")
      return
    }

    logWarning("EMERGENCY RECOVERY: Starting manual data recovery for \(currentUser.uid)")

    // Clear migration flags to force re-attempt
    let migrationKey = "data_migrated_to_firebase_\(currentUser.uid)"
    let emergencyKey = "emergency_recovery_attempted_\(currentUser.uid)"
    let globalMigrationKey = "global_local_data_migrated_to_firebase"

    UserDefaults.standard.removeObject(forKey: migrationKey)
    UserDefaults.standard.removeObject(forKey: emergencyKey)
    UserDefaults.standard.removeObject(forKey: globalMigrationKey)

    // Also clear ownership restrictions
    UserDefaults.standard.removeObject(forKey: "data_owner_uid")
    UserDefaults.standard.removeObject(forKey: "data_owner_email")
    UserDefaults.standard.removeObject(forKey: "device_users")

    logWarning("EMERGENCY RECOVERY: Cleared migration flags, attempting recovery...")

    // Force migration attempt
    SecureLocalDataManager.shared.migrateOldDataToUser(
      firebaseUID: currentUser.uid,
      userEmail: currentUser.email ?? ""
    ) { [weak self] success in
      DispatchQueue.main.async {
        if success {
          logInfo("EMERGENCY RECOVERY: Data recovery successful!")
          let message = "Data recovery successful! Please restart the app to see your data."
          completion(true, message)
          self?.delegate?.didCompleteDataRecovery(success: true, message: message)
        } else {
          logError("EMERGENCY RECOVERY: Data recovery failed")
          let message = "Data recovery failed. Please contact support for assistance."
          completion(false, message)
          self?.delegate?.didCompleteDataRecovery(success: false, message: message)
        }
      }
    }
  }

  // MARK: - Public Methods

  func refreshBiometricUI() {
    logDebug("Refreshing biometric UI, current value: \(isBiometricEnabled)")
    updateBiometricUI()
  }

  func refreshAllSettings() {
    updateBiometricUI()
    delegate?.didUpdateAppVersion(version: appVersionString)
  }

  // MARK: - Biometric Management

  func toggleBiometric(_ isEnabled: Bool) {
    if isEnabled {
      enableBiometric()
    } else {
      disableBiometric()
    }
  }

  private func enableBiometric() {
    FaceIDManager.shared.authenticateWithBiometrics(
      reason: "settings.biometric.enable.reason".localized
    ) { [weak self] success, error in
      DispatchQueue.main.async {
        if success {
          self?.isBiometricEnabled = true
          logInfo("Biometric authentication enabled globally")
          // Update UI to reflect the change
          self?.updateBiometricUI()
        } else {
          if let error = error {
            self?.delegate?.didEncounterBiometricError(
              title: "settings.biometric.error.title",
              message: FaceIDManager.shared.getFriendlyErrorMessage(for: error))
          }
          // Reset switch to off position if authentication failed
          self?.updateBiometricUI()
        }
      }
    }
  }

  private func disableBiometric() {
    isBiometricEnabled = false
    logInfo("Biometric authentication disabled globally")
    updateBiometricUI()
  }

  // MARK: - Account Deletion

  func deleteAccount() {
    delegate?.shouldShowLoading(true, message: "settings.delete.account.processing".localized)

    // Step 1: Clear only current user's data (preserves other users' data)
    clearCurrentUserDataForDeletion()

    // Step 2: Delete Firebase user
    Auth.auth().currentUser?.delete { [weak self] error in
      DispatchQueue.main.async {
        self?.delegate?.shouldShowLoading(false, message: nil)

        if let error = error {
          self?.handleAccountDeletionError(error)
        } else {
          self?.handleSuccessfulAccountDeletion()
        }
      }
    }
  }

  private func clearCurrentUserDataForDeletion() {
    // Clear only current user's data - preserves other users' data on device
    SecureLocalDataManager.shared.clearUserData()  // Current user only

    // Clear current user's UserDefaults
    UserDefaultsManager.removeUser()
    UserDefaultsManager.clearAllSettings()

    // Clear current user's app-specific data
    clearCurrentUserAppSpecificData()

    logInfo("Current user data cleared for account deletion")
  }

  private func clearCurrentUserAppSpecificData() {
    // Clear only current user's profile image (if stored per-user)
    // Do NOT call clearAllGlobalProfileImages() as it affects all users

    // Reset migration state for current user only
    DataMigrationManager.shared.resetCurrentUserMigrationState()

    // Clear current user's data ownership only
    SecureLocalDataManager.shared.clearCurrentUserDataOwnership()
  }

  private func handleAccountDeletionError(_ error: Error) {
    // Handle re-authentication required error
    if (error as NSError).code == AuthErrorCode.requiresRecentLogin.rawValue {
      // IMPORTANT: Don't clear data here - other users might lose their data
      delegate?.didRequestReAuthentication()
    } else {
      delegate?.didFailAccountDeletion(
        title: "settings.delete.account.error.title".localized,
        message: error.localizedDescription
      )
    }
  }

  private func handleSuccessfulAccountDeletion() {
    // Sign out from authentication systems
    AuthenticationManager.shared.signOut()
    SecureLocalDataManager.shared.signOut()

    delegate?.didCompleteAccountDeletion()
  }

  // MARK: - Re-authentication Flow

  func handleReAuthenticationSignOut() {
    // Only clear current user's data, not all users' data
    clearCurrentUserLocalData()
    AuthenticationManager.shared.signOut()
  }

  private func clearCurrentUserLocalData() {
    // Clear only the current user's data - preserve other users' data
    SecureLocalDataManager.shared.clearUserData()  // This clears only current user

    // Clear current user's UserDefaults
    UserDefaultsManager.removeUser()
    UserDefaultsManager.clearAllSettings()

    // Clear only current user's app-specific data (no global cleanup)
    clearCurrentUserAppSpecificData()

    logInfo("Current user data cleared (preserving other users' data)")
  }
}
