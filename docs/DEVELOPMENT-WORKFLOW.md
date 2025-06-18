# 🔄 Development Workflow (No Apple Developer Account Required)

This guide explains how to use the CI/CD setup for development and semantic versioning without needing a paid Apple Developer account.

## 🎯 **Current Setup Overview**

Since you don't have a paid Apple Developer account yet, the workflows have been configured to:

✅ **What Works (Simulator Only)**:
- Semantic versioning based on conventional commits
- Automated testing on simulator
- Code quality checks with SwiftLint
- Security scanning
- GitHub releases with changelogs
- Build verification (simulator builds only)

❌ **What's Disabled**:
- TestFlight deployment (requires paid account)
- Device builds and archiving
- App Store Connect uploads

## 🚀 **Perfect Trunk-Based Development Workflow**

### **Setup: Initialize Your Development**

```bash
# 1. Start from develop branch (your main development branch)
git checkout develop
git pull origin develop

# 2. Create feature branches from develop
git checkout -b feat/expense-tracking
```

### **Daily Development Cycle**

#### **1. Make Changes with Conventional Commits**
```bash
# Add a new feature (minor version bump)
git add .
git commit -m "feat(dashboard): add expense categorization with icons"

# Fix a bug (patch version bump)  
git add .
git commit -m "fix(ui): resolve button alignment issue on iPad"

# Performance improvement (patch version bump)
git add .
git commit -m "perf(database): optimize SQLite query performance"

# Breaking change (major version bump - when you're ready for 1.0.0)
git add .
git commit -m "feat(api)!: migrate to new data structure

BREAKING CHANGE: Database schema has changed, requires data migration"
```

#### **2. Push and Create PR**
```bash
# Push feature branch
git push origin feat/expense-tracking

# Create PR to develop (not main!)
gh pr create --base develop --title "feat: expense tracking improvements"
```

#### **3. Automatic Workflow Triggers**
When you push to `develop` branch:

1. **🧪 Testing**: Runs all unit tests on simulator
2. **🔍 Linting**: SwiftLint code quality checks
3. **📦 Semantic Versioning**: Automatically calculates new version
4. **🏗️ Build Verification**: Confirms release build works (simulator)
5. **📝 GitHub Release**: Creates release with changelog

## 📊 **Version Strategy Without Apple Developer Account**

### **Current Approach (Perfect for Development)**

| Branch | Version Pattern | Triggers | Purpose |
|--------|----------------|----------|---------|
| `develop` | `0.9.x`, `0.10.x`, etc. | Push to develop | Development versions |
| `main` | `1.0.0+` | PR merge to main | Production-ready |

### **Example Version Progression**
```bash
# Starting version (package.json)
0.9.0

# After feat commit to develop
feat(auth): add biometric login
→ Version: 0.10.0

# After fix commit to develop  
fix(ui): resolve text alignment
→ Version: 0.10.1

# After another feat commit
feat(dashboard): add spending analytics
→ Version: 0.11.0

# When ready for production (PR to main)
BREAKING CHANGE: new API structure
→ Version: 1.0.0
```

## 🎮 **Complete Development Workflow Example**

### **Week 1-3: Feature Development**
```bash
# Start new feature
git checkout develop
git pull origin develop
git checkout -b feat/expense-analytics

# Daily commits with semantic format
git commit -m "feat(analytics): add spending breakdown chart"
git commit -m "feat(analytics): implement category filtering"
git commit -m "fix(analytics): correct percentage calculations"
git commit -m "test(analytics): add unit tests for chart data"

# Push and PR to develop
git push origin feat/expense-analytics
gh pr create --base develop

# After PR merge, automatic versioning happens:
# 0.9.0 → 0.10.0 (new features added)
```

### **Week 4: Bug Fixes and Polish**
```bash
# Work directly on develop or feature branches
git checkout develop
git pull origin develop

git commit -m "fix(ui): resolve dark mode color issues"
git commit -m "perf(database): optimize query performance"
git commit -m "fix(analytics): handle edge case with empty data"

# Each push to develop auto-versions:
# 0.10.0 → 0.10.1 → 0.10.2 → 0.10.3
```

