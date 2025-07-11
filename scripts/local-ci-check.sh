#!/bin/bash

# Local CI Check Script
# This script mimics the CI environment for debugging build issues

set -e

echo "🚀 Starting Local CI Check..."
echo "================================"

# Configuration
XCODE_PROJECT="FinanceApp.xcworkspace"
SCHEME="FinanceApp"
DESTINATION="platform=iOS Simulator,name=iPhone 16,OS=latest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

# Function to check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "🔍 Checking prerequisites..."

if ! command_exists xcodebuild; then
  print_error "xcodebuild not found. Make sure Xcode is installed."
  exit 1
fi

if ! command_exists pod; then
  print_warning "CocoaPods not found. Installing..."
  gem install cocoapods
fi

if ! command_exists swiftlint; then
  print_warning "SwiftLint not found. Installing..."
  brew install swiftlint
fi

print_status "Prerequisites checked"

# Check workspace
echo ""
echo "📁 Checking workspace structure..."
if [[ ! -d "$XCODE_PROJECT" ]]; then
  print_error "Workspace not found: $XCODE_PROJECT"
  exit 1
fi

print_status "Workspace found: $XCODE_PROJECT"

# Install dependencies
echo ""
echo "📦 Installing dependencies..."
pod install --repo-update
print_status "Dependencies installed"

# Run SwiftLint
echo ""
echo "🧹 Running SwiftLint..."
if swiftlint lint; then
  print_status "SwiftLint passed"
else
  print_warning "SwiftLint found issues (continuing anyway)"
fi

# List available schemes
echo ""
echo "📋 Available schemes:"
xcodebuild -list -workspace "$XCODE_PROJECT"

# Check build settings
echo ""
echo "⚙️ Checking build settings..."
xcodebuild -workspace "$XCODE_PROJECT" \
  -scheme "$SCHEME" \
  -showBuildSettings | head -20

# Test build validation first
echo ""
echo "✅ Validating build configuration..."
if xcodebuild -workspace "$XCODE_PROJECT" \
  -scheme "$SCHEME" \
  -showBuildSettings >/dev/null; then
  print_status "Build configuration valid"
else
  print_error "Build configuration check failed"
  exit 1
fi

# Clean build
echo ""
echo "🧹 Cleaning build..."
xcodebuild -workspace "$XCODE_PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  clean

print_status "Build cleaned"

# Build for testing
echo ""
echo "🔨 Building for testing..."
if xcodebuild -workspace "$XCODE_PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  build-for-testing; then
  print_status "Build for testing succeeded! 🎉"
else
  print_error "Build for testing failed"
  echo ""
  echo "💡 Debug suggestions:"
  echo "1. Check the build output above for specific errors"
  echo "2. Try building in Xcode to see more detailed error messages"
  echo "3. Make sure all dependencies are properly configured"
  echo "4. Check for any scheme-specific settings"
  exit 1
fi

# Run tests (optional)
echo ""
read -p "🧪 Run tests now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Running tests..."
  if xcodebuild -workspace "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    test-without-building; then
    print_status "Tests passed! 🎉"
  else
    print_warning "Tests failed, but build was successful"
  fi
fi

echo ""
print_status "Local CI check completed!"
echo "🚀 You can now continue with trunk-based development"
