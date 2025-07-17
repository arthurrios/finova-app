//
//  BiometricDataManager.swift
//  FinanceApp
//

import Foundation
import LocalAuthentication
import Security
import UIKit

class BiometricDataManager {
    // MARK: - Singleton
    static let shared = BiometricDataManager()
    private init() {}
    
    // MARK: - Keychain Keys
    private let biometricIdentifierKey = "biometric_user_identifier"
    
    // MARK: - Biometric Availability
    func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    func getBiometricType() -> LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }
    
    // MARK: - Biometric Registration
    func registerUserBiometric(for email: String, completion: @escaping (Bool, Error?) -> Void) {
        guard isBiometricAvailable() else {
            completion(false, BiometricError.notAvailable)
            return
        }
        let context = LAContext()
        let reason = "Register your biometric authentication to link accounts securely"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) {
            [weak self] success, error in
            if success {
                let biometricIdentifier = self?.generateBiometricIdentifier() ?? UUID().uuidString
                let stored =
                self?.storeBiometricData(identifier: biometricIdentifier, email: email) ?? false
                DispatchQueue.main.async {
                    completion(stored, stored ? nil : BiometricError.storageFailure)
                }
            } else {
                DispatchQueue.main.async {
                    completion(false, error ?? BiometricError.authenticationFailed)
                }
            }
        }
    }
    // MARK: - Biometric Verification
    func verifyUserBiometric(completion: @escaping (BiometricVerificationResult) -> Void) {
        guard isBiometricAvailable() else {
            completion(.notAvailable)
            return
        }
        guard getBiometricData() != nil else {
            completion(.noRegisteredBiometric)
            return
        }
        let context = LAContext()
        let reason = "Verify your identity to access existing account data"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) {
            [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    if let biometricData = self?.getBiometricData() {
                        completion(.verified(linkedEmail: biometricData.email))
                    } else {
                        completion(.verificationFailed)
                    }
                } else {
                    if let laError = error as? LAError {
                        switch laError.code {
                        case .userCancel:
                            completion(.userCancelled)
                        case .userFallback:
                            completion(.userFallback)
                        default:
                            completion(.verificationFailed)
                        }
                    } else {
                        completion(.verificationFailed)
                    }
                }
            }
        }
    }
    // MARK: - Biometric Data Management
    func hasBiometricData() -> Bool {
        return getBiometricData() != nil
    }
    func getLinkedEmail() -> String? {
        return getBiometricData()?.email
    }
    func clearBiometricData() {
        deleteBiometricDataFromKeychain()
    }
    // MARK: - Private Methods
    private func generateBiometricIdentifier() -> String {
        let deviceIdentifier = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let timestamp = String(Date().timeIntervalSince1970)
        let combined = "\(deviceIdentifier)_\(timestamp)"
        return combined.data(using: String.Encoding.utf8)?.base64EncodedString() ?? UUID().uuidString
    }
    private func storeBiometricData(identifier: String, email: String) -> Bool {
        let biometricData = BiometricUserData(
            identifier: identifier, email: email, registrationDate: Date())
        do {
            let data = try JSONEncoder().encode(biometricData)
            return storeBiometricDataInKeychain(data: data)
        } catch {
            print("❌ Failed to encode biometric data: \(error)")
            return false
        }
    }
    private func getBiometricData() -> BiometricUserData? {
        guard let data = getBiometricDataFromKeychain() else { return nil }
        do {
            return try JSONDecoder().decode(BiometricUserData.self, from: data)
        } catch {
            print("❌ Failed to decode biometric data: \(error)")
            return nil
        }
    }
    // MARK: - Keychain Operations
    private func storeBiometricDataInKeychain(data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: biometricIdentifierKey,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "FinanceApp",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    private func getBiometricDataFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: biometricIdentifierKey,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "FinanceApp",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            return result as? Data
        }
        return nil
    }
    private func deleteBiometricDataFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: biometricIdentifierKey,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "FinanceApp",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Supporting Types

struct BiometricUserData: Codable {
    let identifier: String
    let email: String
    let registrationDate: Date
}

enum BiometricVerificationResult {
    case verified(linkedEmail: String)
    case verificationFailed
    case userCancelled
    case userFallback
    case notAvailable
    case noRegisteredBiometric
}

enum BiometricError: LocalizedError {
    case notAvailable
    case authenticationFailed
    case storageFailure
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Biometric authentication is not available on this device"
        case .authenticationFailed:
            return "Biometric authentication failed"
        case .storageFailure:
            return "Failed to store biometric data securely"
        }
    }
}
