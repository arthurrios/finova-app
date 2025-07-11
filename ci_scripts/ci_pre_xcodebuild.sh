#!/bin/bash

# ci_pre_xcodebuild.sh
# This script runs before Xcode Cloud starts building
# It performs code quality checks

set -e

echo "🧹 Xcode Cloud: Pre-build code quality checks..."
echo "==============================================="

# Ensure SwiftLint is available and run it
if command -v swiftlint >/dev/null 2>&1; then
  echo "✅ SwiftLint found, running analysis..."
  swiftlint lint --reporter xcode
  echo "✅ SwiftLint analysis completed"
else
  echo "⚠️  SwiftLint not found, skipping code quality check"
fi

echo "🎯 Pre-build checks completed!"
