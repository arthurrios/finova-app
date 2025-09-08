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
  private let toastDismissedForVersionKey = "toastDismissedForVersion"

  // MARK: - Testing Properties
  #if DEBUG
    private var mockLatestVersion: String?
    private var forceShowToast: Bool = false
  #endif

  private init() {
    self.currentVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    print("📱 Current app version: \(currentVersion)")
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
      print("📱 No newer version available")
      return false
    }

    // Check if user dismissed toast for current version
    let dismissedForCurrentVersion = UserDefaults.standard.bool(
      forKey: "\(toastDismissedForVersionKey)_\(currentVersion)")

    if dismissedForCurrentVersion {
      // Check if 24 hours have passed since last dismissal
      if let lastDismissedDate = UserDefaults.standard.object(forKey: lastToastDismissedKey)
        as? Date
      {
        let timeSinceDismissal = Date().timeIntervalSince(lastDismissedDate)
        let twentyFourHours: TimeInterval = 24 * 60 * 60  // 24 hours in seconds

        if timeSinceDismissal < twentyFourHours {
          let hoursRemaining = (twentyFourHours - timeSinceDismissal) / 3600
          print(
            "📱 Toast dismissed recently. Remaining time: \(String(format: "%.1f", hoursRemaining)) hours"
          )
          return false
        } else {
          print("📱 24 hours have passed since dismissal. Showing reminder toast")
        }
      } else {
        print("📱 Toast was dismissed but no date recorded. Showing toast")
      }
    }

    print(
      "📱 Version check: current=\(currentVersion), latest=\(latestVersion), shouldShow=true"
    )

    #if DEBUG
      print("🧪 Mock version test: Showing toast with version \(latestVersion)")
    #endif

    return true
  }

  /// Mark toast as dismissed for current version
  func markToastAsDismissed() {
    UserDefaults.standard.set(true, forKey: "\(toastDismissedForVersionKey)_\(currentVersion)")
    UserDefaults.standard.set(Date(), forKey: lastToastDismissedKey)
    print("📱 Update toast dismissed for version \(currentVersion)")
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

  /// Check if a newer version is available
  private func isNewerVersionAvailable(latestVersion: String, currentVersion: String) -> Bool {
    return latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending
  }

  /// Open App Store to update page
  func openAppStore() {
    guard let appStoreURL = URL(string: "https://apps.apple.com/app/id6748543666") else {
      print("❌ Invalid App Store URL")
      return
    }

    if UIApplication.shared.canOpenURL(appStoreURL) {
      UIApplication.shared.open(appStoreURL, options: [:]) { success in
        print("📱 App Store opened: \(success)")
      }
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

    /// Simulate 24 hours passing for testing
    func simulate24HoursPassed() {
      let pastDate = Date().addingTimeInterval(-25 * 60 * 60)  // 25 hours ago
      UserDefaults.standard.set(pastDate, forKey: lastToastDismissedKey)
      print("🧪 Simulated 24+ hours passing since last dismissal")
    }
  #endif
}
