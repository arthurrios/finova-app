# 🚀 CI/CD and Release Strategy Guide

## Overview

This document outlines the complete CI/CD and release strategy for Swift Finance App, including automated testing, semantic versioning, and deployment workflows.

## 📊 Current Version Strategy

- **Current Version**: `0.9.0` (Pre-1.0.0 development phase)
- **Next Release**: Will be `1.0.0` when ready for production
- **Beta Releases**: `0.9.x-beta.y` format for TestFlight distributions

## 🏗️ CI/CD Architecture

### Workflows

1. **🔍 PR Validation** (`.github/workflows/pr-validation.yml`)
   - Runs on every pull request
   - Fast feedback for code quality
   - Includes security scanning

2. **🚀 Main CI/CD Pipeline** (`.github/workflows/ci.yml`)
   - Runs on `main` and `develop` branches
   - Full testing, building, and semantic release
   - Creates GitHub releases automatically

3. **📱 TestFlight Deployment** (`.github/workflows/deploy-testflight.yml`)
   - Deploys beta versions to TestFlight
   - Triggered by pushes to `develop` branch

## 🔄 Branching Strategy

```
main (production) ←── Pull Requests ←── develop (beta) ←── feature branches
  ↓                                          ↓
Release to App Store                   Release to TestFlight
```

### Branch Workflow

1. **Feature Development**: Create feature branches from `develop`
2. **Beta Testing**: Merge to `develop` → Auto-deploy to TestFlight
3. **Production Release**: Create PR from `develop` to `main` → Auto-deploy to App Store

## 📝 Commit Convention

