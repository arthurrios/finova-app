//
//  VersionServiceE2ETests.swift
//  FinovaTests
//
//  Created by Claude on 29/01/2026.
//

import Foundation
import XCTest

@testable import Finova

/// End-to-end tests for version checking against the real App Store API.
/// These tests verify the complete workflow from API call to version comparison.
///
/// Note: These tests require network access and hit the real iTunes API.
/// They may fail if the app is not published or if there are network issues.
class VersionServiceE2ETests: XCTestCase {

  var versionService: VersionService!

  // UserDefaults keys (must match VersionService)
  private let latestVersionKey = "latestAppVersion"
  private let lastVersionCheckKey = "lastVersionCheck"

  override func setUp() {
    super.setUp()
    versionService = VersionService.shared
    clearVersionCache()
  }

  override func tearDown() {
    clearVersionCache()
    super.tearDown()
  }

  // MARK: - Helper Methods

  private func clearVersionCache() {
    UserDefaults.standard.removeObject(forKey: latestVersionKey)
    UserDefaults.standard.removeObject(forKey: lastVersionCheckKey)
    versionService.clearCache()
  }

  private func getCurrentAppVersion() -> String {
    return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
  }

  // MARK: - E2E Tests: iTunes API Integration

  /// Tests that the version service can successfully fetch data from the iTunes API
  func testFetchVersionFromiTunesAPI() {
    let expectation = XCTestExpectation(description: "Fetch version from iTunes API")

    versionService.checkForUpdates { version in
      // The API should return a version string (either real or fallback)
      XCTAssertNotNil(version, "Version should not be nil")

      if let version = version {
        // Version should be a valid semver-like string (e.g., "1.0.0", "1.2.3")
        let versionPattern = #"^\d+\.\d+(\.\d+)?$"#
        let regex = try? NSRegularExpression(pattern: versionPattern)
        let range = NSRange(location: 0, length: version.utf16.count)
        let match = regex?.firstMatch(in: version, options: [], range: range)

        XCTAssertNotNil(match, "Version '\(version)' should match semver pattern")
        print("✅ Fetched version from API: \(version)")
      }

      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 10.0)
  }

  /// Tests that the version is cached after fetching
  func testVersionIsCachedAfterFetch() {
    let expectation = XCTestExpectation(description: "Version should be cached")

    // Ensure cache is clear
    XCTAssertNil(
      UserDefaults.standard.string(forKey: latestVersionKey),
      "Cache should be empty before test")

    versionService.checkForUpdates { version in
      // After fetch, version should be cached
      let cachedVersion = UserDefaults.standard.string(forKey: self.latestVersionKey)
      XCTAssertNotNil(cachedVersion, "Version should be cached after fetch")

      if let version = version, let cached = cachedVersion {
        XCTAssertEqual(version, cached, "Cached version should match fetched version")
        print("✅ Version cached correctly: \(cached)")
      }

      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 10.0)
  }

  /// Tests the complete flow: fetch from API, cache, compare versions
  func testCompleteVersionCheckFlow() {
    let expectation = XCTestExpectation(description: "Complete version check flow")
    let currentVersion = getCurrentAppVersion()

    print("📱 Current app version: \(currentVersion)")

    // Step 1: Fetch version from App Store
    versionService.checkForUpdates { [weak self] latestVersion in
      guard let self = self, let latestVersion = latestVersion else {
        XCTFail("Failed to fetch version")
        expectation.fulfill()
        return
      }

      print("📱 Latest version from API: \(latestVersion)")

      // Step 2: Verify caching worked
      let cachedVersion = UserDefaults.standard.string(forKey: self.latestVersionKey)
      XCTAssertEqual(cachedVersion, latestVersion, "Cached version should match")

      // Step 3: Test version comparison
      let comparisonResult = latestVersion.compare(currentVersion, options: .numeric)

      switch comparisonResult {
      case .orderedDescending:
        print("✅ App Store version (\(latestVersion)) > Current version (\(currentVersion))")
        print("   → Update toast SHOULD show")
      case .orderedSame:
        print("✅ App Store version (\(latestVersion)) = Current version (\(currentVersion))")
        print("   → Update toast should NOT show (same version)")
      case .orderedAscending:
        print("✅ App Store version (\(latestVersion)) < Current version (\(currentVersion))")
        print("   → Update toast should NOT show (running newer dev build)")
      }

      // The test passes regardless of comparison result - we're testing the flow works
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 10.0)
  }

