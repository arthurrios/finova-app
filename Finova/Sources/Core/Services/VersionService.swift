//
//  VersionService.swift
//  FinanceApp
//
//  Created by Arthur Rios on [Current Date]
//

import Foundation

final class VersionService {
  static let shared = VersionService()

  private let appStoreURL = "https://itunes.apple.com/lookup?bundleId=com.arthurrios.Finova"
  private let latestVersionKey = "latestAppVersion"
  private let lastVersionCheckKey = "lastVersionCheck"

  private init() {}

  /// Check for app updates from App Store
  func checkForUpdates(completion: @escaping (String?) -> Void) {
    // Check if we should skip this check (rate limiting)
    if shouldSkipVersionCheck() {
      completion(getCachedVersion())
      return
    }

    guard let url = URL(string: appStoreURL) else {
      completion(getCachedVersion())
      return
    }

    let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
      guard let self = self else { return }

      if let error = error {
        print("❌ Version check failed: \(error.localizedDescription)")
        completion(self.getCachedVersion())
        return
      }

      guard let data = data else {
        completion(self.getCachedVersion())
        return
      }

      do {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let results = json["results"] as? [[String: Any]],
          let firstResult = results.first,
          let latestVersion = firstResult["version"] as? String
        {

          // Cache the latest version
          UserDefaults.standard.set(latestVersion, forKey: self.latestVersionKey)
          UserDefaults.standard.set(Date(), forKey: self.lastVersionCheckKey)

          print("📱 Latest version found: \(latestVersion)")
          completion(latestVersion)
        } else {
          completion(self.getCachedVersion())
        }
      } catch {
        print("❌ Failed to parse version response: \(error)")
        completion(self.getCachedVersion())
      }
    }

    task.resume()
  }

  /// Get cached version
  private func getCachedVersion() -> String? {
    return UserDefaults.standard.string(forKey: latestVersionKey)
  }

  /// Check if we should skip version check (rate limiting - max once per day)
  private func shouldSkipVersionCheck() -> Bool {
    guard let lastCheck = UserDefaults.standard.object(forKey: lastVersionCheckKey) as? Date else {
      return false
    }

    let oneDay: TimeInterval = 24 * 60 * 60
    return Date().timeIntervalSince(lastCheck) < oneDay
  }
}
