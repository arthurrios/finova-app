#!/bin/sh

# Xcode Cloud post-clone: install the CocoaPods dependencies.
#
# `Pods/` is gitignored, so a fresh clone has no `Pods/Target Support Files/*.xcconfig`
# and every Pods target fails with "Unable to open base configuration reference file".
# Some of Pods/ is committed despite the ignore rule — 456 of 1100 files, from an
# accidental `git add -f` at some point — which is why local builds work and Cloud's
# clone does not. Rather than commit the remaining 644, generate them here from the
# Podfile.lock, which IS tracked and pins every version.
#
# Runs from ci_scripts/, so step up to the repo before installing.

set -e

echo "--- Installing CocoaPods"
if ! command -v pod >/dev/null 2>&1; then
    brew install cocoapods
fi
pod --version

echo "--- pod install"
cd "$CI_PRIMARY_REPOSITORY_PATH"
pod install --repo-update

echo "--- Sanity check: the xcconfig Cloud needs must now exist"
test -f "Pods/Target Support Files/Pods-Finova/Pods-Finova.release.xcconfig" \
    || { echo "Pods-Finova.release.xcconfig still missing after pod install"; exit 1; }
echo "OK"
