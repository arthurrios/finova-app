import XCTest

/// Launch smoke test, run by Xcode Cloud on the Release build before an archive is distributed.
///
/// iOS 1.6.1 passed every build step and crashed about a second after launch for every App Store
/// user, because GoogleService-Info.plist was missing from the bundle. The unit tests run a Debug
/// build, where a missing plist is tolerated, so they could not see it. This test runs under the
/// "Finova Launch Test" scheme, whose test action uses the Release configuration, and only checks
/// that the app is still running after a few seconds.
final class LaunchSmokeTests: XCTestCase {
    /// Long enough to cover Firebase setup and the first database work after launch.
    private let aliveSeconds: TimeInterval = 10

    func testReleaseAppStaysRunningAfterLaunch() {
        let app = XCUIApplication()
        app.launch()

        let deadline = Date().addingTimeInterval(aliveSeconds)
        while Date() < deadline {
            XCTAssertEqual(
                app.state, .runningForeground,
                "Finova stopped running after launch. Check the crash log of this run: a Release "
                    + "build without GoogleService-Info.plist stops here on purpose."
            )
            if app.state != .runningForeground { return }
            Thread.sleep(forTimeInterval: 1)
        }
    }
}
