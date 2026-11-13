#!/bin/sh

# Xcode Cloud post-clone: install the CocoaPods dependencies.
#
# `Pods/` is gitignored, so a fresh clone has no `Pods/Target Support Files/*.xcconfig`
# and every Pods target fails with "Unable to open base configuration reference file".
# Podfile.lock IS tracked and pins every version, so install from it here.
#
# Runs from ci_scripts/, so step up to the repo before installing.

set -e

echo "--- Restoring GoogleService-Info.plist"
# The plist is gitignored (it is a build input, not source), so a fresh clone does not have it.
# Without it `configureFirebase()` cannot run and the app traps inside FirebaseAuth about a second
# after launch, on whatever background thread first touches a singleton — a crash with no visible
# connection to its cause. Provide it as a base64 secret on the Xcode Cloud workflow.
if [ -z "${GOOGLE_SERVICE_INFO_PLIST_BASE64:-}" ]; then
    echo "GOOGLE_SERVICE_INFO_PLIST_BASE64 is not set."
    echo "Add it as a secret environment variable on the Xcode Cloud workflow."
    exit 1
fi

PLIST_DEST="$CI_PRIMARY_REPOSITORY_PATH/Finova/GoogleService-Info.plist"
echo "$GOOGLE_SERVICE_INFO_PLIST_BASE64" | base64 --decode > "$PLIST_DEST"

# Fail here rather than let a truncated or mis-pasted secret become a launch crash in TestFlight.
plutil -lint "$PLIST_DEST" >/dev/null || { echo "Decoded GoogleService-Info.plist is not a valid plist"; exit 1; }
echo "OK: $(wc -c < "$PLIST_DEST") bytes"

echo "--- Installing CocoaPods"
if ! command -v pod >/dev/null 2>&1; then
    brew install cocoapods
fi
pod --version

echo "--- pod install"
cd "$CI_PRIMARY_REPOSITORY_PATH"
# The CocoaPods CDN times out now and then on Xcode Cloud ("trunk URL couldn't be downloaded ...
# Timeout was reached"), which failed the 1.6.2 archive on an unchanged Podfile.lock. A network
# hiccup should cost a retry, not a release, so try three times before giving up.
attempt=1
until pod install --repo-update; do
    if [ "$attempt" -ge 3 ]; then
        echo "pod install failed $attempt times, giving up"
        exit 1
    fi
    echo "pod install failed (attempt $attempt of 3), retrying in 30s"
    attempt=$((attempt + 1))
    sleep 30
done

echo "--- Sanity check: the xcconfig Cloud needs must now exist"
test -f "Pods/Target Support Files/Pods-Finova/Pods-Finova.release.xcconfig" \
    || { echo "Pods-Finova.release.xcconfig still missing after pod install"; exit 1; }
echo "OK"
