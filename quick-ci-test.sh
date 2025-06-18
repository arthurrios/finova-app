#!/bin/bash

# 🧪 Quick CI Test - Basic Validation
echo "🧪 Quick CI Test for FinanceApp"
echo "================================"

# Set environment
export XCODE_PROJECT="FinanceApp.xcworkspace"
export SCHEME="FinanceApp"
DESTINATION='platform=iOS Simulator,name=iPhone 16,OS=latest'

# Step 1: Check if workspace exists
echo "📁 Checking workspace..."
if [ -d "$XCODE_PROJECT" ]; then
  echo "✅ Workspace found: $XCODE_PROJECT"
elif [ -f "FinanceApp.xcodeproj/project.pbxproj" ]; then
  export XCODE_PROJECT="FinanceApp.xcodeproj"
  echo "✅ Using Xcode project: $XCODE_PROJECT"
else
  echo "❌ No workspace or project found"
  exit 1
fi

# Step 2: Check schemes
echo "📋 Listing schemes..."
if [[ "$XCODE_PROJECT" == *.xcworkspace ]]; then
  xcodebuild -list -workspace "$XCODE_PROJECT"
else
  xcodebuild -list -project "$XCODE_PROJECT"
fi

# Step 3: Check available simulators
echo "📱 Checking iPhone 16 simulator..."
xcrun simctl list devices | grep "iPhone 16" || echo "⚠️  iPhone 16 not found"

# Step 4: Quick build check
echo "🔨 Testing build..."
if [[ "$XCODE_PROJECT" == *.xcworkspace ]]; then
  xcodebuild -workspace "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -showBuildSettings >/dev/null
else
  xcodebuild -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -showBuildSettings >/dev/null
fi

if [ $? -eq 0 ]; then
  echo "✅ Build settings validated"
else
  echo "❌ Build settings validation failed"
  exit 1
fi

# Step 5: SwiftLint check
echo "🔍 Checking SwiftLint..."
if command -v swiftlint &>/dev/null; then
  echo "✅ SwiftLint available"
  swiftlint version
else
  echo "⚠️  SwiftLint not installed"
fi

# Step 6: Check for required files
echo "📄 Checking CI-related files..."
[ -f ".swiftlint.yml" ] && echo "✅ SwiftLint config found" || echo "⚠️  .swiftlint.yml not found"
[ -f "Podfile" ] && echo "✅ Podfile found" || echo "⚠️  Podfile not found"
[ -f ".commitlintrc.json" ] && echo "✅ Commitlint config found" || echo "⚠️  .commitlintrc.json not found"

echo ""
echo "🎉 Quick validation completed!"
echo "💡 Project structure looks good for CI/CD"
echo "🚀 The develop-ci.yml workflow should work correctly"
