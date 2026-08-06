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
    updateCurrencyUI()
    updateTagTranslationUI()
    delegate?.didUpdateAppVersion(version: appVersionString)
  }

  // MARK: - Tag Translation

  /// iOS 26, not the framework's own 18.0 floor.
  ///
  /// 18 can translate, but only through a SwiftUI view held alive for the life of the app to vend a
  /// session. 26 added `TranslationSession(installedSource:target:)`, which removes that machinery
  /// and every failure mode that came with it. Below 26 the tag simply shows the name that was typed,
  /// which is the same thing it does whenever a translation is unavailable for any other reason.
  var isTagTranslationSupported: Bool {
    if #available(iOS 26.0, *) { return true }
    return false
  }

  func updateTagTranslationUI() {
    delegate?.didUpdateTagTranslation(
      isEnabled: UserDefaultsManager.isTagNameTranslationEnabled(),
      isSupported: isTagTranslationSupported)
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
