#!/bin/bash
# Build a signed Android release bundle from secrets and check what came out.
#
# google-services.json, keystore.properties and the upload key are not in git. A release build
# without them used to succeed quietly (unsigned, Firebase off). The Gradle guard in
# android/app/build.gradle.kts now refuses that build; this script supplies the files from CI
# secrets, builds, and then checks the bundle itself:
#   - it is signed with the upload key from the secret (not a debug key, not unsigned);
#   - it carries the Firebase config (google_app_id resource).
#
# Required environment (GitHub repository secrets):
#   GOOGLE_SERVICES_JSON_BASE64      base64 of android/app/google-services.json
#   ANDROID_UPLOAD_KEYSTORE_BASE64   base64 of the upload keystore (.jks)
#   ANDROID_KEYSTORE_PASSWORD        storePassword
#   ANDROID_KEY_ALIAS                keyAlias
#   ANDROID_KEY_PASSWORD             keyPassword
#
# Runs from anywhere. On a developer Mac (CI not set) it refuses to overwrite existing key files.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
ANDROID="$REPO/android"
PACKAGE="com.arthurrios.finova"

missing=()
for v in GOOGLE_SERVICES_JSON_BASE64 ANDROID_UPLOAD_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD; do
    [ -n "${!v:-}" ] || missing+=("$v")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "::error::Missing secrets: ${missing[*]}. See docs/release-checklist.md."
    exit 1
fi

if [ "${CI:-}" != "true" ]; then
    for f in "$ANDROID/app/google-services.json" "$ANDROID/keystore.properties"; do
        if [ -e "$f" ]; then
            echo "Refusing to overwrite $f outside CI. Run this in a clean checkout."
            exit 1
        fi
    done
fi

WORK="$(mktemp -d)"
cleanup() {
    rm -rf "$WORK"
    rm -f "$ANDROID/keystore.properties" "$ANDROID/app/google-services.json"
}
trap cleanup EXIT

echo "--- Restoring google-services.json"
echo "$GOOGLE_SERVICES_JSON_BASE64" | base64 --decode > "$ANDROID/app/google-services.json"
python3 - "$ANDROID/app/google-services.json" "$PACKAGE" <<'EOF'
import json, sys
path, package = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path))
except Exception as e:
    sys.exit(f"::error::google-services.json is not valid JSON ({e}). Check GOOGLE_SERVICES_JSON_BASE64.")
names = [c.get("client_info", {}).get("android_client_info", {}).get("package_name") for c in data.get("client", [])]
if package not in names:
    sys.exit(f"::error::google-services.json has no client for {package} (found {names}).")
print(f"OK: project {data.get('project_info', {}).get('project_id')}, client {package}")
EOF

echo "--- Restoring the upload key"
KEYSTORE="$WORK/upload.jks"
echo "$ANDROID_UPLOAD_KEYSTORE_BASE64" | base64 --decode > "$KEYSTORE"
cat > "$ANDROID/keystore.properties" <<EOF
storeFile=$KEYSTORE
storePassword=$ANDROID_KEYSTORE_PASSWORD
keyAlias=$ANDROID_KEY_ALIAS
keyPassword=$ANDROID_KEY_PASSWORD
EOF
# Fails here, with a clear message, if the password or alias secret is wrong.
EXPECTED_SHA256=$(keytool -list -v -keystore "$KEYSTORE" -storepass "$ANDROID_KEYSTORE_PASSWORD" -alias "$ANDROID_KEY_ALIAS" 2>/dev/null \
    | awk '/SHA256:/ {print $2; exit}') || true
if [ -z "$EXPECTED_SHA256" ]; then
    echo "::error::Cannot open the upload keystore with ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS."
    exit 1
fi

echo "--- bundleRelease"
cd "$ANDROID"
./gradlew --no-daemon :app:bundleRelease

AAB="$ANDROID/app/build/outputs/bundle/release/app-release.aab"
[ -f "$AAB" ] || { echo "::error::$AAB was not produced"; exit 1; }

echo "--- Checking the bundle"
ACTUAL_SHA256=$(keytool -printcert -jarfile "$AAB" 2>/dev/null | awk '/SHA256:/ {print $2; exit}')
if [ -z "$ACTUAL_SHA256" ]; then
    echo "::error::The release bundle is not signed."
    exit 1
fi
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    echo "::error::The release bundle is signed with a different key ($ACTUAL_SHA256), not the upload key."
    exit 1
fi
echo "OK: signed with the upload key"

# Count, not grep -q: with pipefail, grep -q exiting early makes unzip fail on SIGPIPE.
if [ "$(unzip -p "$AAB" base/resources.pb | grep -ac google_app_id || true)" = "0" ]; then
    echo "::error::The release bundle has no google_app_id: the Firebase config did not make it in."
    exit 1
fi
echo "OK: Firebase config is in the bundle"

ls -l "$AAB"
