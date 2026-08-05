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

  // MARK: - Transparent Mode
  //
  // Mirror Mode moved your personal ledger into the group, which by the app's own rule stopped
  // those rows being personal. This publishes a COPY and leaves the originals alone, so turning it
  // off simply withdraws the copies. The user-facing wording says so explicitly — someone deciding
  // whether to enable it needs to know their own records are not going anywhere.

  var isPublishingToAnyGroup: Bool {
    return !TransparencyManager.shared.publishedGroupIds().isEmpty
  }

  var publishedGroupNames: String? {
    let names = TransparencyManager.shared.publishedGroupIds()
      .compactMap { BudgetGroupService.shared.fetchGroup(byId: $0)?.name }
    return names.isEmpty ? nil : names.joined(separator: ", ")
  }

  /// Every group the user belongs to, not just the ones they own.
  ///
  /// Mirror Mode was owner-only, because moving your ledger into someone else's group would have
  /// handed them your records. Publishing a copy carries no such risk, so any member may choose to
  /// be transparent to their own group.
  var availableGroups: [BudgetGroup] {
    return BudgetGroupService.shared.fetchAllGroups().filter { !$0.isDeleted }
  }

  // MARK: - Initialization

  init() {
    configureInitialSettings()
  }

  // MARK: - Configuration

  private func configureInitialSettings() {
    updateBiometricUI()
    updateTransparencyUI()
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

  // MARK: - Public Methods

  func refreshBiometricUI() {
    logDebug("Refreshing biometric UI, current value: \(isBiometricEnabled)")
    updateBiometricUI()
  }

  func refreshAllSettings() {
    updateBiometricUI()
    updateCurrencyUI()
    updateTagTranslationUI()
    updateTransparencyUI()
    delegate?.didUpdateAppVersion(version: appVersionString)
  }

  // MARK: - Group Sharing Management

  private func updateTransparencyUI() {
    delegate?.didUpdateTransparency(
      isEnabled: isPublishingToAnyGroup,
      groupName: publishedGroupNames
    )
  }

  func toggleTransparency(_ enabled: Bool) {
    if enabled {
      let groups = availableGroups
      if groups.isEmpty {
        delegate?.didUpdateTransparency(isEnabled: false, groupName: nil)
        return
      }
      if groups.count == 1, let group = groups.first {
        selectTransparencyGroup(group)
      } else {
        delegate?.didRequestGroupSelection(groups: groups)
      }
    } else {
      // Stop publishing everywhere. No financial row is touched: the next sync withdraws the
      // projections from the group zones and the personal ledger is left exactly as it was.
      for groupId in TransparencyManager.shared.publishedGroupIds() {
        TransparencyManager.shared.setPublishing(false, forGroup: groupId)
      }
      SyncEngine.shared.pushPendingChangesNow()
      updateTransparencyUI()
    }
  }

  func selectTransparencyGroup(_ group: BudgetGroup) {
    TransparencyManager.shared.setPublishing(true, forGroup: group.id)
    SyncEngine.shared.pushPendingChangesNow()
    updateTransparencyUI()
  }

  func isPublishing(to group: BudgetGroup) -> Bool {
    TransparencyManager.shared.isPublishing(toGroup: group.id)
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
