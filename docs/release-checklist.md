# Release checklist

iOS 1.6.1 crashed at launch for every App Store user. `GoogleService-Info.plist` is not in git,
the 1.6 branches were cut without the fix that writes it on Xcode Cloud (`2af396c`), and nothing
checked the shipped app. These checks exist so that cannot happen again. They cost nothing:
iOS checks run in Xcode Cloud (included in the Apple Developer membership), Android checks run on
your Mac (Google Play has no build service).

## iOS: Xcode Cloud

### Secret (App Store Connect → Xcode Cloud → workflow → Environment)

| Variable | Value |
| --- | --- |
| `GOOGLE_SERVICE_INFO_PLIST_BASE64` | `base64 -i Finova/GoogleService-Info.plist \| pbcopy`, marked **Secret** |

### Workflow actions (set once, in Xcode → Report navigator → Cloud → Manage Workflows)

| Action | Scheme | What it stops |
| --- | --- | --- |
| Test | `Finova CI Tests` (test plan `FinovaTests-CI`), an iPhone simulator | any unit test failure that is not a known one |
| Test | `Finova Launch Test`, an iPhone simulator | a Release app that crashes within 10 s of launch (the 1.6.1 crash) |
| Archive | `Finova` | as before |

Keep TestFlight / App Store distribution as a **post-action**, so it only runs when every action
above succeeded. Check this on the first run: a red test action must leave no new TestFlight build.

The scripts run in every action:

- `ci_scripts/ci_post_clone.sh` writes the plist from the secret and stops if it is missing.
- `ci_scripts/ci_post_xcodebuild.sh` stops the archive if the archived app has no plist.

### Known unit test failures

`FinovaTests-CI.xctestplan` runs `FinovaTests` serially (parallel runs make suites pollute each
other) and skips these, which also fail on the unmodified release branch:

| Skipped | Why |
| --- | --- |
| `AuthenticationTests/testFaceIDUserManagement()` | red on 1.6.0 and 1.6.2; cause not checked (probably no Face ID on a simulator) |
| `NotificationTests/testRecurringNotificationsNotMarkedAsDuplicates()` | red on 1.6.0 and 1.6.2 |
| `BalanceMonitorTests` (whole suite) | results depend on today's date; which tests fail moves with the calendar |
| `ImportRollbackTests`, `ImportRecurringSafetyTests` (whole suites) | order pollution: red in some full runs, green alone |

Sources: full serial runs of release/v1.6.2 (2026-11-12, 1061 tests, 5 failed) and
release/v1.6.0 (2026-10-18, 905 tests, 9 failed). Remove a skip once its test is fixed. Add one
only after the same test fails on the unmodified base branch.

`FinovaTests` (the scheme you use in Xcode) still runs everything.

## Android: your Mac

A release build (`bundleRelease`, `assembleRelease`) refuses to run without
`android/app/google-services.json` and `android/keystore.properties`. Debug builds do not need them.

## Before you push a release branch for Xcode Cloud

1. `scripts/release-preflight.sh audit`. It lists `fix` commits on older release branches that
   the newest one does not have. Cherry-pick each one, or add its SHA and a reason to
   `ci/release-audit-reviewed.txt`.
2. Optional: `scripts/release-preflight.sh ios` runs the launch test on your simulator.

## Before you release an iOS build

1. The Xcode Cloud run is green: both test actions and the archive.
2. If you archive on your Mac instead: archive from the CLI with
   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, never from a beta Xcode. Then check
   the `.ipa`: `unzip -l build/export/Finova.ipa | grep GoogleService-Info.plist` shows the file,
   and `DTSDKName` in its `Info.plist` is not a beta SDK.
3. Install the TestFlight build on a real phone. Open it. Sign in.
4. Use a phased release, so a crash reaches few people and you can pause it.

## Before you upload to Google Play

1. `scripts/release-preflight.sh`. It runs the Android unit tests, builds the signed bundle,
   checks it is signed with your upload key and carries the Firebase config, and runs the audit.
   It prints the bundle path and the version.
2. Check `versionCode` and `versionName` are higher than the build on Play.
3. Upload to the **internal testing** track first. Install it from Play on a real phone. Open it.
   Sign in. Then promote it.
4. Use a staged rollout (for example 10%) for production.
