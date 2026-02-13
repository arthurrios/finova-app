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

  /// Returns the display text for the current currency setting
  var currencyDisplayText: String {
    let savedCode = UserDefaultsManager.getCurrencyCode()
    if savedCode == UserDefaultsManager.currencyAutoValue {
      let deviceCurrency = AppConfig.deviceLocaleCurrencyCode
      return "\("settings.currency.auto".localized) (\(deviceCurrency))"
    } else {
      return savedCode
    }
  }

  /// List of common currencies for the picker
  static let availableCurrencies: [(code: String, name: String)] = [
    ("USD", "US Dollar"),
    ("EUR", "Euro"),
    ("GBP", "British Pound"),
    ("JPY", "Japanese Yen"),
    ("BRL", "Brazilian Real"),
    ("CAD", "Canadian Dollar"),
    ("AUD", "Australian Dollar"),
    ("CHF", "Swiss Franc"),
    ("CNY", "Chinese Yuan"),
    ("INR", "Indian Rupee"),
    ("MXN", "Mexican Peso"),
    ("KRW", "South Korean Won"),
    ("SGD", "Singapore Dollar"),
    ("HKD", "Hong Kong Dollar"),
    ("NOK", "Norwegian Krone"),
    ("SEK", "Swedish Krona"),
    ("DKK", "Danish Krone"),
    ("NZD", "New Zealand Dollar"),
    ("ZAR", "South African Rand"),
    ("RUB", "Russian Ruble"),
    ("TRY", "Turkish Lira"),
    ("PLN", "Polish Zloty"),
    ("THB", "Thai Baht"),
    ("IDR", "Indonesian Rupiah"),
    ("MYR", "Malaysian Ringgit"),
    ("PHP", "Philippine Peso"),
    ("CZK", "Czech Koruna"),
    ("ILS", "Israeli Shekel"),
    ("CLP", "Chilean Peso"),
    ("COP", "Colombian Peso"),
    ("ARS", "Argentine Peso"),
    ("PEN", "Peruvian Sol"),
    ("AED", "UAE Dirham"),
    ("SAR", "Saudi Riyal")
  ]

  // MARK: - Mirror Mode

  var isMirrorModeEnabled: Bool {
    return MirrorModeManager.shared.isEnabled
  }

  var mirrorGroupName: String? {
    guard let groupId = MirrorModeManager.shared.linkedGroupId else { return nil }
    return BudgetGroupService.shared.fetchGroup(byId: groupId)?.name
  }

  var availableGroups: [BudgetGroup] {
    return BudgetGroupService.shared.fetchAllGroups()
  }

  // MARK: - Initialization

  init() {
    configureInitialSettings()
  }

  // MARK: - Configuration

  private func configureInitialSettings() {
    updateBiometricUI()
    updateMirrorModeUI()
    delegate?.didUpdateAppVersion(version: appVersionString)
  }

  private func updateBiometricUI() {
    let isAvailable = isBiometricAvailable

    if !isAvailable {
      isBiometricEnabled = false
    }

    delegate?.didUpdateBiometricUI(
      isEnabled: isBiometricEnabled,
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

    logWarning("EMERGENCY RECOVERY: Cleared migration flags")

    let message = "Recovery flags cleared. Please restart the app."
    completion(true, message)
    delegate?.didCompleteDataRecovery(success: true, message: message)
  }

  // MARK: - Public Methods

  func refreshBiometricUI() {
    logDebug("Refreshing biometric UI, current value: \(isBiometricEnabled)")
    updateBiometricUI()
  }

  func refreshAllSettings() {
    updateBiometricUI()
    updateCurrencyUI()
    updateMirrorModeUI()
    delegate?.didUpdateAppVersion(version: appVersionString)
  }

  // MARK: - Mirror Mode Management

  private func updateMirrorModeUI() {
    delegate?.didUpdateMirrorMode(
      isEnabled: isMirrorModeEnabled,
      groupName: mirrorGroupName
    )
  }

  func toggleMirrorMode(_ enabled: Bool) {
    if enabled {
      let groups = availableGroups
      if groups.isEmpty {
        delegate?.didUpdateMirrorMode(isEnabled: false, groupName: nil)
        return
      }
      if groups.count == 1, let group = groups.first {
        selectMirrorGroup(group)
      } else {
        delegate?.didRequestGroupSelection(groups: groups)
      }
    } else {
      MirrorModeManager.shared.disableMirrorMode()
      updateMirrorModeUI()
    }
  }

  func selectMirrorGroup(_ group: BudgetGroup) {
    MirrorModeManager.shared.enableMirrorMode(groupId: group.id)
    updateMirrorModeUI()
  }

  // MARK: - Currency Management

  private func updateCurrencyUI() {
    let displayText = currencyDisplayText
    logDebug("updateCurrencyUI - displayText: \(displayText), delegate exists: \(delegate != nil)")
    delegate?.didUpdateCurrency(displayText: displayText)
  }

  /// Sets the currency to auto (device locale)
  func setCurrencyToAuto() {
    let newCode = UserDefaultsManager.currencyAutoValue
    logDebug("setCurrencyToAuto called")
    logDebug("Before save - stored code: \(UserDefaultsManager.getCurrencyCode())")
    UserDefaultsManager.setCurrencyCode(newCode)
    logDebug("After save - stored code: \(UserDefaultsManager.getCurrencyCode())")
    // Update UI immediately on the same run loop
    updateCurrencyUI()
    notifyCurrencyChange()
  }

  /// Sets a specific currency code
  func setCurrency(code: String) {
    logDebug("setCurrency called with code: \(code)")
    logDebug("Before save - stored code: \(UserDefaultsManager.getCurrencyCode())")
    UserDefaultsManager.setCurrencyCode(code)
    logDebug("After save - stored code: \(UserDefaultsManager.getCurrencyCode())")
    // Update UI immediately on the same run loop
    updateCurrencyUI()
    notifyCurrencyChange()
  }

  private func notifyCurrencyChange() {
    logDebug("Posting currencyDidChange notification")
    NotificationCenter.default.post(name: .currencyDidChange, object: nil)
  }

  /// Returns the currently selected currency code (or "auto")
  func getCurrentCurrencyCode() -> String {
    return UserDefaultsManager.getCurrencyCode()
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
    if !isBiometricAvailable {
      delegate?.didRequestOpenSettings(
        title: biometricTypeString,
        message: String(
          format: "settings.biometric.notEnrolled.message".localized,
          biometricTypeString
        )
      )
      updateBiometricUI()
      return
    }

    FaceIDManager.shared.authenticateWithBiometrics(
      reason: "settings.biometric.enable.reason".localized
    ) { [weak self] success, error in
      DispatchQueue.main.async {
        if success {
          self?.isBiometricEnabled = true
          logInfo("Biometric authentication enabled globally")
          self?.updateBiometricUI()
        } else {
          if let error = error {
            self?.delegate?.didEncounterBiometricError(
              title: "settings.biometric.error.title",
              message: FaceIDManager.shared.getFriendlyErrorMessage(for: error))
          }
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
    if let uid = UIDUserDefaultsManager.shared.currentUserUID {
      DBHelper.shared.deleteAllTransactions(forUser: uid)
      DBHelper.shared.deleteAllBudgets(forUser: uid)
      ProfileImageManager.shared.removeProfileImage()
    }

    // Clear current user's UserDefaults
    UserDefaultsManager.removeUser()
    UserDefaultsManager.clearAllSettings()

    logInfo("Current user data cleared for account deletion")
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
    if let uid = UIDUserDefaultsManager.shared.currentUserUID {
      DBHelper.shared.deleteAllTransactions(forUser: uid)
      DBHelper.shared.deleteAllBudgets(forUser: uid)
      ProfileImageManager.shared.removeProfileImage()
    }

    // Clear current user's UserDefaults
    UserDefaultsManager.removeUser()
    UserDefaultsManager.clearAllSettings()

    logInfo("Current user data cleared (preserving other users' data)")
  }
}
