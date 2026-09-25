# Finova for Android

Native Kotlin + Jetpack Compose port of the iOS app, living next to it in this repo.

- **Source of truth:** iOS `release/v1.5.2` (features, money rules, copy). It has every non-sync fix
  from 1.6.0. Sync (CloudKit) is out of scope; any future sync must be a backend both apps share.
- **Package / applicationId:** `com.arthurrios.finova` (permanent once on Google Play).
- **Design tokens:** `ui/theme/` mirrors `Finova/Sources/Core/Constants/` on iOS.

## Open and run

Open this `android/` folder (not the repo root) in Android Studio, let Gradle sync, pick an
emulator and press Run.

## Status

Skeleton only: app shell, theme, placeholder screen. Versions in `gradle/libs.versions.toml` have
not been through a first build yet. `gradlew` and the wrapper jar are not committed yet —
generate them on the first build (`gradle wrapper`, or let Android Studio create them).