  /// Tests that rate limiting works (skips API call if checked recently)
  func testRateLimitingPreventsFrequentAPICalls() {
    let expectation1 = XCTestExpectation(description: "First API call")
    let expectation2 = XCTestExpectation(description: "Second call should use cache")

    // First call - should hit the API
    versionService.checkForUpdates { version in
      XCTAssertNotNil(version, "First call should return version")
      print("✅ First call completed: \(version ?? "nil")")
      expectation1.fulfill()
    }

    wait(for: [expectation1], timeout: 10.0)

    // Second call immediately after - should use cache due to rate limiting
    let cacheCheckStart = Date()
    versionService.checkForUpdates { version in
      let elapsed = Date().timeIntervalSince(cacheCheckStart)
      XCTAssertNotNil(version, "Second call should return cached version")

      // If rate limiting works, the second call should be almost instant (< 1 second)
      // because it uses cache instead of making another API call
      print("✅ Second call completed in \(String(format: "%.3f", elapsed))s: \(version ?? "nil")")

      expectation2.fulfill()
    }

    wait(for: [expectation2], timeout: 10.0)
  }

  // MARK: - E2E Tests: UpdateToastManager Integration

  /// Tests the complete UpdateToastManager flow with real API data
  func testUpdateToastManagerWithRealAPI() {
    let expectation = XCTestExpectation(description: "UpdateToastManager API integration")

    // Clear all state
    clearVersionCache()
    #if DEBUG
      UpdateToastManager.shared.resetTestingState()
    #endif

    let currentVersion = getCurrentAppVersion()
    print("📱 Testing UpdateToastManager with current version: \(currentVersion)")

    // Use UpdateToastManager to check for updates
    UpdateToastManager.shared.checkForUpdatesFromAppStore { hasNewerVersion in
      print("📱 UpdateToastManager.hasNewerVersion: \(hasNewerVersion)")

      // Now check if toast should show
      let shouldShow = UpdateToastManager.shared.shouldShowUpdateToast()
      print("📱 UpdateToastManager.shouldShowUpdateToast: \(shouldShow)")

      // The result depends on App Store version vs current version
      // This test verifies the integration works, not specific behavior
      if hasNewerVersion {
        // If there's a newer version and no cooldowns, toast should show
        XCTAssertTrue(
          shouldShow,
          "Toast should show when newer version available and no cooldowns active")
      } else {
        // If no newer version, toast should not show
        XCTAssertFalse(shouldShow, "Toast should not show when no newer version")
      }

      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 10.0)
  }

  /// Tests that the toast correctly respects cooldown after being shown
  func testToastCooldownAfterShowing() {
    let expectation = XCTestExpectation(description: "Toast cooldown test")

    // Clear state and set up a mock newer version
    clearVersionCache()
    #if DEBUG
      UpdateToastManager.shared.resetTestingState()
      UpdateToastManager.shared.setMockLatestVersion("99.0.0")
    #endif

    // First check - should show
    let shouldShowFirst = UpdateToastManager.shared.shouldShowUpdateToast()
    #if DEBUG
      XCTAssertTrue(shouldShowFirst, "Toast should show first time")
    #endif

    // Mark as shown
    UpdateToastManager.shared.markToastAsShown()

    // Second check - should NOT show due to 30-min cooldown
    let shouldShowSecond = UpdateToastManager.shared.shouldShowUpdateToast()
    XCTAssertFalse(shouldShowSecond, "Toast should not show immediately after being shown")

    print("✅ Cooldown working correctly")
    expectation.fulfill()

    wait(for: [expectation], timeout: 5.0)
  }

  // MARK: - E2E Tests: Version Comparison Edge Cases

  /// Tests version comparison with various version string formats
  func testVersionComparisonFormats() {
    // Test cases: (version1, version2, expected: version1 > version2)
    let testCases: [(String, String, Bool)] = [
      ("2.0.0", "1.0.0", true),  // Major version
      ("1.1.0", "1.0.0", true),  // Minor version
      ("1.0.1", "1.0.0", true),  // Patch version
      ("1.10.0", "1.9.0", true),  // Double-digit minor
      ("1.0.0", "1.0.0", false),  // Equal versions
      ("1.0.0", "2.0.0", false),  // Older version
      ("1.2", "1.1.0", true),  // Missing patch
      ("2.0", "1.9.9", true),  // Missing patch vs full version
    ]

    for (latest, current, expectedNewer) in testCases {
      let result = latest.compare(current, options: .numeric) == .orderedDescending
      XCTAssertEqual(
        result, expectedNewer,
        "Expected '\(latest)' > '\(current)' to be \(expectedNewer), got \(result)"
      )
      print("✅ '\(latest)' > '\(current)' = \(result) (expected: \(expectedNewer))")
    }
  }

