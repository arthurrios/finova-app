#!/bin/bash

# Setup script for Swift Finance App
# This script sets up the development environment

set -e

echo "🚀 Setting up Swift Finance App development environment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

# Check if we're in the right directory
if [ ! -f "Podfile" ] || [ ! -d "FinanceApp.xcodeproj" ]; then
  print_error "Please run this script from the project root directory"
  exit 1
fi

# Check for required tools
echo "🔍 Checking for required tools..."

# Check for Homebrew
if ! command -v brew &>/dev/null; then
  print_warning "Homebrew not found. Installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
print_status "Homebrew is available"

# Check for CocoaPods
if ! command -v pod &>/dev/null; then
  print_warning "CocoaPods not found. Installing..."
  gem install cocoapods
fi
print_status "CocoaPods is available"

# Check for SwiftLint
if ! command -v swiftlint &>/dev/null; then
  print_warning "SwiftLint not found. Installing..."
  brew install swiftlint
fi
print_status "SwiftLint is available"

# Check for Node.js (for semantic-release)
if ! command -v node &>/dev/null; then
  print_warning "Node.js not found. Installing..."
  brew install node
fi
print_status "Node.js is available"

# Install CocoaPods dependencies
echo "📦 Installing CocoaPods dependencies..."
pod install --repo-update
print_status "CocoaPods dependencies installed"

# Install npm dependencies for semantic-release
echo "📦 Installing npm dependencies..."
npm install
print_status "npm dependencies installed"

# Setup git hooks
echo "🪝 Setting up git hooks..."
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
print_status "Git hooks configured"

# Create necessary directories
echo "📁 Creating necessary directories..."
mkdir -p scripts
mkdir -p docs
print_status "Directories created"

# Setup initial git configuration for conventional commits
echo "⚙️  Configuring git for conventional commits..."
git config --local commit.template .gitmessage 2>/dev/null || true

# Create git message template
cat >.gitmessage <<EOF
# <type>(<scope>): <subject>
#
# <body>
#
# <footer>

# Type should be one of the following:
# * feat: A new feature
# * fix: A bug fix
# * docs: Documentation only changes
# * style: Changes that do not affect the meaning of the code
# * refactor: A code change that neither fixes a bug nor adds a feature
# * perf: A code change that improves performance
# * test: Adding missing tests or correcting existing tests
# * build: Changes that affect the build system or external dependencies
# * ci: Changes to our CI configuration files and scripts
# * chore: Other changes that don't modify src or test files
# * revert: Reverts a previous commit
EOF

print_status "Git message template created"

# Verify Xcode project
echo "🔨 Verifying Xcode project..."
if xcodebuild -list -workspace FinanceApp.xcworkspace &>/dev/null; then
  print_status "Xcode project is valid"
else
  print_error "Xcode project validation failed"
  exit 1
fi

# Run initial build to make sure everything works
echo "🏗️  Running initial build..."
xcodebuild -workspace FinanceApp.xcworkspace \
  -scheme FinanceApp \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  clean build >/dev/null

print_status "Initial build successful"

# Setup complete
echo ""
echo "🎉 Setup complete! You're ready to start developing."
echo ""
echo "📚 Next steps:"
echo "   1. Open FinanceApp.xcworkspace in Xcode"
echo "   2. Select your development team in project settings"
echo "   3. Update bundle identifier if needed"
echo "   4. Update ExportOptions.plist with your Team ID"
echo "   5. Set up GitHub repository secrets for CI/CD:"
echo "      - APP_STORE_CONNECT_API_KEY"
echo "      - APP_STORE_CONNECT_KEY_ID"
echo "      - APP_STORE_CONNECT_ISSUER_ID"
echo ""
echo "💡 Useful commands:"
echo "   - Run tests: xcodebuild test -workspace FinanceApp.xcworkspace -scheme FinanceApp -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'"
echo "   - Run SwiftLint: swiftlint"
echo "   - Fix SwiftLint issues: swiftlint autocorrect"
echo "   - Install pods: pod install"
echo ""
echo "📖 For more information, check the documentation in the docs/ folder."
