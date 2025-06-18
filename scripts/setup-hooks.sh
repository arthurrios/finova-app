#!/bin/bash

# Setup Git Hooks for Swift Finance App
# This script configures git to use the custom pre-commit hook

echo "🪝 Setting up git hooks..."

# Make sure the pre-commit hook is executable
chmod +x .githooks/pre-commit

# Configure git to use our custom hooks directory
git config core.hooksPath .githooks

echo "✅ Git hooks configured successfully!"
echo ""
echo "🔧 What happens now on every commit:"
echo "   1. SwiftLint auto-fixes issues automatically"
echo "   2. Fixed files are re-staged for commit"
echo "   3. Remaining issues (if any) will block the commit"
echo "   4. You'll see exactly what needs manual fixing"
echo ""
echo "💡 To test it, try making a commit:"
echo "   git add ."
echo "   git commit -m \"feat: test commit with auto-linting\""
