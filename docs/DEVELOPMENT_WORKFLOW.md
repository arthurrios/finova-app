# 🚀 Development Workflow - Trunk-Based with CI Issues

This guide helps you continue development with trunk-based flow while debugging CI build issues.

## 🔧 Quick Solutions

### Option 1: Use Permissive CI (Immediate Relief)

The new permissive CI workflow (`.github/workflows/develop-ci-permissive.yml`) allows you to:
- ✅ Continue merging to develop branch
- ✅ Get semantic versioning releases
- ✅ Run diagnostics in parallel
- ⚠️  Build issues won't block development

**To activate:** Simply push to develop - both workflows will run in parallel.

### Option 2: Local CI Testing

Use the local CI check script to debug issues locally:

```bash
# Run local CI check (mimics GitHub Actions)
./scripts/local-ci-check.sh
```

This will:
- Install dependencies
- Run SwiftLint
- Test build configuration
- Build for testing with detailed output
- Optionally run tests

### Option 3: Disable Original CI Temporarily

To completely bypass the strict CI while debugging:

```bash
# Rename the strict CI file to disable it
git mv .github/workflows/develop-ci.yml .github/workflows/develop-ci.yml.disabled
git commit -m "temp: disable strict CI for debugging"
git push origin develop
```

## 🔍 Debugging the Build Issue

### Step 1: Run Local Check
```bash
./scripts/local-ci-check.sh
```

### Step 2: Check Common Issues

1. **CocoaPods Issues:**
   ```bash
   pod deintegrate
   pod install --repo-update
   ```

2. **Xcode Version Mismatch:**
   - CI uses Xcode 16.2.0
   - Check your local version: `xcodebuild -version`

3. **Scheme Configuration:**
   ```bash
   xcodebuild -list -workspace FinanceApp.xcworkspace
   ```

4. **Simulator Issues:**
   ```bash
   # List available simulators
   xcrun simctl list devices iPhone
   
   # Reset simulator if needed
   xcrun simctl erase "iPhone 16"
   ```

### Step 3: Build with Verbose Output
```bash
xcodebuild -workspace FinanceApp.xcworkspace \
           -scheme FinanceApp \
           -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
           clean build-for-testing \
           -verbose
```

## 🚀 Continue Development

### Trunk-Based Flow with Permissive CI

1. **Make your changes** on feature branches or directly on develop
2. **Test locally** using the local CI script
3. **Push to develop** - permissive CI will run
4. **Get semantic releases** automatically
5. **Debug build issues** in parallel using CI artifacts

### When Build is Fixed

1. **Re-enable strict CI:**
   ```bash
   git mv .github/workflows/develop-ci.yml.disabled .github/workflows/develop-ci.yml
   ```

2. **Remove permissive CI:**
   ```bash
   git rm .github/workflows/develop-ci-permissive.yml
   ```

3. **Test everything works:**
   ```bash
   ./scripts/local-ci-check.sh
   ```

## 📋 Checklist for Each Development Cycle

- [ ] Run local CI check before pushing
- [ ] Check SwiftLint issues
- [ ] Verify build works locally with iPhone 16 simulator
- [ ] Push to develop
- [ ] Monitor CI artifacts for build diagnostics
- [ ] Continue development regardless of CI status

## 🆘 Emergency Bypass

If you need to merge urgently and CI is completely broken:

```bash
# Create temporary branch
git checkout -b emergency-merge
git push origin emergency-merge

# Create PR directly to main, bypassing develop CI
# (You'll need to configure branch protection rules to allow this)
```

## 📊 CI Status Overview

- **Strict CI**: Blocks development, requires all builds to pass
- **Permissive CI**: Allows development, provides diagnostics
- **Local CI**: Fastest feedback loop for debugging

Choose the approach that fits your current needs! 