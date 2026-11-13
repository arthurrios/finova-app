# Finova for Android

Native Kotlin + Jetpack Compose port of the iOS app, living next to it in this repo.

- **Source of truth:** iOS `release/v1.5.2` (features, money rules, copy). It has every non-sync fix
  from 1.6.0. Sync (CloudKit) is out of scope; any future sync must be a backend both apps share.
- **Package / applicationId:** `com.arthurrios.finova` (permanent once on Google Play).
- **Design tokens:** `ui/theme/` mirrors `Finova/Sources/Core/Constants/` on iOS.

## Open and run

Open this `android/` folder (not the repo root) in Android Studio, let Gradle sync, pick an
emulator and press Run.

## Build from the command line

```bash
./gradlew assembleDebug
```

JDK 17 is enough. The first build was verified on Android Studio 2026.1, AGP 8.11.1, Gradle 8.14.3,
on the `Pixel_9_Pro_API_36` emulator.

## Status

App shell, theme and a placeholder screen. Screens are ported from iOS 1.5.2 one by one.
