//
//  UserDefaultsManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation
import UIKit

class UserDefaultsManager {
    private static let userKey = "userKey"
    private static let profileImageKey = "profileImageKey"
    
    static func saveUser(user: User) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    static func saveProfileImage(image: UIImage) {
        if let imageData = image.jpegData(compressionQuality: 1.0) {
            UserDefaults.standard.set(imageData, forKey: profileImageKey)
        }
    }
    
    static func loadProfileImage() -> UIImage? {
        if let imageData = UserDefaults.standard.data(forKey: profileImageKey) {
            return UIImage(data: imageData)
        }
        return nil
    }
    
    static func getUser() -> User? {
        if let userData = UserDefaults.standard.data(forKey: userKey) {
            let decoder = JSONDecoder()
            if let user = try? decoder.decode(User.self, from: userData) {
                return user
            }
        }
        return nil
    }
    
    static func removeUser() {
        UserDefaults.standard.removeObject(forKey: userKey)
        UserDefaults.standard.synchronize()
    }
}