### **When Ready for 1.0.0 (Future with Apple Developer Account)**
```bash
# Create PR from develop to main
gh pr create --base main --head develop --title "Release v1.0.0"

# After merge, triggers production pipeline (when you have Apple Developer account)
```

## 🔧 **Local Development Tips**

### **Check Your Commit Before Pushing**
```bash
# Preview what version would be bumped
npx semantic-release --dry-run

# Check commit message format
npx commitlint --from HEAD~1 --to HEAD --verbose

# Run local checks (like CI)
swiftlint
pod install
xcodebuild test -workspace FinanceApp.xcworkspace -scheme FinanceApp -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'
```

### **Track Your Versions**
```bash
# Check current version
grep '"version"' package.json

# See version history
git tag --sort=-version:refname

# View releases on GitHub
gh release list
```

## 📱 **Testing Your Builds**

Since you can't deploy to TestFlight yet, here's how to test:

### **Simulator Testing**
```bash
# Build and run in simulator (what CI does)
xcodebuild -workspace FinanceApp.xcworkspace \
           -scheme FinanceApp \
           -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
           clean build
```

### **Device Testing (Personal Development)**
1. Open `FinanceApp.xcworkspace` in Xcode
2. Select your personal development team
3. Connect your device via USB
4. Build and run directly to your device for testing

## 🎯 **Benefits of This Approach**

### **✅ What You Get Right Now**
- 🔄 **Semantic Versioning**: Professional version management
- 📝 **Automated Changelogs**: Generated from your commits  
- 🧪 **Continuous Testing**: Every push runs full test suite
- 🔍 **Code Quality**: SwiftLint ensures consistent code style
- 📊 **Build Verification**: Confirms each version builds successfully
- 🏷️ **GitHub Releases**: Professional release management

### **🚀 Future Ready**
When you get Apple Developer account:
1. Uncomment TestFlight deployment workflow
2. Add your App Store Connect API keys
3. Everything else works immediately!

## 🔥 **Pro Tips for Trunk-Based Development**

### **1. Commit Often with Small Changes**
```bash
# Instead of one big commit
git commit -m "feat(dashboard): implement complete expense tracking system"

# Break it down
git commit -m "feat(dashboard): add expense input form"
git commit -m "feat(dashboard): implement expense validation"
git commit -m "feat(dashboard): add expense list display"
git commit -m "feat(dashboard): integrate with SQLite storage"
```

### **2. Use Feature Flags for Large Features**
```swift
// In your code
if AppConfig.isExpenseAnalyticsEnabled {
    // New feature code
}
```

### **3. Merge to Develop Frequently**
- Don't let feature branches live more than 2-3 days
- Merge to develop multiple times per day if possible
- Keep develop branch always deployable

### **4. Use Descriptive Scopes**
```bash
git commit -m "feat(auth): add biometric authentication"
git commit -m "fix(dashboard): resolve memory leak in chart view"
git commit -m "perf(database): optimize transaction queries"
```

## 🚨 **Common Issues & Solutions**

### **"Semantic Release Didn't Create a Version"**
**Cause**: No conventional commits found
**Solution**: 
```bash
# Check recent commits
git log --oneline -5

# Make sure you're using conventional format
git commit -m "feat(scope): description"  # ✅ Correct
git commit -m "Added new feature"         # ❌ Wrong
```

### **"Build Failed in CI"**
**Cause**: Usually SwiftLint or test failures
**Solution**:
```bash
# Run locally first
swiftlint lint
swiftlint autocorrect  # Fix auto-fixable issues
xcodebuild test -workspace FinanceApp.xcworkspace -scheme FinanceApp -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'
```

### **"Version Didn't Bump as Expected"**
**Cause**: Commit type doesn't trigger version bump
**Solution**: Check your commit types:
- `feat:` → minor bump
- `fix:` → patch bump  
- `BREAKING CHANGE:` → major bump
- `chore:`, `docs:`, `test:` → no version bump

## 🎉 **You're All Set!**

This setup gives you a professional development workflow with:
- ✅ Semantic versioning working perfectly
- ✅ Trunk-based development on `develop` branch
- ✅ No Apple Developer account required
- ✅ Professional CI/CD pipeline
- ✅ Future-ready for when you get Apple Developer account

**Happy coding! 🚀** 