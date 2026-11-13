#!/bin/sh

# Xcode Cloud post-xcodebuild: check the archive before it can be distributed.
#
# ci_post_clone.sh writes GoogleService-Info.plist from a secret, and the app refuses to start
# without it. Both of those happen too early or too late to see what actually shipped, and 1.6.1
# reached the App Store without the file. This looks inside the archived app itself, so a missing
# build input fails the build here instead of crashing on users' phones.

set -e

# Only archives are distributed. Build and test actions have no archive to check.
if [ -z "${CI_ARCHIVE_PATH:-}" ]; then
    echo "--- No archive (action: ${CI_XCODEBUILD_ACTION:-unknown}), nothing to check"
    exit 0
fi

APP="$CI_ARCHIVE_PATH/Products/Applications/Finova.app"
echo "--- Checking the archived app: $APP"

if [ ! -d "$APP" ]; then
    echo "Finova.app not found in the archive"
    exit 1
fi

PLIST="$APP/GoogleService-Info.plist"
if [ ! -f "$PLIST" ]; then
    echo "GoogleService-Info.plist is missing from the archived app: it would crash at launch."
    echo "Check GOOGLE_SERVICE_INFO_PLIST_BASE64 on the Xcode Cloud workflow."
    exit 1
fi
plutil -lint "$PLIST" >/dev/null || { echo "GoogleService-Info.plist in the archive is not a valid plist"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Info.plist")
echo "OK: Finova $VERSION ($BUILD) has its Firebase configuration"
