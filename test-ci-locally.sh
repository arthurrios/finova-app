#!/bin/bash

# 🧪 Local CI Test Script
# This script simulates the GitHub Actions workflow locally

set -e # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Environment variables (matching CI)
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export XCODE_PROJECT="FinanceApp.xcworkspace"
export SCHEME="FinanceApp"
DESTINATION='platform=iOS Simulator,name=iPhone 16,OS=latest'

echo -e "${BLUE}🧪 Starting Local CI Test for FinanceApp${NC}"
echo "================================================="

# Function to print step headers
print_step() {
  echo -e "\n${YELLOW}🔄 $1${NC}"
  echo "-------------------------------------------"
}

# Function to check if command exists
check_command() {
  if ! command -v $1 &>/dev/null; then
    echo -e "${RED}❌ $1 is not installed${NC}"
    return 1
  fi
  echo -e "${GREEN}✅ $1 is available${NC}"
}

# Function to run step with error handling
run_step() {
  local step_name="$1"
  shift
  echo -e "${BLUE}Running: $@${NC}"

  if "$@"; then
    echo -e "${GREEN}✅ $step_name completed successfully${NC}"
    return 0
  else
    echo -e "${RED}❌ $step_name failed${NC}"
    return 1
  fi
}

# Step 1: Check prerequisites
print_step "Checking Prerequisites"
check_command "xcodebuild" || exit 1
check_command "pod" || echo -e "${YELLOW}⚠️  CocoaPods not found - will try to install${NC}"
check_command "swiftlint" || echo -e "${YELLOW}⚠️  SwiftLint not found - will try to install${NC}"

# Step 2: Install dependencies
print_step "Installing Dependencies"

# Install CocoaPods if needed
if ! command -v pod &>/dev/null; then
  echo "Installing CocoaPods..."
  run_step "CocoaPods Installation" gem install cocoapods
fi

# Install SwiftLint if needed
if ! command -v swiftlint &>/dev/null; then
  echo "Installing SwiftLint..."
  if command -v brew &>/dev/null; then
    run_step "SwiftLint Installation" brew install swiftlint
  else
    echo -e "${RED}❌ Homebrew not found. Please install SwiftLint manually${NC}"
    exit 1
  fi
fi

# Install pod dependencies
if [ -f "Podfile" ]; then
  run_step "Pod Install" pod install --repo-update
else
  echo -e "${YELLOW}⚠️  No Podfile found, skipping pod install${NC}"
fi

# Step 3: Check workspace/project exists
print_step "Validating Project Structure"
if [ ! -f "$XCODE_PROJECT" ]; then
  echo -e "${RED}❌ Workspace $XCODE_PROJECT not found${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Workspace found: $XCODE_PROJECT${NC}"

# Step 4: List available schemes and destinations
print_step "Listing Project Information"
run_step "List Schemes" xcodebuild -list -workspace "$XCODE_PROJECT"

echo -e "\n${BLUE}Available iOS Simulators:${NC}"
xcrun simctl list devices iOS | grep iPhone || echo "No iPhone simulators found"

# Step 5: Run SwiftLint
print_step "Running SwiftLint"
if [ -f ".swiftlint.yml" ]; then
  run_step "SwiftLint" swiftlint lint --reporter github-actions-logging
else
  echo -e "${YELLOW}⚠️  No .swiftlint.yml found, running with default config${NC}"
  swiftlint lint || echo -e "${YELLOW}⚠️  SwiftLint found issues but continuing...${NC}"
fi

# Step 6: Check build settings
print_step "Validating Build Settings"
run_step "Build Settings Check" xcodebuild -workspace "$XCODE_PROJECT" \
  -scheme "$SCHEME" \
  -showBuildSettings | head -20

# Step 7: Clean and build for testing
print_step "Building for Testing"
run_step "Build for Testing" xcodebuild -workspace "$XCODE_PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  clean build-for-testing

# Step 8: Run tests
print_step "Running Unit Tests"
run_step "Unit Tests" xcodebuild -workspace "$XCODE_PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  test \
  -resultBundlePath TestResults.xcresult

# Step 9: Build for release (verification)
print_step "Release Build Verification"
run_step "Release Build" xcodebuild -workspace "$XCODE_PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -configuration Release \
  clean build

# Step 10: Check for test results
print_step "Checking Test Results"
if [ -d "TestResults.xcresult" ]; then
  echo -e "${GREEN}✅ Test results generated successfully${NC}"
  echo "📊 Test results location: TestResults.xcresult"

  # Try to extract basic test info
  if command -v xcparse &>/dev/null; then
    echo "📈 Extracting test summary..."
    xcparse summary TestResults.xcresult
  else
    echo -e "${YELLOW}💡 Install xcparse for detailed test analysis: 'brew install chargepoint/xcparse/xcparse'${NC}"
  fi
else
  echo -e "${YELLOW}⚠️  No test results found${NC}"
fi

# Final summary
echo -e "\n${GREEN}🎉 Local CI Test Completed Successfully!${NC}"
echo "================================================="
echo -e "${GREEN}✅ All workflow steps passed${NC}"
echo -e "${BLUE}📱 Project is ready for CI/CD pipeline${NC}"
echo -e "${YELLOW}💡 You can now safely push to trigger the GitHub Actions workflow${NC}"

# Optional: Open test results
if [ -d "TestResults.xcresult" ] && command -v open &>/dev/null; then
  echo -e "\n${BLUE}🔍 Opening test results...${NC}"
  open TestResults.xcresult
fi
