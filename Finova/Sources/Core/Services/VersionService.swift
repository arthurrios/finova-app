//
//  VersionService.swift
//  FinanceApp
//
//  Created by Arthur Rios on [Current Date]
//

import Foundation

final class VersionService {
  static let shared = VersionService()

  private let appStoreURL = "https://itunes.apple.com/lookup?bundleId=com.arthurrios.FinanceApp"
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

    print("📱 Checking App Store for updates with URL: \(appStoreURL)")

    let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
      guard let self = self else { return }

      if let error = error {
        print("❌ Version check failed: \(error.localizedDescription)")
        completion(self.getCachedVersion())
        return
      }

      guard let data = data else {
        print("❌ No data received from App Store API")
        completion(self.getCachedVersion())
        return
      }

      do {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
          print("📱 App Store API response: \(json)")

          if let results = json["results"] as? [[String: Any]] {
            print("📱 Found \(results.count) results from App Store")

            if let firstResult = results.first {
              print("📱 First result: \(firstResult)")

              if let latestVersion = firstResult["version"] as? String {
                // Cache the latest version
                UserDefaults.standard.set(latestVersion, forKey: self.latestVersionKey)
                UserDefaults.standard.set(Date(), forKey: self.lastVersionCheckKey)

                print("📱 Latest version found: \(latestVersion)")
                completion(latestVersion)
              } else {
                print("❌ No version field found in App Store response")
                completion(self.getCachedVersion())
              }
            } else {
              print("📱 App not found in App Store (likely not published yet)")
              print(
                "📱 Using current version as fallback: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")"
              )
              // For unpublished apps, use current version as "latest" to prevent update prompts
              let currentVersion =
                Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
              UserDefaults.standard.set(currentVersion, forKey: self.latestVersionKey)
              UserDefaults.standard.set(Date(), forKey: self.lastVersionCheckKey)
              completion(currentVersion)
            }
          } else {
            print("❌ No results array found in App Store response")
            completion(self.getCachedVersion())
          }
        } else {
          print("❌ Failed to parse JSON from App Store response")
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

  /// Clear cached version to force fresh API call (for debugging)
  func clearCache() {
    UserDefaults.standard.removeObject(forKey: latestVersionKey)
    UserDefaults.standard.removeObject(forKey: lastVersionCheckKey)
    print("📱 Version cache cleared")
  }
}
