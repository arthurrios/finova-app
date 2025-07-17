#!/bin/bash

# ci_post_xcodebuild.sh
# This script runs after Xcode Cloud completes the build
# It performs additional validations and cleanup

set -e

echo "🔍 Xcode Cloud: Post-build validations..."
echo "========================================="

# Check if build was successful
if [ "$CI_XCODEBUILD_EXIT_CODE" = "0" ]; then
  echo "✅ Build completed successfully!"

  # Optionally: Clean up derived data to save space
  echo "🧹 Cleaning up build artifacts..."
  rm -rf ~/Library/Developer/Xcode/DerivedData/*/Build/Intermediates.noindex

  echo "📊 Build statistics:"
  echo "   - Archive path: $CI_ARCHIVE_PATH"
  echo "   - Product path: $CI_PRODUCT_PATH"
  echo "   - Workflow: $CI_WORKFLOW"
  echo "   - Branch: $CI_BRANCH"

else
  echo "❌ Build failed with exit code: $CI_XCODEBUILD_EXIT_CODE"
  exit 1
fi

echo "🎉 Post-build validations completed!"
