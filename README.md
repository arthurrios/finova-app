# 📱 Swift Finance App

A comprehensive personal finance management app built with Swift and UIKit, featuring secure local data storage, user authentication, and modern development practices.

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

- **Current Version**: Active Development
- **iOS Deployment**: iOS 15.0+
- **Xcode**: 16.2.0+
- **Swift**: 5.0+

## 📋 Features

- 🔐 **User Authentication** - Firebase Authentication with Google Sign-In
- 💾 **Local Data Storage** - Secure SQLite database with encryption
- 💰 **Transaction Management** - Add, edit, and categorize income/expenses
- 🔄 **Recurring Transactions** - Automated recurring transaction handling
- 📊 **Budget Tracking** - Budget creation and expense monitoring
- 🎨 **Modern UI** - Clean interface with shimmer effects and animations
- 📱 **Dashboard** - Financial overview with monthly summaries
- 🛡️ **Data Privacy** - All financial data stored locally, never in cloud

## 🛠️ Tech Stack

- **Language**: Swift 5.0+
- **UI Framework**: UIKit with programmatic UI
- **Architecture**: MVC with Flow Coordinator Pattern
- **Database**: SQLite with secure local encryption
- **Authentication**: Firebase Authentication
- **UI Enhancements**: Custom animations and shimmer effects
- **Dependency Management**: CocoaPods
- **CI/CD**: GitHub Actions + Xcode Cloud
- **Code Quality**: SwiftLint
- **Testing**: XCTest with iPhone 16 simulator

## 🔄 Development Workflow

### 1. Local Development
```bash
# Create feature branch from develop
git checkout -b feature/expense-tracking

# Make changes with conventional commits
git commit -m "feat(tracking): add expense categorization"

# Push and create PR
git push origin feature/expense-tracking
```

### 2. Commit Convention
```bash
# Features
feat(scope): description

# Bug fixes
fix(scope): description

# Breaking changes
feat(scope)!: description
```

## 🧪 Testing

```bash
# Run unit tests (using iPhone 16 simulator)
xcodebuild test -workspace FinanceApp.xcworkspace -scheme FinanceApp -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'

# Run SwiftLint
swiftlint

# Fix SwiftLint issues automatically
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
│   │   ├── Components/    # Reusable UI components
│   │   ├── Database/      # SQLite and data management
│   │   ├── Models/        # Data models and entities
│   │   ├── Repositories/  # Data access layer
│   │   └── Utils/         # Utility classes and extensions
│   └── Scenes/            # UI scenes and view controllers
├── Resources/             # Assets, fonts, and configuration files
├── FinanceAppTests/       # Unit and integration tests
├── .github/workflows/     # CI/CD pipeline definitions
├── scripts/               # Build and setup scripts
└── docs/                  # Project documentation
```

## 🔐 Security & Privacy

- 🔒 Firebase Authentication for secure user login
- 💾 All financial data stored locally in encrypted SQLite database
- 🔐 No sensitive financial data sent to cloud servers
- 🛡️ Automated security scanning in CI pipeline
- 📱 Privacy-first architecture design

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

## 📊 CI/CD Pipeline

- ✅ Automated testing on pull requests
- 🔍 Code quality checks with SwiftLint
- 🔒 Security vulnerability scanning with Trivy
- 📦 Semantic versioning for releases
- 📈 Build artifacts and test reports
- 🚀 Hybrid approach: GitHub Actions + Xcode Cloud

## 🆘 Support

### Getting Help
- 📖 Check the documentation in the `docs/` folder
- 🐛 Open an issue for bugs or feature requests
- 💬 Review the development workflow guide

### Common Issues
- **Build failures**: Ensure Xcode 16.2.0+ and run `pod install`
- **SwiftLint errors**: Run `swiftlint autocorrect` for auto-fixes
- **CocoaPods issues**: Try `pod install --repo-update`
- **Simulator issues**: Use iPhone 16 simulator for testing

## 📄 License

This project is licensed under the MIT License.

## 🙏 Acknowledgments

- Firebase team for authentication services
- SQLite.swift contributors for database integration
- iOS development community for best practices
- Open source contributors for inspiration

---

**Status**: Paused Development  
**Last Updated**: July 2025 