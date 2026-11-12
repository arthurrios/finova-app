# Release checklist

iOS 1.6.1 crashed at launch for every App Store user. `GoogleService-Info.plist` is not in git,
the 1.6 branches were cut without the fix that writes it on Xcode Cloud (`2af396c`), and nothing
checked the shipped app. These checks exist so that cannot happen again.

## Secrets

Key files are never committed. CI gets them from secrets.

### GitHub (repository → Settings → Secrets and variables → Actions → New repository secret)

| Secret | Value | Make it with |
| --- | --- | --- |
| `GOOGLE_SERVICE_INFO_PLIST_BASE64` | iOS Firebase config | `base64 -i Finova/GoogleService-Info.plist \| pbcopy` |
| `GOOGLE_SERVICES_JSON_BASE64` | Android Firebase config | `base64 -i android/app/google-services.json \| pbcopy` |
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | Android upload key (`.jks`) | `base64 -i ~/.finova-keys/finova-upload.jks \| pbcopy` |
| `ANDROID_KEYSTORE_PASSWORD` | `storePassword` from `android/keystore.properties` | copy by hand |
| `ANDROID_KEY_ALIAS` | `keyAlias` from `android/keystore.properties` | copy by hand |
| `ANDROID_KEY_PASSWORD` | `keyPassword` from `android/keystore.properties` | copy by hand |

### Xcode Cloud (App Store Connect → Xcode Cloud → workflow → Environment → Secret)

| Variable | Value |
| --- | --- |
| `GOOGLE_SERVICE_INFO_PLIST_BASE64` | same value as the GitHub secret; mark it **Secret** |

`ci_scripts/ci_post_clone.sh` writes the plist from it and stops the build if it is missing.
`ci_scripts/ci_post_xcodebuild.sh` stops the build if the archived app has no plist.

## What runs on every push and pull request (`.github/workflows/release-checks.yml`)

Branches: `main` and `release/**`.

| Job | Fails when |
| --- | --- |
| Android unit tests | `./gradlew :app:testDebugUnitTest` fails |
| Android release build | a secret is missing, the bundle is not signed with the upload key, or it has no Firebase config |
| iOS unit tests | a test fails that is not in `ci/known-ios-test-failures.txt`, or no tests ran |
| iOS launch smoke test | the Release app has no `GoogleService-Info.plist`, or exits within 12 s of launch |
| Release branch audit | a `fix` commit on an older release branch is not in the newest one |

A release build on any machine (CI or your Mac) also refuses to run without
`android/app/google-services.json` and `android/keystore.properties`. Debug builds still work
without them.

## Before you cut a new release branch

1. Run the audit against the branch you are about to cut from:
   `scripts/release-branch-audit.sh --target origin/<branch>`
2. Cherry-pick every listed fix, or add it to `ci/release-audit-reviewed.txt` with a reason.
3. Copy `.github/workflows/release-checks.yml`, `scripts/ci/`, `scripts/release-branch-audit.sh`
   and `ci/` into the new branch if it does not have them. GitHub runs the workflow file that is
   on the pushed branch.

## Before you upload to the App Store

1. All jobs of **Release checks** are green on the release branch.
2. The Xcode Cloud build is green. Both `ci_post_clone.sh` and `ci_post_xcodebuild.sh` ran
   (search the log for `OK: Finova`).
3. If you archive on your Mac instead: archive from the CLI with
   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, never from a beta Xcode. Then check
   the `.ipa`:
   - `unzip -l build/export/Finova.ipa | grep GoogleService-Info.plist` shows the file;
   - `DTSDKName` in its `Info.plist` is not a beta SDK.
4. Install the TestFlight build on a real phone. Open it. Sign in. Before you release to users.
5. Use a phased release, so a crash reaches few people and you can pause it.

## Before you upload to Google Play

1. All jobs of **Release checks** are green on the release branch.
2. Build the bundle on your Mac: `cd android && ./gradlew :app:bundleRelease`. It stops if the
   Firebase config or the signing setup is missing.
3. Check `versionCode` and `versionName` in `android/app/build.gradle.kts` are higher than the
   build on Play.
4. Upload to the **internal testing** track first. Install it from Play on a real phone. Open it.
   Sign in. Then promote it.
5. Use a staged rollout (for example 10%) for production.
