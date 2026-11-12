#!/bin/bash
# Launch smoke test: build the Release app for the simulator, launch it, and fail if it dies early.
#
# iOS 1.6.1 passed every build step and crashed about a second after launch for every App Store
# user, because GoogleService-Info.plist was missing from the bundle. Unit tests did not notice:
# they run a Debug build where a missing plist is tolerated. This runs the Release configuration
# and simply checks the process is still alive after SMOKE_SECONDS.
#
# Environment (all optional):
#   SIMULATOR_UDID   simulator to use (default: scripts/ci/pick-simulator.sh)
#   DERIVED_DATA     derived data path (default: build/smoke-derived-data)
#   APP_PATH         skip the build and launch this .app instead
#   SMOKE_SECONDS    how long the app must stay alive (default: 12)
#   SKIP_BUNDLE_CHECK=1  launch even if the plist is missing (to prove the launch check works)

set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPTS/../.." && pwd)}"
cd "$REPO"

BUNDLE_ID="com.arthurrios.FinanceApp"
SMOKE_SECONDS="${SMOKE_SECONDS:-12}"
DERIVED_DATA="${DERIVED_DATA:-$REPO/build/smoke-derived-data}"
LOGS="${SMOKE_LOGS:-$REPO/build/smoke-logs}"
mkdir -p "$LOGS"

UDID="$("$SCRIPTS/pick-simulator.sh")"
echo "--- Simulator $UDID"

if [ -z "${APP_PATH:-}" ]; then
    echo "--- Building Finova (Release, iphonesimulator)"
    # Ad-hoc signing ("-") is what a simulator needs; no certificates involved.
    xcodebuild build \
        -workspace Finova.xcworkspace \
        -scheme Finova \
        -configuration Release \
        -sdk iphonesimulator \
        -destination "id=$UDID" \
        -derivedDataPath "$DERIVED_DATA" \
        CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
        > "$LOGS/build.log" 2>&1 || {
            grep -E ': error:|^\*\* ' "$LOGS/build.log" | tail -n 30
            echo "::error::Release simulator build failed (see build.log)"
            exit 1
        }
    tail -n 1 "$LOGS/build.log"
    APP_PATH="$DERIVED_DATA/Build/Products/Release-iphonesimulator/Finova.app"
fi
[ -d "$APP_PATH" ] || { echo "::error::$APP_PATH not found"; exit 1; }

echo "--- Checking the bundle"
if [ ! -f "$APP_PATH/GoogleService-Info.plist" ]; then
    if [ "${SKIP_BUNDLE_CHECK:-}" = "1" ]; then
        echo "GoogleService-Info.plist is missing (SKIP_BUNDLE_CHECK=1, launching anyway)"
    else
        echo "::error::GoogleService-Info.plist is missing from Finova.app: the app would crash at launch."
        exit 1
    fi
else
    plutil -lint "$APP_PATH/GoogleService-Info.plist" >/dev/null
    echo "OK: GoogleService-Info.plist is in the bundle"
fi

echo "--- Booting the simulator"
xcrun simctl boot "$UDID" 2>/dev/null || true   # already booted is fine
xcrun simctl bootstatus "$UDID" -b >/dev/null

# Leave the simulator as we found it: remove the app afterwards only if it was not there before.
WAS_INSTALLED=0
xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 && WAS_INSTALLED=1
cleanup() {
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    [ "$WAS_INSTALLED" = "1" ] || xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

xcrun simctl install "$UDID" "$APP_PATH"

echo "--- Launching for ${SMOKE_SECONDS}s"
MARKER="$LOGS/.launch-marker"
touch "$MARKER"
START=$(date +%s)
OUT=$(xcrun simctl launch --terminate-running-process \
    --stdout="$LOGS/app-stdout.log" --stderr="$LOGS/app-stderr.log" \
    "$UDID" "$BUNDLE_ID")
PID="${OUT##*: }"
echo "Launched: pid $PID"

alive=1
for _ in $(seq 1 "$SMOKE_SECONDS"); do
    sleep 1
    if ! kill -0 "$PID" 2>/dev/null; then
        alive=0
        break
    fi
done
ELAPSED=$(( $(date +%s) - START ))

if [ "$alive" = "1" ]; then
    echo "OK: Finova is still running after ${ELAPSED}s"
    exit 0
fi

echo "::error::Finova exited ${ELAPSED}s after launch. This is a launch crash."
echo "--- Last app output"
tail -n 40 "$LOGS/app-stderr.log" "$LOGS/app-stdout.log" 2>/dev/null || true
# Crash reports for simulator apps land in the host's DiagnosticReports.
# Only reports written after this launch; give ReportCrash a few seconds to write it.
REPORT=""
for _ in 1 2 3 4 5; do
    REPORT=$(find ~/Library/Logs/DiagnosticReports -maxdepth 1 -name 'Finova-*.ips' -newer "$MARKER" 2>/dev/null | head -1)
    [ -n "$REPORT" ] && break
    sleep 2
done
if [ -n "$REPORT" ]; then
    cp "$REPORT" "$LOGS/"
    echo "--- Crash report: $(basename "$REPORT")"
    grep -m 5 -E '"(exception|termination|crashed|indicator)' "$REPORT" || head -c 2000 "$REPORT"
fi
exit 1