We use [Conventional Commits](https://conventionalcommits.org/) for automated versioning:

### Format
```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types and Version Impact

| Type | Description | Version Bump |
|------|-------------|--------------|
| `feat` | New feature | Minor |
| `fix` | Bug fix | Patch |
| `perf` | Performance improvement | Patch |
| `refactor` | Code refactoring | Patch |
| `style` | Code style changes | Patch |
| `docs` | Documentation | Patch |
| `test` | Test changes | No release |
| `chore` | Maintenance | No release |
| `ci` | CI/CD changes | No release |

### Breaking Changes
- Add `BREAKING CHANGE:` in footer → Major version bump
- Add `!` after type → Major version bump

### Examples

```bash
# Minor version bump (new features)
feat(auth): add biometric authentication
feat(dashboard): implement expense categorization

# Patch version bump (bug fixes)
fix(calculation): correct tax computation formula
fix(ui): resolve button alignment on iPad

# Major version bump (breaking changes)
feat(api)!: migrate to new backend API structure

BREAKING CHANGE: API endpoints have changed, requires app update
```

## 🔧 Local Development Setup

### 1. Initial Setup
```bash
# Clone the repository
git clone <your-repo-url>
cd swift-finance-app

# Run setup script
./scripts/setup.sh
```

### 2. Manual Configuration
1. Open `FinanceApp.xcworkspace` in Xcode
2. Select your development team
3. Update bundle identifier if needed
4. Update `ExportOptions.plist` with your Team ID

### 3. Git Hooks
Pre-commit hooks are automatically configured to:
- Run SwiftLint on staged files
- Enforce code quality standards

## 🤖 GitHub Actions Setup

### Required Secrets

Set these in your GitHub repository settings (`Settings > Secrets and variables > Actions`):

| Secret | Description | How to Get |
|--------|-------------|------------|
| `APP_STORE_CONNECT_API_KEY` | Base64 encoded .p8 key | [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/creating_api_keys_for_app_store_connect_api) |
| `APP_STORE_CONNECT_KEY_ID` | Key ID from App Store Connect | Same as above |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from App Store Connect | Same as above |
| `SLACK_WEBHOOK_URL` | (Optional) Slack notifications | [Slack Incoming Webhooks](https://api.slack.com/messaging/webhooks) |

### Setting up App Store Connect API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. Navigate to Users and Access > Keys
3. Create a new API key with "App Manager" role
4. Download the `.p8` file
5. Convert to base64: `base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy`
6. Add as `APP_STORE_CONNECT_API_KEY` secret

## 🚀 Release Process

### Automatic Releases (Recommended)

1. **Make Changes**: Use conventional commits
2. **Create PR**: From feature branch to `develop` or `main`
3. **Merge PR**: Triggers automated process
4. **Release**: Semantic release creates version and GitHub release

### Manual Release Triggers

```bash
# Trigger TestFlight deployment
git push origin develop

# Trigger production release (via PR to main)
gh pr create --base main --head develop --title "Release v1.0.0"
```

## 📱 Testing Strategy

### Unit Tests
- Run automatically in all workflows
- Required for PR approval
- Coverage reports uploaded to GitHub

### Integration Tests
- Included in main CI pipeline
- Test Firebase integration
- Database operations validation

### UI Tests (Future Enhancement)
- Planned for v1.1.0
- Will include critical user journey testing

## 🔍 Code Quality

### SwiftLint Rules
Configuration in `.swiftlint.yml`:
- Line length: 120 characters (warning), 150 (error)
- Function body length: 50 lines (warning), 100 (error)
- Cyclomatic complexity: 10 (warning), 15 (error)

### Security Scanning
- Trivy vulnerability scanner on all PRs
- SARIF upload to GitHub Security tab
- Dependency vulnerability alerts

## 📊 Monitoring and Notifications

### GitHub Actions Status
- All workflows report status to GitHub checks
- Failed builds block PR merging
- Artifact uploads for debugging

### Slack Notifications (Optional)
Configure `SLACK_WEBHOOK_URL` for:
- Successful TestFlight deployments
- Production releases
- Failed build notifications

## 🔧 Troubleshooting

### Common Issues

#### 1. SwiftLint Failures
```bash
# Fix automatically fixable issues
swiftlint autocorrect

# Check specific files
swiftlint lint path/to/file.swift
```

#### 2. CocoaPods Issues
```bash
# Clean and reinstall
rm -rf Pods/ Podfile.lock
pod install --repo-update
```

#### 3. Build Failures
```bash
# Clean build folder
rm -rf build/
xcodebuild clean -workspace FinanceApp.xcworkspace -scheme FinanceApp

# Reset derived data
rm -rf ~/Library/Developer/Xcode/DerivedData
```

#### 4. Semantic Release Issues
```bash
# Check commit message format
npx commitlint --from HEAD~1 --to HEAD --verbose

# Dry run semantic release
npx semantic-release --dry-run
```

### Getting Help

1. Check GitHub Actions logs for detailed error messages
2. Review SwiftLint output for code quality issues
3. Verify all required secrets are properly configured
4. Ensure Xcode project settings match CI configuration

## 🎯 Future Enhancements

### Phase 2 (v1.1.0)
- [ ] UI Testing integration
- [ ] Fastlane integration for advanced deployment
- [ ] Code coverage reporting
- [ ] Performance testing automation

### Phase 3 (v1.2.0)
- [ ] Multi-environment support (staging/production)
- [ ] Firebase App Distribution integration
- [ ] Automated App Store screenshots
- [ ] Release notes automation from JIRA/Linear

### Phase 4 (v2.0.0)
- [ ] Advanced monitoring and analytics
- [ ] A/B testing pipeline integration
- [ ] Automated security testing
- [ ] Multi-platform support (watchOS, macOS)

## 📚 Resources

- [Conventional Commits](https://conventionalcommits.org/)
- [Semantic Release](https://semantic-release.gitbook.io/)
- [GitHub Actions for iOS](https://github.com/actions/starter-workflows/tree/main/ci)
- [SwiftLint Rules](https://realm.github.io/SwiftLint/rule-directory.html)
- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)

---

**Last Updated**: December 2024  
**Version**: 1.0.0  
**Maintainer**: Development Team 