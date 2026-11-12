#!/bin/bash
# Write Finova/GoogleService-Info.plist from the GOOGLE_SERVICE_INFO_PLIST_BASE64 secret.
# Same secret, same checks as ci_scripts/ci_post_clone.sh (Xcode Cloud), for GitHub Actions.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$REPO/Finova/GoogleService-Info.plist"

if [ -z "${GOOGLE_SERVICE_INFO_PLIST_BASE64:-}" ]; then
    echo "::error::GOOGLE_SERVICE_INFO_PLIST_BASE64 is not set. Add it as a GitHub repository secret (docs/release-checklist.md)."
    exit 1
fi
if [ -e "$DEST" ] && [ "${CI:-}" != "true" ]; then
    echo "Keeping the existing $DEST (not in CI)."
    exit 0
fi

echo "$GOOGLE_SERVICE_INFO_PLIST_BASE64" | base64 --decode > "$DEST"
plutil -lint "$DEST" >/dev/null || { echo "::error::Decoded GoogleService-Info.plist is not a valid plist"; exit 1; }
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print BUNDLE_ID" "$DEST" 2>/dev/null || echo "?")
echo "OK: GoogleService-Info.plist for $BUNDLE_ID ($(wc -c < "$DEST" | tr -d ' ') bytes)"
