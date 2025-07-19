//
//  UserLoginModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation

struct User: Codable {
    let firebaseUID: String?
    var name: String
    let email: String
    var isUserSaved: Bool = false
    var hasFaceIdEnabled: Bool = false
    let createdAt: Date
    let lastSignIn: Date
    
    init(firebaseUID: String?, name: String, email: String, isUserSaved: Bool = false, hasFaceIdEnabled: Bool = false) {
        self.firebaseUID = firebaseUID
        self.name = name
        self.email = email
        self.isUserSaved = isUserSaved
        self.hasFaceIdEnabled = hasFaceIdEnabled
        self.createdAt = Date()
        self.lastSignIn = Date()
    }
    
    init(name: String, email: String, isUserSaved: Bool = false, hasFaceIdEnabled: Bool = false) {
        self.firebaseUID = nil
        self.name = name
        self.email = email
        self.isUserSaved = isUserSaved
        self.hasFaceIdEnabled = hasFaceIdEnabled
        self.createdAt = Date()
        self.lastSignIn = Date()
    }
    
    var isFirebaseUser: Bool {
        return firebaseUID != nil
    }
    
    var displayName: String {
        return name.isEmpty ? "User" : name
    }
}

extension User {
    func withUpdatedSignIn() -> User {
        var updatedUser = self
        return User(
            firebaseUID: self.firebaseUID,
            name: self.name,
            email: self.email,
            isUserSaved: self.isUserSaved,
            hasFaceIdEnabled: self.hasFaceIdEnabled
        )
    }
}
