#!/bin/bash
# Release preflight: run on your Mac before uploading a build to Google Play (and, optionally,
# before you push a release branch that Xcode Cloud will archive).
#
#   scripts/release-preflight.sh              android + audit (the default)
#   scripts/release-preflight.sh android      Android unit tests + signed release bundle, then checks it
#   scripts/release-preflight.sh audit        fix commits on older release branches missing from the newest
#   scripts/release-preflight.sh ios          the Release launch test on a simulator (Xcode Cloud runs it too)
#
# Google Play has no build service, so the Android bundle is always built here. Exit 1 on any failure.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

STEPS=("$@")
[ ${#STEPS[@]} -gt 0 ] || STEPS=(android audit)

FAILED=()
step() { echo; echo "=== $*"; }

prop() { grep "^$1=" android/keystore.properties | cut -d= -f2-; }

run_android() {
    step "Android: unit tests and signed release bundle"
    # The Gradle guard in android/app/build.gradle.kts stops bundleRelease when google-services.json
    # or keystore.properties is missing, with a list of what is missing.
    (cd android && ./gradlew :app:testDebugUnitTest :app:bundleRelease) || return 1

    local aab=android/app/build/outputs/bundle/release/app-release.aab
    [ -f "$aab" ] || { echo "No bundle at $aab"; return 1; }

    step "Android: checking the bundle"
    local expected actual
    expected=$(keytool -list -v -keystore "$(prop storeFile)" -storepass "$(prop storePassword)" \
        -alias "$(prop keyAlias)" 2>/dev/null | awk '/SHA256:/ {print $2; exit}')
    actual=$(keytool -printcert -jarfile "$aab" 2>/dev/null | awk '/SHA256:/ {print $2; exit}')
    if [ -z "$actual" ]; then
        echo "FAIL: the bundle is not signed."; return 1
    fi
    if [ -z "$expected" ] || [ "$actual" != "$expected" ]; then
        echo "FAIL: the bundle is not signed with the upload key in keystore.properties."; return 1
    fi
    echo "OK: signed with the upload key"

    # Count, not grep -q: with pipefail, grep -q exiting early makes unzip fail on SIGPIPE.
    if [ "$(unzip -p "$aab" base/resources.pb | grep -ac google_app_id || true)" = "0" ]; then
        echo "FAIL: the bundle has no google_app_id. The Firebase config did not make it in."; return 1
    fi
    echo "OK: Firebase config is in the bundle"

    grep -E '^\s*version(Code|Name)\s*=' android/app/build.gradle.kts | sed 's/^ */  /'
    echo "  Check these are higher than the build already on Google Play."
    echo "  Bundle: $REPO/$aab"
}

run_audit() {
    step "Release branch audit"
    git fetch --quiet origin
    scripts/release-branch-audit.sh
}

run_ios() {
    step "iOS: Release launch test"
    [ -f Finova/GoogleService-Info.plist ] || { echo "FAIL: Finova/GoogleService-Info.plist is missing."; return 1; }
    local udid
    udid=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
key = lambda r: tuple(int(x) for x in re.findall(r"iOS-(\d+)-(\d+)", r)[0])
for runtime in sorted((r for r in devices if re.search(r"iOS-\d+-\d+", r)), key=key, reverse=True):
    for d in devices[runtime]:
        if d.get("isAvailable") and d["name"].startswith("iPhone"):
            print(d["udid"]); sys.exit(0)
sys.exit("No available iPhone simulator")')
    xcodebuild test -workspace Finova.xcworkspace -scheme "Finova Launch Test" \
        -destination "id=$udid" -quiet
}

for s in "${STEPS[@]}"; do
    case "$s" in
        android) run_android || FAILED+=(android) ;;
        audit)   run_audit   || FAILED+=(audit) ;;
        ios)     run_ios     || FAILED+=(ios) ;;
        *) echo "Unknown step: $s (use android, audit, ios)"; exit 2 ;;
    esac
done

echo
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "PREFLIGHT FAILED: ${FAILED[*]}. Do not upload."
    exit 1
fi
echo "PREFLIGHT OK: ${STEPS[*]}"
