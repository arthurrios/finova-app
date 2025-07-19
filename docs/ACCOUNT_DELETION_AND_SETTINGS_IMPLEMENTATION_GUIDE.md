# 🛡️ Account Deletion & Settings Implementation Guide

## Overview
This comprehensive guide details how to implement a user-facing Account Deletion feature (per App Store Guideline 5.1.1(v)) and create a complete Settings screen with Face ID/Touch ID toggle, app version display, and account deletion. All implementations use UIKit and align with your app's local-first, privacy-centric architecture and existing design system.

---

## Table of Contents
1. [Settings Screen Creation](#settings-screen-creation)
    - View Controller Setup  
    - View Implementation
    - Navigation Integration
2. [Feature Implementations](#feature-implementations)
    - Face ID/Touch ID Toggle
    - Account Deletion
    - App Version Display
3. [Dashboard Integration](#dashboard-integration)
    - Adding Settings Button
    - Navigation Flow
4. [UserDefaults Extensions](#userdefaults-extensions)
5. [Testing & Validation](#testing--validation)
6. [References](#references)

---

## Settings Screen Creation

### 1. Create SettingsViewModel

Create `Finova/Sources/Scenes/Settings/SettingsViewModel.swift`:

```swift
//
//  SettingsViewModel.swift
//  Finova
//
//  Created by User on [Date]
//

import Foundation
import UIKit
import FirebaseAuth
import LocalAuthentication

protocol SettingsViewModelDelegate: AnyObject {
    func didUpdateBiometricUI(isEnabled: Bool, isAvailable: Bool, biometricType: String)
    func didUpdateAppVersion(_ version: String)
    func didEncounterBiometricError(title: String, message: String)
    func didRequestReAuthentication()
    func didCompleteAccountDeletion()
    func didFailAccountDeletion(title: String, message: String)
    func shouldShowLoading(_ show: Bool, message: String?)
}

final class SettingsViewModel {
    
    weak var delegate: SettingsViewModelDelegate?
    
    // MARK: - Properties
    
    var isBiometricEnabled: Bool {
        get { UserDefaultsManager.getBiometricEnabled() }
        set { UserDefaultsManager.setBiometricEnabled(newValue) }
    }
    
    var biometricTypeString: String {
        return FaceIDManager.shared.biometricTypeString
    }
    
    var isBiometricAvailable: Bool {
        return FaceIDManager.shared.isFaceIDAvailable
    }
    
    var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    
    // MARK: - Initialization
    
    init() {
        configureInitialSettings()
    }
    
    // MARK: - Configuration
    
    private func configureInitialSettings() {
        updateBiometricUI()
        delegate?.didUpdateAppVersion(appVersionString)
    }
    
    private func updateBiometricUI() {
        let isAvailable = isBiometricAvailable
        
        if !isAvailable {
            isBiometricEnabled = false
        }
        
        delegate?.didUpdateBiometricUI(
            isEnabled: isBiometricEnabled,
            isAvailable: isAvailable,
            biometricType: biometricTypeString
        )
    }
    
    // MARK: - Biometric Management
    
    func toggleBiometric(_ isEnabled: Bool) {
        if isEnabled {
            enableBiometric()
        } else {
            disableBiometric()
        }
    }
    
    private func enableBiometric() {
        FaceIDManager.shared.authenticateWithBiometrics(
            reason: "settings.biometric.enable.reason".localized
        ) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.isBiometricEnabled = true
                    FaceIDManager.shared.enableFaceIDForCurrentUser()
                    print("✅ Biometric authentication enabled")
                } else {
                    if let error = error {
                        self?.delegate?.didEncounterBiometricError(
                            title: "settings.biometric.error.title".localized,
                            message: FaceIDManager.shared.getFriendlyErrorMessage(for: error)
                        )
                    }
                }
            }
        }
    }
    
    private func disableBiometric() {
        isBiometricEnabled = false
        FaceIDManager.shared.disableFaceIDForCurrentUser()
        print("✅ Biometric authentication disabled")
    }
    
    // MARK: - Account Deletion
    
    func deleteAccount() {
        delegate?.shouldShowLoading(true, message: "settings.delete.account.processing".localized)
        
        // Step 1: Clear only current user's data (preserves other users' data)
        clearCurrentUserDataForDeletion()
        
        // Step 2: Delete Firebase user
        Auth.auth().currentUser?.delete { [weak self] error in
            DispatchQueue.main.async {
                self?.delegate?.shouldShowLoading(false, message: nil)
                
                if let error = error {
                    self?.handleAccountDeletionError(error)
                } else {
                    self?.handleSuccessfulAccountDeletion()
                }
            }
        }
    }
    
    private func clearCurrentUserDataForDeletion() {
        // Clear only current user's data - preserves other users' data on device
        SecureLocalDataManager.shared.clearUserData() // Current user only
        
        // Clear current user's UserDefaults
        UserDefaultsManager.removeUser()
        UserDefaultsManager.clearAllSettings()
        
        // Clear current user's app-specific data
        clearCurrentUserAppSpecificData()
        
        print("✅ Current user data cleared for account deletion")
    }
    
    private func clearCurrentUserAppSpecificData() {
        // Clear only current user's profile image (if stored per-user)
        // Do NOT call clearAllGlobalProfileImages() as it affects all users
        
        // Reset migration state for current user only
        DataMigrationManager.shared.resetCurrentUserMigrationState()
        
        // Clear current user's data ownership only
        SecureLocalDataManager.shared.clearCurrentUserDataOwnership()
    }
    
    private func handleAccountDeletionError(_ error: Error) {
        // Handle re-authentication required error
        if (error as NSError).code == AuthErrorCode.requiresRecentLogin.rawValue {
            // IMPORTANT: Don't clear data here - other users might lose their data
            delegate?.didRequestReAuthentication()
        } else {
            delegate?.didFailAccountDeletion(
                title: "settings.delete.account.error.title".localized,
                message: error.localizedDescription
            )
        }
    }
    
    private func handleSuccessfulAccountDeletion() {
        // Sign out from authentication systems
        AuthenticationManager.shared.signOut()
        SecureLocalDataManager.shared.signOut()
        
        delegate?.didCompleteAccountDeletion()
    }
    
    // MARK: - Re-authentication Flow
    
    func handleReAuthenticationSignOut() {
        // Only clear current user's data, not all users' data
        clearCurrentUserLocalData()
        AuthenticationManager.shared.signOut()
    }
    
    private func clearCurrentUserLocalData() {
        // Clear only the current user's data - preserve other users' data
        SecureLocalDataManager.shared.clearUserData() // This clears only current user
        
        // Clear current user's UserDefaults
        UserDefaultsManager.removeUser()
        UserDefaultsManager.clearAllSettings()
        
        // Clear only current user's app-specific data (no global cleanup)
        clearCurrentUserAppSpecificData()
        
        print("✅ Current user data cleared (preserving other users' data)")
    }
}
```

### 2. Create SettingsViewController

Create `Finova/Sources/Scenes/Settings/SettingsViewController.swift`:

```swift
//
//  SettingsViewController.swift
//  Finova
//
//  Created by User on [Date]
//

import Foundation
import UIKit

protocol SettingsFlowDelegate: AnyObject {
    func dismissSettings()
    func logout()
}

final class SettingsViewController: UIViewController {
    let contentView: SettingsView
    weak var flowDelegate: SettingsFlowDelegate?
    private let viewModel: SettingsViewModel
    
    init(contentView: SettingsView, flowDelegate: SettingsFlowDelegate) {
        self.contentView = contentView
        self.flowDelegate = flowDelegate
        self.viewModel = SettingsViewModel()
        super.init(nibName: nil, bundle: nil)
        
        self.viewModel.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    private func setup() {
        view.backgroundColor = Colors.gray200
        view.addSubview(contentView)
        contentView.frame = view.bounds
        contentView.delegate = self
        setupNavigation()
    }
    
    private func setupNavigation() {
        navigationItem.title = "settings.title".localized
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "chevronLeft"),
            style: .plain,
            target: self,
            action: #selector(dismissTapped)
        )
        navigationItem.leftBarButtonItem?.tintColor = Colors.gray700
    }
    
    @objc private func dismissTapped() {
        flowDelegate?.dismissSettings()
    }
}

// MARK: - SettingsViewDelegate
extension SettingsViewController: SettingsViewDelegate {
    
    func didToggleBiometric(_ isEnabled: Bool) {
        viewModel.toggleBiometric(isEnabled)
    }
    
    func didTapDeleteAccount() {
        showDeleteAccountConfirmation()
    }
}

// MARK: - SettingsViewModelDelegate
extension SettingsViewController: SettingsViewModelDelegate {
    
    func didUpdateBiometricUI(isEnabled: Bool, isAvailable: Bool, biometricType: String) {
        contentView.biometricSwitch.isOn = isEnabled
        contentView.biometricSwitch.isEnabled = isAvailable
        contentView.biometricLabel.text = biometricType
        contentView.biometricLabel.textColor = isAvailable ? Colors.gray700 : Colors.gray400
    }
    
    func didUpdateAppVersion(_ version: String) {
        contentView.versionLabel.text = version
    }
    
    func didEncounterBiometricError(title: String, message: String) {
        // Revert switch if authentication failed
        contentView.biometricSwitch.isOn = false
        showErrorAlert(title: title, message: message)
    }
    
    func didRequestReAuthentication() {
        showReAuthenticationAlert()
    }
    
    func didCompleteAccountDeletion() {
        showSuccessAlert()
    }
    
    func didFailAccountDeletion(title: String, message: String) {
        showErrorAlert(title: title, message: message)
    }
    
    func shouldShowLoading(_ show: Bool, message: String?) {
        if show, let message = message {
            LoadingManager.shared.showLoading(on: self, message: message)
        } else {
            LoadingManager.shared.hideLoading()
        }
    }
}

// MARK: - Alert Methods
extension SettingsViewController {
    
    private func showDeleteAccountConfirmation() {
        let alert = UIAlertController(
            title: "settings.delete.account.title".localized,
            message: "settings.delete.account.warning".localized,
            preferredStyle: .alert
        )
        
        let deleteAction = UIAlertAction(
            title: "settings.delete.account.confirm".localized,
            style: .destructive
        ) { [weak self] _ in
            self?.viewModel.deleteAccount()
        }
        
        let cancelAction = UIAlertAction(
            title: "alert.cancel".localized,
            style: .cancel
        )
        
        alert.addAction(deleteAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    private func showReAuthenticationAlert() {
        let alert = UIAlertController(
            title: "settings.delete.account.reauth.title".localized,
            message: "settings.delete.account.reauth.message".localized,
            preferredStyle: .alert
        )
        
        let signOutAction = UIAlertAction(
            title: "settings.delete.account.signout".localized,
            style: .default
        ) { [weak self] _ in
            // This only clears current user data, preserving other users' data
            self?.viewModel.handleReAuthenticationSignOut()
            self?.flowDelegate?.logout()
        }
        
        let cancelAction = UIAlertAction(
            title: "alert.cancel".localized,
            style: .cancel
        )
        
        alert.addAction(signOutAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    private func showSuccessAlert() {
        let alert = UIAlertController(
            title: "settings.delete.account.success.title".localized,
            message: "settings.delete.account.success.message".localized,
            preferredStyle: .alert
        )
        
        let okAction = UIAlertAction(
            title: "alert.ok".localized,
            style: .default
        ) { [weak self] _ in
            self?.flowDelegate?.logout()
        }
        
        alert.addAction(okAction)
        present(alert, animated: true)
    }
    
    private func showErrorAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default))
        present(alert, animated: true)
    }
}
```

### 3. Create SettingsView

Create `Finova/Sources/Scenes/Settings/SettingsView.swift`:

```swift
//
//  SettingsView.swift
//  Finova
//
//  Created by User on [Date]
//

import Foundation
import UIKit

protocol SettingsViewDelegate: AnyObject {
    func didToggleBiometric(_ isEnabled: Bool)
    func didTapDeleteAccount()
}

final class SettingsView: UIView {
    
    weak var delegate: SettingsViewDelegate?
    
    // MARK: - UI Components
    
    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        return scroll
    }()
    
    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // Security Section
    private let securityHeaderView = createSectionHeader(title: "settings.section.security".localized)
    
    let biometricContainer = createSettingContainer()
    private let biometricIconView = createIconView(imageName: "faceid")
    let biometricLabel = createSettingLabel(text: "Face ID / Touch ID")
    let biometricSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.onTintColor = Colors.primary
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }()
    

    
    // About Section
    private let aboutHeaderView = createSectionHeader(title: "settings.section.about".localized)
    
    private let versionContainer = createSettingContainer()
    private let versionIconView = createIconView(imageName: "info.circle")
    private let versionTitleLabel = createSettingLabel(text: "settings.version.title".localized)
    let versionLabel = createDetailLabel(text: "1.0.0 (1)")
    
    // Account Section
    private let accountHeaderView = createSectionHeader(title: "settings.section.account".localized)
    
    private let deleteAccountContainer: UIView = {
        let container = createSettingContainer()
        container.backgroundColor = Colors.gray100
        return container
    }()
    private let deleteAccountIconView = createIconView(imageName: "trash", tintColor: Colors.red)
    private let deleteAccountLabel: UILabel = {
        let label = createSettingLabel(text: "settings.delete.account.title".localized)
        label.textColor = Colors.red
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupActions()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        backgroundColor = Colors.gray200
        
        addSubview(scrollView)
        scrollView.addSubview(contentStackView)
        
        setupSections()
        setupConstraints()
    }
    
    private func setupSections() {
        // Security Section
        contentStackView.addArrangedSubview(securityHeaderView)
        setupBiometricContainer()
        contentStackView.addArrangedSubview(biometricContainer)
        
        // About Section
        contentStackView.addArrangedSubview(aboutHeaderView)
        setupVersionContainer()
        contentStackView.addArrangedSubview(versionContainer)
        
        // Account Section
        contentStackView.addArrangedSubview(accountHeaderView)
        setupDeleteAccountContainer()
        contentStackView.addArrangedSubview(deleteAccountContainer)
    }
    
    private func setupBiometricContainer() {
        biometricContainer.addSubview(biometricIconView)
        biometricContainer.addSubview(biometricLabel)
        biometricContainer.addSubview(biometricSwitch)
        
        NSLayoutConstraint.activate([
            biometricIconView.leadingAnchor.constraint(equalTo: biometricContainer.leadingAnchor, constant: Metrics.spacing4),
            biometricIconView.centerYAnchor.constraint(equalTo: biometricContainer.centerYAnchor),
            
            biometricLabel.leadingAnchor.constraint(equalTo: biometricIconView.trailingAnchor, constant: Metrics.spacing3),
            biometricLabel.centerYAnchor.constraint(equalTo: biometricContainer.centerYAnchor),
            
            biometricSwitch.trailingAnchor.constraint(equalTo: biometricContainer.trailingAnchor, constant: -Metrics.spacing4),
            biometricSwitch.centerYAnchor.constraint(equalTo: biometricContainer.centerYAnchor)
        ])
    }
    

    
    private func setupVersionContainer() {
        versionContainer.addSubview(versionIconView)
        versionContainer.addSubview(versionTitleLabel)
        versionContainer.addSubview(versionLabel)
        
        NSLayoutConstraint.activate([
            versionIconView.leadingAnchor.constraint(equalTo: versionContainer.leadingAnchor, constant: Metrics.spacing4),
            versionIconView.centerYAnchor.constraint(equalTo: versionContainer.centerYAnchor),
            
            versionTitleLabel.leadingAnchor.constraint(equalTo: versionIconView.trailingAnchor, constant: Metrics.spacing3),
            versionTitleLabel.centerYAnchor.constraint(equalTo: versionContainer.centerYAnchor),
            
            versionLabel.trailingAnchor.constraint(equalTo: versionContainer.trailingAnchor, constant: -Metrics.spacing4),
            versionLabel.centerYAnchor.constraint(equalTo: versionContainer.centerYAnchor)
        ])
    }
    
    private func setupDeleteAccountContainer() {
        deleteAccountContainer.addSubview(deleteAccountIconView)
        deleteAccountContainer.addSubview(deleteAccountLabel)
        
        NSLayoutConstraint.activate([
            deleteAccountIconView.leadingAnchor.constraint(equalTo: deleteAccountContainer.leadingAnchor, constant: Metrics.spacing4),
            deleteAccountIconView.centerYAnchor.constraint(equalTo: deleteAccountContainer.centerYAnchor),
            
            deleteAccountLabel.leadingAnchor.constraint(equalTo: deleteAccountIconView.trailingAnchor, constant: Metrics.spacing3),
            deleteAccountLabel.centerYAnchor.constraint(equalTo: deleteAccountContainer.centerYAnchor)
        ])
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Metrics.spacing4),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Metrics.spacing4),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing4),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Metrics.spacing4),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * Metrics.spacing4)
        ])
    }
    
    private func setupActions() {
        biometricSwitch.addTarget(self, action: #selector(biometricToggled), for: .valueChanged)
        
        let deleteAccountTap = UITapGestureRecognizer(target: self, action: #selector(deleteAccountTapped))
        deleteAccountContainer.addGestureRecognizer(deleteAccountTap)
    }
    
    @objc private func biometricToggled() {
        delegate?.didToggleBiometric(biometricSwitch.isOn)
    }
    
    @objc private func deleteAccountTapped() {
        delegate?.didTapDeleteAccount()
    }
}

// MARK: - Factory Methods
extension SettingsView {
    
    private static func createSectionHeader(title: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.text = title.uppercased()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.spacing4),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.spacing3),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Metrics.spacing1),
            container.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        return container
    }
    
    private static func createSettingContainer() -> UIView {
        let container = UIView()
        container.backgroundColor = Colors.gray100
        container.layer.cornerRadius = CornerRadius.large
        container.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 56)
        ])
        
        return container
    }
    
    private static func createIconView(imageName: String, tintColor: UIColor = Colors.gray600) -> UIImageView {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: imageName)
        imageView.tintColor = tintColor
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        return imageView
    }
    
    private static func createSettingLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Fonts.textMD.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private static func createDetailLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private static func createChevronView() -> UIImageView {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "chevron.right")
        imageView.tintColor = Colors.gray400
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 12),
            imageView.heightAnchor.constraint(equalToConstant: 12)
        ])
        
        return imageView
    }
}
```

---

## Feature Implementations

### 3. UserDefaults Extensions

Create `Finova/Sources/Core/UserDefaults/UserDefaultsManager+Settings.swift`:

```swift
//
//  UserDefaultsManager+Settings.swift
//  Finova
//
//  Created by User on [Date]
//

import Foundation

extension UserDefaultsManager {
    
    // MARK: - Biometric Settings
    
    private static let biometricEnabledKey = "biometricEnabled"
    
    static func setBiometricEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: biometricEnabledKey)
        UserDefaults.standard.synchronize()
    }
    
    static func getBiometricEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: biometricEnabledKey)
    }
    

    
    // MARK: - Clear All Settings
    
    static func clearAllSettings() {
        UserDefaults.standard.removeObject(forKey: biometricEnabledKey)
        UserDefaults.standard.removeObject(forKey: currentMonthIndex)
        UserDefaults.standard.removeObject(forKey: balanceDisplayModeKey)
        UserDefaults.standard.synchronize()
    }
}
```

### 4. Add User Data Management Methods to SecureLocalDataManager

Add these methods to your `SecureLocalDataManager.swift`:

```swift
// Add these methods to SecureLocalDataManager class

/// Clear current user's data ownership records only
func clearCurrentUserDataOwnership() {
    guard let uid = currentUserUID else {
        print("❌ Cannot clear data ownership: No authenticated user")
        return
    }
    
    // Clear only current user's ownership records, preserve others
    // Implementation should remove ownership for current UID only
    print("✅ Current user data ownership cleared")
}

/// Clear all user data - existing method, already implemented
/// This method should clear only current user's encrypted data directory
func clearUserData() {
    // Existing implementation - clears current user's data only
    // This is the correct method to use for both account deletion and re-auth
}
```

**Important Note**: The `clearUserData()` method clears only the current user's encrypted data, preserving other users' data on the device. This is the correct approach for both account deletion and re-authentication scenarios.

### 5. Add DataMigrationManager Method

Add this method to your `DataMigrationManager.swift`:

```swift
// Add this method to DataMigrationManager class

/// Reset migration state for current user only
func resetCurrentUserMigrationState() {
    guard let uid = currentUserUID else {
        print("❌ Cannot reset migration state: No authenticated user")
        return
    }
    
    // Reset migration flags for current user only
    // Do not affect other users' migration states
    UserDefaults.standard.removeObject(forKey: "migration_completed_\(uid)")
    print("✅ Current user migration state reset")
}
```

---

## Dashboard Integration

### 6. Update DashboardView

Add the settings button to your `DashboardView.swift` by modifying the header section:

```swift
// Add this property to DashboardView class
private let settingsButton: UIButton = {
    let btn = UIButton(type: .system)
    btn.setImage(UIImage(named: "settingsIcon"), for: .normal)
    btn.tintColor = Colors.gray500
    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
}()

// Update your setupView() method to include the settings button
private func setupView() {
    // ... existing code ...
    
    headerItemsView.addSubview(settingsButton)
    
    // ... existing code ...
    
    settingsButton.addTarget(
        self,
        action: #selector(settingsTapped),
        for: .touchUpInside)
}

// Update your setupLayout() method to position the settings button
private func setupLayout() {
    NSLayoutConstraint.activate([
        // ... existing constraints ...
        
        settingsButton.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
        settingsButton.trailingAnchor.constraint(
            equalTo: logoutButton.leadingAnchor, constant: -Metrics.spacing3),
        settingsButton.heightAnchor.constraint(equalToConstant: Metrics.logoutButtonSize),
        settingsButton.widthAnchor.constraint(equalToConstant: Metrics.logoutButtonSize),
        
        // Update logout button constraint to account for settings button
        logoutButton.trailingAnchor.constraint(
            equalTo: headerItemsView.layoutMarginsGuide.trailingAnchor),
        
        // ... rest of existing constraints ...
    ])
}

// Add the settings button action
@objc private func settingsTapped() {
    delegate?.didTapSettings()
}
```

### 7. Update DashboardViewDelegate

Add the settings method to `DashboardViewDelegate.swift`:

```swift
public protocol DashboardViewDelegate: AnyObject {
    func didTapAddTransaction()
    func didTapProfileImage()
    func didTapSettings()  // Add this line
    func logout()
}
```

### 8. Update DashboardViewController

Add the settings navigation to `DashboardViewController.swift`:

```swift
// Add this to the DashboardViewDelegate extension
extension DashboardViewController: DashboardViewDelegate {
    // ... existing methods ...
    
    func didTapSettings() {
        self.flowDelegate?.openSettings()
    }
}
```

### 9. Update DashboardFlowDelegate

Add the settings method to `DashboardFlowDelegate.swift`:

```swift
public protocol DashboardFlowDelegate: AnyObject {
    func logout()
    func navigateToBudgets(date: Date?)
    func openAddTransactionModal()
    func openSettings()  // Add this line
}
```

### 10. Update AppFlowController

Add settings navigation to `AppFlowController.swift`:

```swift
// Add this extension to AppFlowController
extension AppFlowController: SettingsFlowDelegate {
    func dismissSettings() {
        navigationController?.dismiss(animated: true)
    }
}

// Add this method to the DashboardFlowDelegate extension
extension AppFlowController: DashboardFlowDelegate {
    // ... existing methods ...
    
    func openSettings() {
        let settingsViewController = viewControllersFactory.makeSettingsViewController(flowDelegate: self)
        let navController = UINavigationController(rootViewController: settingsViewController)
        navController.modalPresentationStyle = .pageSheet
        navigationController?.present(navController, animated: true)
    }
}
```

### 11. Update ViewControllersFactory

Add the settings factory method to `ViewControllersFactory.swift`:

```swift
// Add this method to ViewControllersFactory class
func makeSettingsViewController(flowDelegate: SettingsFlowDelegate) -> SettingsViewController {
    let settingsView = SettingsView()
    let settingsViewController = SettingsViewController(
        contentView: settingsView,
        flowDelegate: flowDelegate
    )
    return settingsViewController
}
```

And add it to `ViewControllersFactoryProtocol.swift`:

```swift
// Add this method to ViewControllersFactoryProtocol
func makeSettingsViewController(flowDelegate: SettingsFlowDelegate) -> SettingsViewController
```

---

## Localization Strings

Add these localization strings to your `Localizable.xcstrings`:

```json
{
  "settings.title": {
    "en": "Settings",
    "pt-BR": "Configurações"
  },
  "settings.section.security": {
    "en": "Security",
    "pt-BR": "Segurança"
  },

  "settings.section.about": {
    "en": "About",
    "pt-BR": "Sobre"
  },
  "settings.section.account": {
    "en": "Account",
    "pt-BR": "Conta"
  },
  "settings.biometric.enable.reason": {
    "en": "Enable biometric authentication for secure access",
    "pt-BR": "Ativar autenticação biométrica para acesso seguro"
  },
  "settings.biometric.error.title": {
    "en": "Biometric Error",
    "pt-BR": "Erro Biométrico"
  },

  "settings.version.title": {
    "en": "Version",
    "pt-BR": "Versão"
  },
  "settings.delete.account.title": {
    "en": "Delete Account",
    "pt-BR": "Excluir Conta"
  },
  "settings.delete.account.warning": {
    "en": "This action is irreversible. All your data will be permanently deleted. Are you sure?",
    "pt-BR": "Esta ação é irreversível. Todos os seus dados serão excluídos permanentemente. Tem certeza?"
  },
  "settings.delete.account.confirm": {
    "en": "Delete",
    "pt-BR": "Excluir"
  },
  "settings.delete.account.processing": {
    "en": "Deleting account...",
    "pt-BR": "Excluindo conta..."
  },
  "settings.delete.account.error.title": {
    "en": "Deletion Error",
    "pt-BR": "Erro na Exclusão"
  },
  "settings.delete.account.reauth.title": {
    "en": "Authentication Required",
    "pt-BR": "Autenticação Necessária"
  },
  "settings.delete.account.reauth.message": {
    "en": "Please sign in again to delete your account, or sign out to clear local data only",
    "pt-BR": "Faça login novamente para excluir sua conta, ou saia para limpar apenas os dados locais"
  },
  "settings.delete.account.signout": {
    "en": "Sign Out & Clear Data",
    "pt-BR": "Sair e Limpar Dados"
  },
  "settings.delete.account.success.title": {
    "en": "Account Deleted",
    "pt-BR": "Conta Excluída"
  },
  "settings.delete.account.success.message": {
    "en": "Your account has been successfully deleted",
    "pt-BR": "Sua conta foi excluída com sucesso"
  }
}
```

---

## Testing & Validation

1. **Test on physical device** - Face ID/Touch ID requires real hardware
2. **Test account deletion flow** - Verify Firebase user deletion and local data cleanup
3. **Test language/currency changes** - Verify preferences are saved and applied
4. **Test navigation flow** - Ensure proper modal presentation and dismissal
5. **Test UI on different screen sizes** - Verify layout works on all supported devices
6. **Test biometric toggle** - Verify Face ID permission requests work correctly

---

## References
- [App Store Review Solution Guide](./APP_STORE_REVIEW_SOLUTION_GUIDE.md)
- [Sign in with Apple Implementation Guide](./SIGN_IN_WITH_APPLE_IMPLEMENTATION_GUIDE.md)
- [Firebase Auth Implementation Plan](./FIREBASE_AUTH_IMPLEMENTATION_PLAN.md)
- [Security Implementation Summary](./SECURITY_IMPLEMENTATION_SUMMARY.md) 