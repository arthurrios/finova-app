//
//  AuthenticationManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 23/06/25.
//

import Foundation
import FirebaseAuth
import GoogleSignIn
import UIKit

protocol AuthenticationManagerDelegate: AnyObject {
    func authenticationDidComplete(user: User)
    func authenticationDidFail(error: Error)
}

class AuthenticationManager {
    
    // MARK: - Singleton
    
    static let shared = AuthenticationManager()
    
    // MARK: - Properties
    
    weak var delegate: AuthenticationManagerDelegate?
    
    private init() {
        setupAuthStateListener()
    }
    
    // MARK: - Public Properties
    
    var currentUser: FirebaseAuth.User? {
        return Auth.auth().currentUser
    }
    
    var isAuthenticated: Bool {
        return currentUser != nil
    }
    
    // MARK: - Authentication State Listener
    
    private func setupAuthStateListener() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            if let user = user {
                print("🔥 Firebase Auth State Changed: User signed in - \(user.email ?? "No email")")
                self?.handleAuthenticatedUser(user)
            } else {
                print("🔥 Firebase Auth State Changed: User signed out")
            }
        }
    }
    
    // MARK: - Email/Password Authentication
    
    func signIn(email: String, password: String) {
        print("🔐 Attempting email/password sign-in for: \(email)")
        
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            self?.handleAuthResult(result: result, error: error, method: "Email/Password")
        }
    }
    
    func register(name: String, email: String, password: String) {
        print("🔐 Attempting user registration for: \(email)")
        
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            if let error = error {
                print("❌ Registration failed: \(error.localizedDescription)")
                self?.delegate?.authenticationDidFail(error: error)
                return
            }
            
            if let user = result?.user {
                let changeRequest = user.createProfileChangeRequest()
                changeRequest.displayName = name
                changeRequest.commitChanges { profileError in
                    if let profileError = profileError {
                        print("⚠️ Failed to update display name: \(profileError.localizedDescription)")
                    } else {
                        print("✅ Display name updated successfully")
                    }
                }
            }
            
            self?.handleAuthResult(result: result, error: error, method: "Registration")
        }
    }
    
    // MARK: - Google Sign-In
    
    func signInWithGoogle() {
        print("🔐 Attempting Google Sign-In")
        
        guard let presentingViewController = getCurrentViewController() else {
            print("❌ No presenting view controller found")
            delegate?.authenticationDidFail(error: AuthError.noPresentingController)
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { [weak self] result, error in
            if let error = error {
                print("❌ Google Sign-In failed: \(error.localizedDescription)")
                self?.delegate?.authenticationDidFail(error: error)
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                print("❌ Failed to obtain Google tokens")
                self?.delegate?.authenticationDidFail(error: AuthError.googleTokenFailure)
                return
            }
            
            print("✅ Google tokens obtained successfully")

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )
            
            Auth.auth().signIn(with: credential) { authResult, authError in
                self?.handleAuthResult(result: authResult, error: authError, method: "Google Sign-In")
            }
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        print("🔐 Signing out user")
        
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            print("✅ User signed out successfully")
        } catch {
            print("❌ Error signing out: \(error.localizedDescription)")
        }
    }

    // MARK: - Private methods
    
    private func handleAuthResult(result: AuthDataResult?, error: Error?, method: String) {
        if let error = error {
            print("❌ \(method) authentication failed: \(error.localizedDescription)")
            delegate?.authenticationDidFail(error: error)
            return
        }
        
        guard let firebaseUser = result?.user else {
            print("❌ No user data received from \(method)")
            delegate?.authenticationDidFail(error: AuthError.noUser)
            return
        }
        
        print("✅ \(method) authentication successful for: \(firebaseUser.email ?? "No email")")
        handleAuthenticatedUser(firebaseUser)
    }
    
    private func handleAuthenticatedUser(_ firebaseUser: FirebaseAuth.User) {
        print("🔄 Processing authenticated user: \(firebaseUser.uid)")
        
        let user = User(
            firebaseUID: firebaseUser.uid,
            name: firebaseUser.displayName ?? "User",
            email: firebaseUser.email ?? "",
            isUserSaved: true,
            hasFaceIdEnabled: false
        )
        
        print("✅ Local user object created successfully")
        delegate?.authenticationDidComplete(user: user)
    }
}

// MARK: - Helper Method for Getting Current View Controller

private func getCurrentViewController() -> UIViewController? {
    if let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .filter({ $0.activationState == .foregroundActive })
        .first {
        
        if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return keyWindow.rootViewController?.topMostViewController()
        }
    }
    
    if let keyWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) {
        return keyWindow.rootViewController?.topMostViewController()
    }
    
    return nil
}

// MARK: - Authentication Errors

enum AuthError: LocalizedError {
    case noPresentingController
    case googleTokenFailure
    case noUser
    case invalidCredentials
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .noPresentingController:
            return "No view controller available to present Google Sign-In"
        case .googleTokenFailure:
            return "Failed to obtain Google authentication token"
        case .noUser:
            return "No user data received from authentication"
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError:
            return "Network connection error. Please check your internet connection."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .noPresentingController:
            return "Please try again when the app is in the foreground"
        case .googleTokenFailure:
            return "Please try again or use email/password sign-in"
        case .noUser:
            return "Please contact support if this issue persists"
        case .invalidCredentials:
            return "Please check your email and password and try again"
        case .networkError:
            return "Please check your internet connection and try again"
        }
    }
}

private extension UIViewController {
    func topMostViewController() -> UIViewController {
        if let presented = self.presentedViewController {
            return presented.topMostViewController()
        }
        
        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.topMostViewController() ?? navigationController
        }
        
        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.topMostViewController() ?? tabBarController
        }
        
        return self
    }
}
