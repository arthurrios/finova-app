#!/bin/bash

# ci_post_clone.sh
# This script runs on Xcode Cloud after the repository is cloned
# It installs CocoaPods dependencies before building

set -e

echo "🚀 Xcode Cloud: Installing dependencies..."
echo "=========================================="

# Install CocoaPods if not available
if ! command -v pod &>/dev/null; then
  echo "📦 Installing CocoaPods..."
  gem install cocoapods
fi

# Install dependencies
echo "📥 Installing Pod dependencies..."
pod install --repo-update

echo "✅ Dependencies installed successfully!"

# Optional: Install SwiftLint for code quality
if ! command -v swiftlint &>/dev/null; then
  echo "🧹 Installing SwiftLint..."
  brew install swiftlint
fi

echo "🎉 Xcode Cloud setup complete!"
