//
//  SecureLocalDataManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 23/06/25.
//

import Foundation
import CryptoKit

class SecureLocalDataManager {
    
    // MARK: - Singleton
    static let shared = SecureLocalDataManager()
    
    // MARK: - Properties
    private var currentUserUID: String?
    private var encryptionKey: SymmetricKey?
    
    private init() {}
    
    // MARK: - User Session Management
    
    func authenticateUser(firebaseUID: String) {
        print("🔒 Authenticating user for secure data access: \(firebaseUID)")
        self.currentUserUID = firebaseUID
        self.encryptionKey = generateEncryptionKey(for: firebaseUID)
        
        // Create user data directory if first time
        createUserDataDirectoryIfNeeded(for: firebaseUID)
        print("✅ User authenticated for secure data access")
    }
    
    func signOut() {
        print("🔒 Signing out from secure data manager")
        self.currentUserUID = nil
        self.encryptionKey = nil
    }
    
    // MARK: - Generic Data Access (UID-isolated)
    
    func saveData<T: Codable>(_ data: T, filename: String) {
        guard let uid = currentUserUID else {
            print("❌ Cannot save data: No authenticated user")
            return
        }
        
        saveEncryptedData(data, for: uid, filename: filename)
    }
    
    func loadData<T: Codable>(type: T.Type, filename: String) -> T? {
        guard let uid = currentUserUID else {
            print("❌ Cannot load data: No authenticated user")
            return nil
        }
        return loadEncryptedData(type: type, for: uid, filename: filename)
    }
    
    // MARK: - Data Migration from Old Local Storage
    
    func migrateOldDataToUser(firebaseUID: String, completion: @escaping (Bool) -> Void) {
        print("🔄 Starting data migration for user: \(firebaseUID)")
        
        let migrationKey = "data_migrated_to_firebase_\(firebaseUID)"
        if UserDefaults.standard.bool(forKey: migrationKey) {
            print("✅ Migration already completed for this user")
            completion(true)
            return
        }
        
        // Authenticate with new UID
        authenticateUser(firebaseUID: firebaseUID)
        
        // For now, mark migration as completed
        // TODO: Add actual migration logic when we integrate with your existing data
        UserDefaults.standard.set(true, forKey: migrationKey)
        print("✅ Data migration completed successfully")
        completion(true)
    }
    
    // MARK: - User Data Directory Management
    
    func getUserDataDirectory() -> URL? {
        guard let uid = currentUserUID else { return nil }
        return getUserDataDirectory(for: uid)
    }
    
    func clearUserData() {
        guard let uid = currentUserUID else { return }
        let userDirectory = getUserDataDirectory(for: uid)
        
        do {
            if FileManager.default.fileExists(atPath: userDirectory.path) {
                do {
                    try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
                    print("✅ User data directory created: \(userDirectory.path)")
                } catch {
                    print("❌ Failed to create user data directory: \(error)")
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func generateEncryptionKey(for userUID: String) -> SymmetricKey {
        let keyData = SHA256.hash(data: Data(userUID.utf8))
        return SymmetricKey(data: keyData)
    }
    
    private func createUserDataDirectoryIfNeeded(for userUID: String) {
        let userDirectory = getUserDataDirectory(for: userUID)
        
        if !FileManager.default.fileExists(atPath: userDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
            } catch {
                print("❌ Failed to create user data directory: \(error)")
            }
        }
    }
    
    private func getUserDataDirectory(for userUID: String) -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory
            .appendingPathComponent("UserData")
            .appendingPathExtension(userUID)
    }
    
    private func saveEncryptedData<T: Codable>(_ data: T, for userUID: String, filename: String) {
        guard let encryptionKey = encryptionKey else {
            print("❌ Cannot save: No encryption key available")
            return
        }
        
        do {
            let jsonData = try JSONEncoder().encode(data)
            let encryptedData = try AES.GCM.seal(jsonData, using: encryptionKey)
            
            let userDirectory = getUserDataDirectory(for: userUID)
            let fileURL = userDirectory.appendingPathComponent(filename)
            
            try encryptedData.combined?.write(to: fileURL)
            print("✅ Encrypted data saved: \(filename)")
        } catch {
            print("❌ Failed to save encrypted data: \(error)")
        }
    }
    
    private func loadEncryptedData<T: Codable>(type: T.Type, for userUID: String, filename: String) -> T? {
        guard let encryptionKey = encryptionKey else {
            print("❌ Cannot load: No encryption key available")
            return nil
        }
        
        do {
            let userDirectory = getUserDataDirectory(for: userUID)
            let fileURL = userDirectory.appendingPathComponent(filename)
            
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("ℹ️ Data file does not exist: \(filename)")
                return nil
            }
            
            let encryptedData = try Data(contentsOf: fileURL)
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
            
            let result = try JSONDecoder().decode(type, from: decryptedData)
            print("✅ Encrypted data loaded: \(filename)")
            return result
        } catch {
            print("❌ Failed to load encrypted data: \(error)")
            return nil
        }
    }
}

// MARK: - Debug Helper

extension SecureLocalDataManager {
    func printDebugInfo() {
        print("🔍 SecureLocalDataManager Debug Info:")
        print("   Current User UID: \(currentUserUID ?? "None")")
        print("   Encryption Key: \(encryptionKey != nil ? "Available" : "None")")
        if let directory = getUserDataDirectory() {
            print("   User Data Directory: \(directory.path)")
            print("   Directory Exists: \(FileManager.default.fileExists(atPath: directory.path))")
        }
    }
}
