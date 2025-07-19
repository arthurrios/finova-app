//
//  FaceIDManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 23/06/25.
//

import Foundation
import LocalAuthentication

class FaceIDManager {
    static let shared = FaceIDManager()
    
    private init() {}
    
    // MARK: - Face ID Availability
    
    var isFaceIDAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    var biometricType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        return context.biometryType
    }
    
    var biometricTypeString: String {
        switch biometricType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Biometrics"
        @unknown default:
            return "Biometric Authentication"
        }
    }
    
    // MARK: - Authentication
    
    func authenticateWithBiometrics(reason: String, completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }
    
    // MARK: - User Settings
    
    func enableFaceIDForCurrentUser() {
        UserDefaultsManager.updateCurrentUserFaceID(enabled: true)
        print("✅ Face ID enabled for current user")
    }
    
    func disableFaceIDForCurrentUser() {
        UserDefaultsManager.updateCurrentUserFaceID(enabled: false)
        print("✅ Face ID disabled for current user")
    }
    
    var isCurrentUserFaceIDEnabled: Bool {
        return UserDefaultsManager.getCurrentUserFaceIDSetting()
    }
    
    // MARK: - Error Handling
    
    func getFriendlyErrorMessage(for error: Error) -> String {
        guard let laError = error as? LAError else {
            return "An unknown biometric authentication error occurred."
        }
        
        switch laError.code {
        case .authenticationFailed:
            return "\(biometricTypeString) authentication failed. Please try again."
        case .userCancel:
            return "Authentication was cancelled."
        case .userFallback:
            return "User chose to enter password instead."
        case .systemCancel:
            return "Authentication was cancelled by the system."
        case .passcodeNotSet:
            return "Device passcode is not set. Please set up a passcode in Settings."
        case .biometryNotAvailable:
            return "\(biometricTypeString) is not available on this device."
        case .biometryNotEnrolled:
            return "\(biometricTypeString) is not set up. Please set up \(biometricTypeString) in Settings."
        case .biometryLockout:
            return "\(biometricTypeString) is locked. Please unlock using your passcode."
        default:
            return "Biometric authentication error: \(laError.localizedDescription)"
        }
    }
}
