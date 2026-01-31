//
//  UpdateToastManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on [Current Date]
//

import Foundation
import UIKit

protocol UpdateToastManagerDelegate: AnyObject {
  func updateToastManager(_ manager: UpdateToastManager, shouldShowToast: Bool)
  func updateToastManager(_ manager: UpdateToastManager, didDismissToast: Bool)
}

final class UpdateToastManager {
  static let shared = UpdateToastManager()

  weak var delegate: UpdateToastManagerDelegate?

  // MARK: - Properties
  private let currentVersion: String
  private let latestVersionKey = "latestAppVersion"
  private let lastToastDismissedKey = "lastToastDismissed"
  private let lastToastShownKey = "lastToastShown"
  private let toastDismissedForVersionKey = "toastDismissedForVersion"

  // MARK: - Testing Properties
  #if DEBUG
    private var mockLatestVersion: String?
    private var forceShowToast: Bool = false
  #endif

  private init() {
    self.currentVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
  }

  // MARK: - Public Methods

  /// Check if update toast should be shown
  func shouldShowUpdateToast() -> Bool {
    #if DEBUG
      if forceShowToast {
        print("🧪 Force showing toast for testing")
        return true
      }
    #endif

    // Check if there's a newer version available
    let latestVersion = getLatestVersion()
    let hasNewerVersion = isNewerVersionAvailable(
      latestVersion: latestVersion, currentVersion: currentVersion)

    if !hasNewerVersion {
      return false
    }

    // Check if user dismissed toast for current version
    let dismissedForCurrentVersion = UserDefaults.standard.bool(
      forKey: "\(toastDismissedForVersionKey)_\(currentVersion)")

    if dismissedForCurrentVersion {
      // Check if 6 hours have passed since last dismissal
      if let lastDismissedDate = UserDefaults.standard.object(forKey: lastToastDismissedKey)
        as? Date
      {
        let timeSinceDismissal = Date().timeIntervalSince(lastDismissedDate)
        let sixHours: TimeInterval = 6 * 60 * 60  // 6 hours in seconds

        if timeSinceDismissal < sixHours {
          return false
        }
      }
    } else {
      // Toast was not dismissed, check if it was shown recently
      if let lastShownDate = UserDefaults.standard.object(forKey: lastToastShownKey) as? Date {
        let timeSinceShown = Date().timeIntervalSince(lastShownDate)
        let thirtyMinutes: TimeInterval = 30 * 60  // 30 minutes in seconds

        if timeSinceShown < thirtyMinutes {
          return false
        }
      }
    }

    #if DEBUG
      print("🧪 Mock version test: Showing toast with version \(latestVersion)")
    #endif

    return true
  }

  /// Mark toast as dismissed for current version
  func markToastAsDismissed() {
    UserDefaults.standard.set(true, forKey: "\(toastDismissedForVersionKey)_\(currentVersion)")
    UserDefaults.standard.set(Date(), forKey: lastToastDismissedKey)
  }

  /// Mark toast as shown (for cooldown tracking)
  func markToastAsShown() {
    UserDefaults.standard.set(Date(), forKey: lastToastShownKey)
  }

  /// Get the latest version from App Store or cache
  private func getLatestVersion() -> String {
    #if DEBUG
      if let mockVersion = mockLatestVersion {
        return mockVersion
      }
    #endif

    // Return cached version or current version as fallback
    return UserDefaults.standard.string(forKey: latestVersionKey) ?? currentVersion
  }

  /// Check for updates from App Store
  func checkForUpdatesFromAppStore(completion: @escaping (Bool) -> Void) {
    VersionService.shared.checkForUpdates { [weak self] latestVersion in
      guard let self = self, let latestVersion = latestVersion else {
        completion(false)
        return
      }

      // Update the cached version
      UserDefaults.standard.set(latestVersion, forKey: self.latestVersionKey)

      // Check if this is a newer version
      let hasNewerVersion = self.isNewerVersionAvailable(
        latestVersion: latestVersion, currentVersion: self.currentVersion)
      completion(hasNewerVersion)
    }
  }

  /// Check if a newer version is available
  private func isNewerVersionAvailable(latestVersion: String, currentVersion: String) -> Bool {
    return latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending
  }

  /// Open App Store to update page
  func openAppStore() {
    guard let appStoreURL = URL(string: "https://apps.apple.com/app/id6748543666") else {
      logError("Invalid App Store URL")
      return
    }

    if UIApplication.shared.canOpenURL(appStoreURL) {
      UIApplication.shared.open(appStoreURL, options: [:], completionHandler: nil)
    }
  }

  // MARK: - Testing Methods (DEBUG only)

  #if DEBUG
    /// Force show toast for testing
    func forceShowToastForTesting() {
      forceShowToast = true
      delegate?.updateToastManager(self, shouldShowToast: true)
    }

    /// Set mock latest version for testing
    func setMockLatestVersion(_ version: String) {
      mockLatestVersion = version
      UserDefaults.standard.set(version, forKey: latestVersionKey)
      print("🧪 Mock version set to: \(version)")
    }

    /// Reset testing state
    func resetTestingState() {
      forceShowToast = false
      mockLatestVersion = nil
      UserDefaults.standard.removeObject(forKey: latestVersionKey)
      UserDefaults.standard.removeObject(forKey: lastToastDismissedKey)
      UserDefaults.standard.removeObject(forKey: lastToastShownKey)

      // Clear all version-specific dismiss flags
      let defaults = UserDefaults.standard
      let keys = defaults.dictionaryRepresentation().keys
      for key in keys {
        if key.hasPrefix(toastDismissedForVersionKey) {
          defaults.removeObject(forKey: key)
        }
      }
      print("🧪 Testing state reset")
    }

    /// Simulate 6 hours passing for testing
    func simulate6HoursPassed() {
      let pastDate = Date().addingTimeInterval(-7 * 60 * 60)  // 7 hours ago
      UserDefaults.standard.set(pastDate, forKey: lastToastDismissedKey)
      print("🧪 Simulated 6+ hours passing since last dismissal")
    }
  #endif
}