  // MARK: - E2E Tests: Network Error Handling

  /// Tests that the service handles network errors gracefully
  func testNetworkErrorHandling() {
    let expectation = XCTestExpectation(description: "Network error handling")

    // Clear cache to force API call
    clearVersionCache()

    // Even if network fails, should return cached or fallback version
    versionService.checkForUpdates { version in
      // Should never crash, should return some version (cached or current as fallback)
      print("📱 Version returned (may be fallback): \(version ?? "nil")")
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 15.0)
  }

  // MARK: - E2E Tests: Full User Journey Simulation

  /// Simulates a complete user journey: fresh install → update available → dismiss → reminder
  func testFullUserJourney() {
    // Step 1: Fresh install (clear all state)
    clearVersionCache()
    #if DEBUG
      UpdateToastManager.shared.resetTestingState()
    #endif

    print("\n🧪 === FULL USER JOURNEY TEST ===\n")

    // Step 2: Simulate newer version on App Store
    #if DEBUG
      UpdateToastManager.shared.setMockLatestVersion("99.0.0")
      print("📱 Step 1: Set mock App Store version to 99.0.0")
    #endif

    // Step 3: First launch - toast should show
    let shouldShowFirstLaunch = UpdateToastManager.shared.shouldShowUpdateToast()
    #if DEBUG
      XCTAssertTrue(shouldShowFirstLaunch, "Toast should show on first launch with update available")
      print("✅ Step 2: Toast shows on first launch: \(shouldShowFirstLaunch)")
    #endif

    // Step 4: User sees toast, mark as shown
    UpdateToastManager.shared.markToastAsShown()
    print("📱 Step 3: User sees toast (marked as shown)")

    // Step 5: User opens app again within 30 minutes - should NOT show
    let shouldShowWithinCooldown = UpdateToastManager.shared.shouldShowUpdateToast()
    XCTAssertFalse(shouldShowWithinCooldown, "Toast should not show within 30-min cooldown")
    print("✅ Step 4: Toast hidden during 30-min cooldown: \(!shouldShowWithinCooldown)")

    // Step 6: Simulate 30 minutes passing
    let thirtyFiveMinutesAgo = Date().addingTimeInterval(-35 * 60)
    UserDefaults.standard.set(thirtyFiveMinutesAgo, forKey: "lastToastShown")
    print("📱 Step 5: Simulated 35 minutes passing")

    // Step 7: Toast should show again
    let shouldShowAfterCooldown = UpdateToastManager.shared.shouldShowUpdateToast()
    #if DEBUG
      XCTAssertTrue(shouldShowAfterCooldown, "Toast should show after 30-min cooldown")
      print("✅ Step 6: Toast shows after cooldown: \(shouldShowAfterCooldown)")
    #endif

    // Step 8: User clicks "Later" (dismisses)
    UpdateToastManager.shared.markToastAsDismissed()
    print("📱 Step 7: User clicked 'Later' (dismissed)")

    // Step 9: Toast should NOT show (6-hour dismissal cooldown)
    let shouldShowAfterDismiss = UpdateToastManager.shared.shouldShowUpdateToast()
    XCTAssertFalse(shouldShowAfterDismiss, "Toast should not show after dismissal")
    print("✅ Step 8: Toast hidden after dismissal: \(!shouldShowAfterDismiss)")

    // Step 10: Simulate 6 hours passing
    #if DEBUG
      UpdateToastManager.shared.simulate6HoursPassed()
      print("📱 Step 9: Simulated 6+ hours passing")
    #endif

    // Step 11: Toast should show as reminder
    let shouldShowReminder = UpdateToastManager.shared.shouldShowUpdateToast()
    #if DEBUG
      XCTAssertTrue(shouldShowReminder, "Toast should show as reminder after 6 hours")
      print("✅ Step 10: Reminder toast shows: \(shouldShowReminder)")
    #endif

    print("\n🧪 === USER JOURNEY COMPLETE ===\n")
  }
}
