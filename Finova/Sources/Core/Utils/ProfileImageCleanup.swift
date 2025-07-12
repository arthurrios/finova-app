//
//  ProfileImageCleanup.swift
//  FinanceApp
//
//  Created by Cursor on 27/01/25.
//

import Foundation
import UIKit

/// Utility class to clean up any global profile image storage
/// and ensure all user images are stored only in user-specific encrypted storage
class ProfileImageCleanup {
    
    static let shared = ProfileImageCleanup()
    
    private init() {}
    
    /// Immediately clears any global profile images from known storage locations
    func clearAllGlobalProfileImages() {
        print("🧹 Starting global profile image cleanup...")
        
        // 1. Clear from UserDefaults (primary global storage)
        clearFromUserDefaults()
        
        // 2. Clear from Documents directory (if any files exist there)
        clearFromDocumentsDirectory()
        
        print("✅ Global profile image cleanup completed")
    }
    
    // MARK: - Private Methods
    
    private func clearFromUserDefaults() {
        let profileImageKeys = [
            "profileImageKey",
            "userProfileImage",
            "profile_image",
            "user_image",
            "globalProfileImage"
        ]
        
        for key in profileImageKeys where UserDefaults.standard.object(forKey: key) != nil {
            UserDefaults.standard.removeObject(forKey: key)
            print("🧹 Cleared profile image from UserDefaults key: \(key)")
        }
        
        UserDefaults.standard.synchronize()
    }
    
    private func clearFromDocumentsDirectory() {
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            return
        }
        
        let profileImageFileNames = [
            "profile_image.jpg",
            "profile_image.png",
            "user_image.jpg",
            "user_image.png",
            "profile.jpg",
            "profile.png"
        ]
        
        for fileName in profileImageFileNames {
            let fileURL = documentsDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
                print("🧹 Removed profile image file: \(fileName)")
            }
        }
    }
    
    func loadGlobalProfileImageIfExists() -> UIImage? {
        // Try to load from UserDefaults (deprecated method)
        if let imageData = UserDefaults.standard.data(forKey: "profileImageKey"),
           let image = UIImage(data: imageData) {
            return image
        }
        
        // Try to load from documents directory
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            return nil
        }
        
        let possibleFiles = [
            "profile_image.jpg",
            "profile_image.png",
            "user_image.jpg",
            "user_image.png"
        ]
        
        for fileName in possibleFiles {
            let fileURL = documentsDirectory.appendingPathComponent(fileName)
            if let imageData = try? Data(contentsOf: fileURL),
               let image = UIImage(data: imageData) {
                return image
            }
        }
        
        return nil
    }
}
