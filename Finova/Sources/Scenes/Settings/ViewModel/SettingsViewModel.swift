//
//  SettingsViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 17/07/25.
//

import Foundation
import UIKit
import FirebaseAuth
import LocalAuthentication

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
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
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
        delegate?.didUpdateAppVersion(version: appVersionString)
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
            reason: "settings.biometric.enable.reason".localized) { [weak self] success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.isBiometricEnabled = true
                        FaceIDManager.shared.enableFaceIDForCurrentUser()
                        print("✅ Biometric authentication enabled")
                    } else {
                        if let error = error {
                            self?.delegate?.didEncounterBiometricError(
                                title: "settings.biometric.error.title",
                                message: FaceIDManager.shared.getFriendlyErrorMessage(for: error))
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
