//
//  UpdateToastManagerTests.swift
//  FinovaTests
//
//  Created by Claude on 28/01/2026.
//

import Foundation
import XCTest

@testable import Finova

class UpdateToastManagerTests: XCTestCase {

    var updateToastManager: UpdateToastManager!

    // UserDefaults keys (must match UpdateToastManager)
    private let latestVersionKey = "latestAppVersion"
    private let lastToastDismissedKey = "lastToastDismissed"
    private let lastToastShownKey = "lastToastShown"
    private let toastDismissedForVersionKey = "toastDismissedForVersion"

    override func setUp() {
        super.setUp()
        updateToastManager = UpdateToastManager.shared
        clearAllToastState()
    }

    override func tearDown() {
        clearAllToastState()
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func clearAllToastState() {
        // Clear all toast-related UserDefaults
        UserDefaults.standard.removeObject(forKey: latestVersionKey)
        UserDefaults.standard.removeObject(forKey: lastToastDismissedKey)
        UserDefaults.standard.removeObject(forKey: lastToastShownKey)

        // Clear version-specific dismiss flags
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys
        for key in keys {
            if key.hasPrefix(toastDismissedForVersionKey) {
                defaults.removeObject(forKey: key)
            }
        }

        #if DEBUG
        updateToastManager.resetTestingState()
        #endif
    }

    private func getCurrentAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private func setMockLatestVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: latestVersionKey)
    }

    private func setLastToastShownDate(_ date: Date) {
        UserDefaults.standard.set(date, forKey: lastToastShownKey)
    }

    private func setLastToastDismissedDate(_ date: Date) {
        UserDefaults.standard.set(date, forKey: lastToastDismissedKey)
    }

    private func markToastDismissedForVersion(_ version: String) {
        UserDefaults.standard.set(true, forKey: "\(toastDismissedForVersionKey)_\(version)")
    }

    // MARK: - Version Comparison Tests

    func testVersionComparisonNewerVersionAvailable() {
        // Given: App Store has version 2.0.0, current is 1.0.0
        let currentVersion = getCurrentAppVersion()
        let newerVersion = "99.0.0" // Guaranteed to be newer than any real version

        setMockLatestVersion(newerVersion)

        // When: Check if toast should show
        let shouldShow = updateToastManager.shouldShowUpdateToast()

        // Then: Toast should show because newer version is available
        XCTAssertTrue(shouldShow, "Toast should show when App Store version (\(newerVersion)) > current version (\(currentVersion))")
    }

    func testVersionComparisonSameVersion() {
        // Given: App Store has same version as current
        let currentVersion = getCurrentAppVersion()
        setMockLatestVersion(currentVersion)

        // When: Check if toast should show
        let shouldShow = updateToastManager.shouldShowUpdateToast()

        // Then: Toast should NOT show because versions are equal
        XCTAssertFalse(shouldShow, "Toast should NOT show when versions are equal (\(currentVersion))")
    }

    func testVersionComparisonOlderVersionInStore() {
        // Given: App Store has older version than current (e.g., running dev build)
        let currentVersion = getCurrentAppVersion()
        setMockLatestVersion("0.0.1") // Guaranteed to be older

        // When: Check if toast should show
        let shouldShow = updateToastManager.shouldShowUpdateToast()

        // Then: Toast should NOT show because App Store version is older
        XCTAssertFalse(shouldShow, "Toast should NOT show when App Store version (0.0.1) < current version (\(currentVersion))")
    }

    func testVersionComparisonWithMultipleDigits() {
        // Given: Version comparison with multi-digit components
        setMockLatestVersion("99.10.0")

        // When: Check shouldShowUpdateToast
        let shouldShow = updateToastManager.shouldShowUpdateToast()

        // Then: Should handle multi-digit versions correctly
        XCTAssertTrue(shouldShow, "Should correctly compare multi-digit version numbers")
    }

    // MARK: - Cooldown Tests

    func testToastNotShownWithin30MinuteCooldown() {
        // Given: Toast was shown 15 minutes ago, newer version available
        setMockLatestVersion("99.0.0")
        let fifteenMinutesAgo = Date().addingTimeInterval(-15 * 60)
        setLastToastShownDate(fifteenMinutesAgo)

        // When: Check if toast should show
        let shouldShow = updateToastManager.shouldShowUpdateToast()

        // Then: Toast should NOT show due to 30-minute cooldown
        XCTAssertFalse(shouldShow, "Toast should NOT show within 30-minute cooldown period")
    }

    func testToastShownAfter30MinuteCooldown() {
        // Given: Toast was shown 35 minutes ago, newer version available
        setMockLatestVersion("99.0.0")
        let thirtyFiveMinutesAgo = Date().addingTimeInterval(-35 * 60)
        setLastToastShownDate(thirtyFiveMinutesAgo)

        // When: Check if toast should show
        let shouldShow = updateToastManager.shouldShowUpdateToast()

        // Then: Toast should show because 30-minute cooldown has passed
        XCTAssertTrue(shouldShow, "Toast should show after 30-minute cooldown has passed")
    }

    func testToastNotShownWithin6HourDismissalCooldown() {
        // Given: User dismissed toast 3 hours ago
        let currentVersion = getCurrentAppVersion()
        setMockLatestVersion("99.0.0")
        markToastDismissedForVersion(currentVersion)
        let threeHoursAgo = Date().addingTimeInterval(-3 * 60 * 60)
        setLastToastDismissedDate(threeHoursAgo)

        // When: Check if toast should show
        let shouldShow = updateToastManager.shouldShowUpdateToast()

        // Then: Toast should NOT show due to 6-hour dismissal cooldown
        XCTAssertFalse(shouldShow, "Toast should NOT show within 6-hour dismissal cooldown")
    }

    func testToastShownAfter6HourDismissalCooldown() {
        // Given: User dismissed toast 7 hours ago
        let currentVersion = getCurrentAppVersion()
        setMockLatestVersion("99.0.0")
        markToastDismissedForVersion(currentVersion)
        let sevenHoursAgo = Date().addingTimeInterval(-7 * 60 * 60)
        setLastToastDismissedDate(sevenHoursAgo)

        // When: Check if toast should show
        let shouldShow = updateToastManager.shouldShowUpdateToast()

        // Then: Toast should show because 6-hour dismissal cooldown has passed
        XCTAssertTrue(shouldShow, "Toast should show after 6-hour dismissal cooldown has passed")
    }

    // MARK: - Reset Testing State Tests

    #if DEBUG
    func testResetTestingStateClearsLastToastShownKey() {
        // Given: Toast was shown recently (within cooldown)
        setMockLatestVersion("99.0.0")
        let fiveMinutesAgo = Date().addingTimeInterval(-5 * 60)
        setLastToastShownDate(fiveMinutesAgo)

        // Verify cooldown is active
        let shouldShowBeforeReset = updateToastManager.shouldShowUpdateToast()
        XCTAssertFalse(shouldShowBeforeReset, "Toast should NOT show before reset due to cooldown")

        // When: Reset testing state
        updateToastManager.resetTestingState()

        // Set the mock version again (resetTestingState clears it)
        setMockLatestVersion("99.0.0")

        // Then: Toast should show because lastToastShownKey was cleared
        let shouldShowAfterReset = updateToastManager.shouldShowUpdateToast()
        XCTAssertTrue(shouldShowAfterReset, "Toast should show after resetTestingState clears cooldown")
    }

    func testResetTestingStateClearsLatestVersionKey() {
        // Given: A mock version is cached
        setMockLatestVersion("99.0.0")

        // Verify version is cached
        let cachedVersion = UserDefaults.standard.string(forKey: latestVersionKey)
        XCTAssertEqual(cachedVersion, "99.0.0", "Version should be cached before reset")

        // When: Reset testing state
        updateToastManager.resetTestingState()

        // Then: Cached version should be cleared
        let clearedVersion = UserDefaults.standard.string(forKey: latestVersionKey)
        XCTAssertNil(clearedVersion, "Cached version should be nil after reset")
    }

    func testResetTestingStateClearsDismissedKey() {
        // Given: Toast was dismissed
        let currentVersion = getCurrentAppVersion()
        markToastDismissedForVersion(currentVersion)
        setLastToastDismissedDate(Date())

        // Verify dismissed state
        let isDismissed = UserDefaults.standard.bool(forKey: "\(toastDismissedForVersionKey)_\(currentVersion)")
        XCTAssertTrue(isDismissed, "Toast should be marked as dismissed before reset")

        // When: Reset testing state
        updateToastManager.resetTestingState()

        // Then: Dismissed state should be cleared
        let isDismissedAfterReset = UserDefaults.standard.bool(forKey: "\(toastDismissedForVersionKey)_\(currentVersion)")
        XCTAssertFalse(isDismissedAfterReset, "Dismissed state should be cleared after reset")
    }

    func testSetMockLatestVersion() {
        // Given: Clean state
        clearAllToastState()

        // When: Set mock version
        updateToastManager.setMockLatestVersion("5.0.0")

        // Then: Mock version should be used
        let shouldShow = updateToastManager.shouldShowUpdateToast()
        XCTAssertTrue(shouldShow, "Toast should show with mock version 5.0.0")
    }

    func testForceShowToastForTesting() {
        // Given: No newer version available (same version)
        let currentVersion = getCurrentAppVersion()
        setMockLatestVersion(currentVersion)

        // Verify toast would NOT show normally
        let shouldShowNormally = updateToastManager.shouldShowUpdateToast()
        XCTAssertFalse(shouldShowNormally, "Toast should NOT show normally with same version")

        // When: Force show toast
        // Note: forceShowToastForTesting() calls the delegate, so we just verify the flag works
        updateToastManager.forceShowToastForTesting()

        // Then: shouldShowUpdateToast should return true due to force flag
        let shouldShowForced = updateToastManager.shouldShowUpdateToast()
        XCTAssertTrue(shouldShowForced, "Toast should show when force flag is set")

        // Cleanup: Reset to clear force flag
        updateToastManager.resetTestingState()
    }

    func testSimulate6HoursPassed() {
        // Given: Toast was just dismissed
        let currentVersion = getCurrentAppVersion()
        setMockLatestVersion("99.0.0")
        markToastDismissedForVersion(currentVersion)
        setLastToastDismissedDate(Date())

        // Verify toast would NOT show due to recent dismissal
        let shouldShowBeforeSimulation = updateToastManager.shouldShowUpdateToast()
        XCTAssertFalse(shouldShowBeforeSimulation, "Toast should NOT show before simulating time passage")

        // When: Simulate 6 hours passing
        updateToastManager.simulate6HoursPassed()

        // Then: Toast should show because 6 hours have "passed"
        let shouldShowAfterSimulation = updateToastManager.shouldShowUpdateToast()
        XCTAssertTrue(shouldShowAfterSimulation, "Toast should show after simulating 6 hours passing")
    }
    #endif

    // MARK: - Mark Toast Methods Tests

    func testMarkToastAsShown() {
        // Given: Clean state, newer version available
        setMockLatestVersion("99.0.0")

        // Verify toast would show
        let shouldShowBefore = updateToastManager.shouldShowUpdateToast()
        XCTAssertTrue(shouldShowBefore, "Toast should show initially")

        // When: Mark toast as shown
        updateToastManager.markToastAsShown()

        // Then: Toast should NOT show due to cooldown
        let shouldShowAfter = updateToastManager.shouldShowUpdateToast()
        XCTAssertFalse(shouldShowAfter, "Toast should NOT show after being marked as shown (30-min cooldown)")
    }

    func testMarkToastAsDismissed() {
        // Given: Clean state, newer version available
        setMockLatestVersion("99.0.0")

        // Verify toast would show
        let shouldShowBefore = updateToastManager.shouldShowUpdateToast()
        XCTAssertTrue(shouldShowBefore, "Toast should show initially")

        // When: Mark toast as dismissed
        updateToastManager.markToastAsDismissed()

        // Then: Toast should NOT show due to 6-hour dismissal cooldown
        let shouldShowAfter = updateToastManager.shouldShowUpdateToast()
        XCTAssertFalse(shouldShowAfter, "Toast should NOT show after being dismissed (6-hour cooldown)")
    }

    // MARK: - Edge Cases

    func testNoLatestVersionCached() {
        // Given: No version cached (first launch scenario)
        clearAllToastState()

        // When: Check if toast should show
        let shouldShow = updateToastManager.shouldShowUpdateToast()

        // Then: Toast should NOT show because fallback is current version (no update)
        XCTAssertFalse(shouldShow, "Toast should NOT show when no version is cached (uses current as fallback)")
    }

    func testFirstTimeToastAppears() {
        // Given: Newer version available, no previous toast history
        clearAllToastState()
        setMockLatestVersion("99.0.0")

        // When: Check if toast should show
        let shouldShow = updateToastManager.shouldShowUpdateToast()

        // Then: Toast should show
        XCTAssertTrue(shouldShow, "Toast should show on first appearance when newer version exists")
    }

    // MARK: - Integration Flow Tests

    func testCompleteUpdateToastFlow() {
        // This test simulates the complete flow a production user would experience

        // Step 1: User installs app, newer version exists on App Store
        clearAllToastState()
        setMockLatestVersion("99.0.0")

        let shouldShowFirstTime = updateToastManager.shouldShowUpdateToast()
        XCTAssertTrue(shouldShowFirstTime, "Step 1: Toast should show on first launch with newer version")

        // Step 2: User sees toast, mark it as shown
        updateToastManager.markToastAsShown()

        let shouldShowImmediately = updateToastManager.shouldShowUpdateToast()
        XCTAssertFalse(shouldShowImmediately, "Step 2: Toast should NOT show immediately after being shown")

        // Step 3: 30 minutes pass, toast should show again
        let thirtyFiveMinutesAgo = Date().addingTimeInterval(-35 * 60)
        setLastToastShownDate(thirtyFiveMinutesAgo)

        let shouldShowAfterCooldown = updateToastManager.shouldShowUpdateToast()
        XCTAssertTrue(shouldShowAfterCooldown, "Step 3: Toast should show after 30-minute cooldown")

        // Step 4: User clicks "Later" (dismisses)
        updateToastManager.markToastAsDismissed()

        let shouldShowAfterDismiss = updateToastManager.shouldShowUpdateToast()
        XCTAssertFalse(shouldShowAfterDismiss, "Step 4: Toast should NOT show after dismissal")

        // Step 5: 6 hours pass, toast should show as reminder
        #if DEBUG
        updateToastManager.simulate6HoursPassed()
        #else
        let sevenHoursAgo = Date().addingTimeInterval(-7 * 60 * 60)
        setLastToastDismissedDate(sevenHoursAgo)
        #endif

        let shouldShowAsReminder = updateToastManager.shouldShowUpdateToast()
        XCTAssertTrue(shouldShowAsReminder, "Step 5: Toast should show as reminder after 6 hours")
    }
}
