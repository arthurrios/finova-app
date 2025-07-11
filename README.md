# 📱 Swift Finance App

A comprehensive finance management app built with Swift and UIKit, featuring automated CI/CD, semantic versioning, and modern development practices.

## 🚀 Quick Start

```bash
# Clone the repository
git clone <your-repo-url>
cd swift-finance-app

# Setup development environment
./scripts/setup.sh

# Open in Xcode
open FinanceApp.xcworkspace
```

## 🏗️ Project Status

- **Current Version**: `0.9.0` (Pre-release)
- **Target Release**: `1.0.0` (Production ready)
- **iOS Deployment**: iOS 15.0+
- **Xcode**: Latest stable version
- **Swift**: 5.0+

## 📋 Features

### Current (v0.9.0)
- 🔐 Firebase Authentication
- 💾 SQLite Database Integration
- ✨ Modern UI with Shimmer Effects
- 📊 Financial Data Management
- 🔄 Background Sync Support

### Planned (v1.0.0)
- 📈 Advanced Analytics Dashboard
- 🔒 Biometric Authentication
- 📱 Widget Support
- 🌙 Dark Mode
- 💳 Multi-account Management

## 🛠️ Tech Stack

- **Language**: Swift 5.0+
- **UI Framework**: UIKit
- **Architecture**: MVC with Coordinator Pattern
- **Database**: SQLite (SQLite.swift)
- **Authentication**: Firebase Auth
- **UI Enhancements**: ShimmerView
- **Dependency Management**: CocoaPods
- **CI/CD**: GitHub Actions
- **Code Quality**: SwiftLint
- **Version Management**: Semantic Release

## 🔄 Development Workflow

### 1. Local Development
```bash
# Create feature branch
git checkout -b feature/expense-tracking

# Make changes with conventional commits
git commit -m "feat(tracking): add expense categorization"

# Push and create PR
git push origin feature/expense-tracking
gh pr create --base develop
```

### 2. Testing & Deployment
- **PR → develop**: Triggers TestFlight deployment
- **develop → main**: Triggers production release
- **All changes**: Automatically versioned using semantic release

### 3. Commit Convention
```bash
# Features (minor version bump)
feat(scope): description

# Bug fixes (patch version bump)
fix(scope): description

# Breaking changes (major version bump)
feat(scope)!: description
BREAKING CHANGE: explanation
```

## 🧪 Testing

```bash
# Run unit tests
xcodebuild test -workspace FinanceApp.xcworkspace -scheme FinanceApp -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'

# Run SwiftLint
swiftlint

# Fix SwiftLint issues
swiftlint autocorrect
```

## 📚 Documentation

- [🔄 Development Workflow](docs/DEVELOPMENT-WORKFLOW.md) - **START HERE** - Development without Apple Developer account
- [📖 CI/CD Guide](docs/CI-CD-GUIDE.md) - Complete CI/CD setup and workflow
- [🔧 Development Setup](docs/CI-CD-GUIDE.md#local-development-setup) - Local environment configuration
- [📝 Commit Convention](docs/CI-CD-GUIDE.md#commit-convention) - Semantic commit guidelines
- [🚀 Release Process](docs/CI-CD-GUIDE.md#release-process) - Automated release workflow

## 🏗️ Architecture

```
FinanceApp/
├── Sources/
│   ├── Core/              # Core functionality and utilities
│   └── Scenes/            # UI scenes and view controllers
├── Resources/             # Assets, fonts, and configuration files
├── FinanceAppTests/       # Unit and integration tests
├── .github/workflows/     # CI/CD pipeline definitions
├── scripts/               # Build and setup scripts
└── docs/                  # Project documentation
```

## 🔐 Security

- 🔒 Secure authentication with Firebase
- 🔐 API keys and sensitive data encrypted
- 🛡️ Automated security scanning in CI/CD
- 📱 iOS Keychain integration for secure storage

## 🤝 Contributing

1. **Fork** the repository
2. **Create** a feature branch from `develop`
3. **Follow** conventional commit format
4. **Add** tests for new functionality
5. **Ensure** SwiftLint passes
6. **Submit** a pull request

### Code Quality Standards
- SwiftLint compliance required
- Unit test coverage for new features
- Documentation for public APIs
- Conventional commit messages

## 🚀 Deployment

### TestFlight (Beta)
- Automatic deployment from `develop` branch
- Version format: `0.9.x-beta.y`
- Available for internal testing

### App Store (Production)
- Automatic deployment from `main` branch
- Semantic versioning based on commits
- Includes automated release notes

## 📊 CI/CD Pipeline

- ✅ Automated testing on all PRs
- 🔍 Code quality checks with SwiftLint
- 🔒 Security vulnerability scanning
- 📦 Semantic versioning and releases
- 📱 TestFlight and App Store deployment
- 📈 Build artifacts and test reports

## 🆘 Support

### Getting Help
- 📖 Check the [CI/CD Guide](docs/CI-CD-GUIDE.md) for detailed instructions
- 🐛 Open an issue for bugs or questions
- 💬 Use GitHub Discussions for general questions

### Common Issues
- **Build failures**: Check Xcode version and dependencies
- **SwiftLint errors**: Run `swiftlint autocorrect` for auto-fixes
- **CocoaPods issues**: Try `pod install --repo-update`

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Firebase team for authentication services
- SQLite.swift contributors for database integration
- GitHub Actions community for CI/CD templates
- iOS development community for best practices

---

**Maintainer**: Development Team  
**Last Updated**: December 2024  
**Version**: 0.9.0 