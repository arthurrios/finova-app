//
//  AuthenticationManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 23/06/25.
//

import FirebaseAuth
import Foundation
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

  private var isHandlingAuthentication = false

  private func setupAuthStateListener() {
    Auth.auth().addStateDidChangeListener { [weak self] _, user in
      if let user = user {
        print("🔥 Firebase Auth State Changed: User signed in - \(user.email ?? "No email")")

        // Only handle auth state change if not already handling authentication
        if self?.isHandlingAuthentication == false {
          print("📱 Handling auth state change (app startup or background return)")
          self?.handleAuthenticatedUser(user)
        } else {
          print("⏭️ Skipping auth state change (already handling login flow)")
        }
      } else {
        print("🔥 Firebase Auth State Changed: User signed out")
        self?.isHandlingAuthentication = false
      }
    }
  }

  // MARK: - Email/Password Authentication

  func signIn(email: String, password: String) {
    print("🔐 Attempting email/password sign-in for: \(email)")
    isHandlingAuthentication = true

    Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
      self?.handleAuthResult(result: result, error: error, method: "Email/Password")
    }
  }

  func register(name: String, email: String, password: String) {
    print("🔐 Attempting user registration for: \(email)")
    print("🔐 Password length: \(password.count) characters")
    print("🔐 Firebase Auth instance: \(Auth.auth())")
    isHandlingAuthentication = true

    Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
      if let error = error {
        print("❌ Registration failed with detailed error:")
        print("   - Error: \(error)")
        print("   - Localized Description: \(error.localizedDescription)")
        print("   - Error Code: \((error as NSError).code)")
        print("   - Error Domain: \((error as NSError).domain)")
        print("   - User Info: \((error as NSError).userInfo)")

        // Check if it's a Firebase Auth error
        if let authError = error as? AuthErrorCode {
          print("   - Firebase Auth Error Code: \(authError.rawValue)")
        }

        self?.isHandlingAuthentication = false
        self?.delegate?.authenticationDidFail(error: error)
        return
      }

      print("✅ Firebase user created successfully")

      if let user = result?.user {
        print("✅ User UID: \(user.uid)")
        print("✅ User Email: \(user.email ?? "No email")")

        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = name
        changeRequest.commitChanges { [weak self] profileError in
          if let profileError = profileError {
            print("⚠️ Failed to update display name: \(profileError.localizedDescription)")
            // Still proceed with authentication even if display name update fails
            self?.handleAuthResult(result: result, error: error, method: "Registration")
          } else {
            print("✅ Display name updated successfully to: \(name)")
            // Reload the user to get the updated display name
            user.reload { reloadError in
              if let reloadError = reloadError {
                print(
                  "⚠️ Failed to reload user after display name update: \(reloadError.localizedDescription)"
                )
              } else {
                print("✅ User reloaded successfully, displayName: '\(user.displayName ?? "nil")'")
              }
              // Now handle authentication with updated display name
              self?.handleAuthResult(result: result, error: error, method: "Registration")
            }
          }
        }
      } else {
        // No user object, handle auth result immediately
        self?.handleAuthResult(result: result, error: error, method: "Registration")
      }
    }
  }

  // MARK: - Google Sign-In

  func signInWithGoogle() {
    print("🔐 Attempting Google Sign-In")
    isHandlingAuthentication = true

    guard let presentingViewController = getCurrentViewController() else {
      print("❌ No presenting view controller found")
      isHandlingAuthentication = false
      delegate?.authenticationDidFail(error: AuthError.noPresentingController)
      return
    }

    GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) {
      [weak self] result, error in
      if let error = error {
        print("❌ Google Sign-In failed: \(error.localizedDescription)")
        self?.isHandlingAuthentication = false
        self?.delegate?.authenticationDidFail(error: error)
        return
      }

      guard let user = result?.user,
        let idToken = user.idToken?.tokenString
      else {
        print("❌ Failed to obtain Google tokens")
        self?.isHandlingAuthentication = false
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

      // 🔒 Clear SecureLocalDataManager session
      SecureLocalDataManager.shared.signOut()

      print("✅ User signed out successfully")
    } catch {
      print("❌ Error signing out: \(error.localizedDescription)")
    }
  }

  // MARK: - Private methods

  private func handleAuthResult(result: AuthDataResult?, error: Error?, method: String) {
    defer { isHandlingAuthentication = false }  // Reset flag when done

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
    print("🔄 Firebase user displayName: '\(firebaseUser.displayName ?? "nil")'")
    print("🔄 Firebase user email: '\(firebaseUser.email ?? "nil")'")

    let userName = firebaseUser.displayName ?? "User"
    print("🔄 Using userName: '\(userName)'")

    let user = User(
      firebaseUID: firebaseUser.uid,
      name: userName,
      email: firebaseUser.email ?? "",
      isUserSaved: true,
      hasFaceIdEnabled: false
    )

    print("✅ Local user object created with name: '\(user.name)'")
    delegate?.authenticationDidComplete(user: user)
  }
}

// MARK: - Helper Method for Getting Current View Controller

private func getCurrentViewController() -> UIViewController? {
  if let windowScene = UIApplication.shared.connectedScenes
    .compactMap({ $0 as? UIWindowScene })
    .first(where: { $0.activationState == .foregroundActive })
  {

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
      return "auth.error.noPresentingController".localized
    case .googleTokenFailure:
      return "auth.error.googleTokenFailure".localized
    case .noUser:
      return "auth.error.noUser".localized
    case .invalidCredentials:
      return "auth.error.invalidCredentials".localized
    case .networkError:
      return "auth.error.networkError".localized
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

extension UIViewController {
  fileprivate func topMostViewController() -> UIViewController {
    if let presented = self.presentedViewController {
      return presented.topMostViewController()
    }

    if let navigationController = self as? UINavigationController {
      return navigationController.visibleViewController?.topMostViewController()
        ?? navigationController
    }

    if let tabBarController = self as? UITabBarController {
      return tabBarController.selectedViewController?.topMostViewController() ?? tabBarController
    }

    return self
  }
}
