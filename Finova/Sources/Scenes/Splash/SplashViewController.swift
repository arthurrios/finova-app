//
//  SplashViewController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import LocalAuthentication
import UIKit

final class SplashViewController: UIViewController {
  let viewModel = SplashViewModel()
  let contentView: SplashView
  public weak var flowDelegate: SplashFlowDelegate?

  private let gradientLayer = Colors.gradientBlack

  init(contentView: SplashView, flowDelegate: SplashFlowDelegate) {
    self.contentView = contentView
    self.flowDelegate = flowDelegate
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setup()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    gradientLayer.frame = view.bounds
    view.layer.insertSublayer(gradientLayer, at: 0)
  }

  private func decideNavigationFlow() {
    if let firebaseUser = AuthenticationManager.shared.currentUser {
      print("✅ Firebase user found: \(firebaseUser.email ?? "No email")")

      // Authenticate local data manager with Firebase UID
      SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUser.uid)

      // Set current user UID for settings lookup
      UIDUserDefaultsManager.shared.currentUserUID = firebaseUser.uid

      // Check if this user has existing settings
      let existingSettings = UIDUserDefaultsManager.shared.getUserSettings(for: firebaseUser.uid)
      var localUser: User?

      if let settings = existingSettings {
        // Returning user - use their saved settings
        print("🔄 Loading existing user settings for: \(settings.name)")

        // Smart name preservation: if Firebase has a better name, use it
        var bestName = settings.name
        let firebaseName = firebaseUser.displayName ?? ""
        if !firebaseName.isEmpty && firebaseName != "User"
          && (settings.name.isEmpty || settings.name == "User")
        {
          bestName = firebaseName
          print("📝 Updating saved name from '\(settings.name)' to '\(firebaseName)' from Firebase")
        } else if settings.name.isEmpty || settings.name == "User" {
          bestName = firebaseName.isEmpty ? "User" : firebaseName
        }

        var updatedSettings = settings
        updatedSettings.name = bestName  // Update with best available name
        updatedSettings.lastSignIn = Date()
        UIDUserDefaultsManager.shared.saveUserSettings(
          for: firebaseUser.uid, settings: updatedSettings)

        localUser = User(
          firebaseUID: firebaseUser.uid,
          name: bestName,  // Use best available name
          email: settings.email,
          isUserSaved: settings.isUserSaved,
          hasFaceIdEnabled: settings.hasFaceIdEnabled  // Use saved Face ID setting
        )

        print("✅ Restored user: '\(bestName)', faceId: \(settings.hasFaceIdEnabled)")
      } else {
        print("🔄 Syncing new Firebase user to UserDefaults...")

        // Smart name preservation logic for new users
        var finalName = firebaseUser.displayName ?? ""
        if finalName.isEmpty {
          finalName = "User"
          print("⚠️ No name available, falling back to 'User'")
        } else {
          print("📝 Using Firebase display name: '\(finalName)'")
        }

        localUser = User(
          firebaseUID: firebaseUser.uid,
          name: finalName,
          email: firebaseUser.email ?? "",
          isUserSaved: true,  // Mark as saved since they're authenticated with Firebase
          hasFaceIdEnabled: false  // New users start with Face ID disabled
        )

        print("✅ Created new user: '\(finalName)', faceId: false")
      }

      if let user = localUser {
        UserDefaultsManager.saveUserWithUID(user: user)
        print("✅ User data synced with UID-based system")

        // Ensure user settings are properly created
        UserDefaultsManager.updateCurrentUserSavedStatus(saved: user.isUserSaved)
        if user.hasFaceIdEnabled {
          UserDefaultsManager.updateCurrentUserFaceID(enabled: true)
        }
      }

      // For existing users, proceed with Face ID check using global biometric setting
      // For new users, they should go to login first
      if let user = localUser {
        if user.isUserSaved && UserDefaultsManager.getBiometricEnabled() {
          // Existing user with biometric enabled - authenticate with Face ID
          if FaceIDManager.shared.isFaceIDAvailable {
            print("🔒 Biometric enabled globally - requesting biometric authentication")
            authenticateWithFaceID()
          } else {
            print("ℹ️ Biometric not available - proceeding to dashboard")
            flowDelegate?.navigateDirectlyToDashboard()
          }
        } else {
          // New user or user without biometric enabled - go to login
          print("ℹ️ New user or biometric not enabled - showing login")
          animateLogoUp()
        }
      } else {
        print("⚠️ Failed to create local user - showing login")
        animateLogoUp()
      }
    } else {
      print("ℹ️ No Firebase user found, checking local user...")

      // Check for legacy local users (pre-Firebase)
      if let localUser = UserDefaultsManager.getUser(), localUser.isUserSaved {
        if UserDefaultsManager.getBiometricEnabled() {
          print("🔒 Biometric enabled globally - requesting authentication")
          authenticateWithFaceID()
        } else {
          print("ℹ️ Biometric not enabled globally - asking if they want to enable it")
          askToEnableFaceID(for: localUser)
        }
      } else {
        print("ℹ️ No user found - showing login")
        // No user found - show login
        animateLogoUp()
      }
    }
  }

  private func setup() {
    self.view.backgroundColor = Colors.gray100
    self.view.addSubview(contentView)
    self.navigationController?.isNavigationBarHidden = true

    buildHierarchy()

    startAnimation()
  }

  private func buildHierarchy() {
    setupContentViewToBounds(contentView: contentView)
  }

  @objc
  private func navigateToLogin() {
    self.flowDelegate?.navigateToLogin()
  }
}

// MARK: - Animations
extension SplashViewController {
  private func startAnimation() {

    viewModel.saveInitialDate()

    viewModel.performInitialAnimation { [weak self] in
      guard let self else { return }

      UIView.animate(
        withDuration: 1,
        animations: {
          self.contentView.logoImageView.alpha = 1
        },
        completion: { _ in
          self.decideNavigationFlow()
        })
    }
  }

  private func animateLogoUp() {
    UIView.animate(
      withDuration: 1, delay: 0, options: [.curveEaseOut],
      animations: {
        self.contentView.logoImageView.transform = self.contentView.logoImageView.transform
          .translatedBy(x: 0, y: -200)
          .scaledBy(x: 1.15, y: 1.15)
      },
      completion: { _ in
        UIView.animate(
          withDuration: 1,
          animations: {
            self.contentView.loginImageView.alpha = 1
          })

        let fadeAnimation = CABasicAnimation(keyPath: "opacity")
        fadeAnimation.fromValue = 1
        fadeAnimation.toValue = 0
        fadeAnimation.duration = 1
        fadeAnimation.fillMode = .forwards
        fadeAnimation.isRemovedOnCompletion = false
        self.gradientLayer.add(fadeAnimation, forKey: "fade")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
          self.gradientLayer.removeFromSuperlayer()
          self.navigateToLogin()
        }
      })
  }
}

// MARK: - FaceID
extension SplashViewController {
  private func authenticateWithFaceID() {
    // Check if Face ID is available
    guard FaceIDManager.shared.isFaceIDAvailable else {
      print("❌ Face ID not available on this device")
      handleFaceIDFailure()
      return
    }

    let reason = "faceid.reason".localized

    FaceIDManager.shared.authenticateWithBiometrics(reason: reason) { [weak self] success, error in
      guard let self = self else { return }

      if success {
        print("✅ Face ID authentication successful")
        // Since Face ID authentication was successful, ensure global biometric setting is enabled
        UserDefaultsManager.setBiometricEnabled(true)
        print("✅ Global biometric setting enabled after successful authentication")

        // Ensure Firebase user is still available before navigating
        if let firebaseUser = AuthenticationManager.shared.currentUser {
          print("✅ Firebase user still available: \(firebaseUser.uid)")
          // Re-authenticate SecureLocalDataManager to ensure it's properly set
          SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUser.uid)

          // Final safety check before navigation
          DispatchQueue.main.async {
            self.flowDelegate?.navigateDirectlyToDashboard()
          }
        } else {
          print("❌ Firebase user lost after Face ID authentication - going to login")
          self.handleFaceIDFailure()
        }
      } else {
        print("❌ Face ID authentication failed: \(error?.localizedDescription ?? "Unknown error")")

        // Check if it's a failed authentication (not user cancellation)
        if let laError = error as? LAError {
          switch laError.code {
          case .authenticationFailed:
            // Face ID doesn't match - logout immediately
            print("🚨 Face ID authentication failed - logging out user")
            self.logoutUser()
            return
          case .userCancel, .systemCancel:
            // User cancelled - just go to login
            print("ℹ️ User cancelled Face ID authentication")
          case .biometryLockout:
            // Too many failed attempts - logout for security
            print("🚨 Biometry locked out - logging out user")
            self.logoutUser()
            return
          default:
            break
          }
        }

        self.handleFaceIDFailure()
      }
    }
  }

  private func handleFaceIDFailure() {
    // Show login screen without logging out (for cancellations)
    gradientLayer.removeFromSuperlayer()

    // Ensure navigation happens on main thread
    DispatchQueue.main.async {
      self.navigateToLogin()
    }
  }

  private func logoutUser() {
    // Sign out from Firebase and clear local data
    AuthenticationManager.shared.signOut()
    UserDefaultsManager.removeUser()
    SecureLocalDataManager.shared.signOut()

    // Navigate to login
    gradientLayer.removeFromSuperlayer()

    // Ensure navigation happens on main thread
    DispatchQueue.main.async {
      self.navigateToLogin()
    }
  }

  private func askToEnableFaceID(for user: User) {
    // Check if Face ID is available on this device
    guard FaceIDManager.shared.isFaceIDAvailable else {
      print("ℹ️ Face ID not available on this device - going to dashboard")
      flowDelegate?.navigateDirectlyToDashboard()
      return
    }

    let biometricType = FaceIDManager.shared.biometricTypeString
    let alertController = UIAlertController(
      title: String(format: "faceid.enable.title".localized, biometricType),
      message: String(format: "faceid.enable.message".localized, biometricType),
      preferredStyle: .alert
    )

    let enableAction = UIAlertAction(
      title: String(format: "faceid.enable.button".localized, biometricType), style: .default
    ) { _ in
      // Ensure user settings are created before updating Face ID
      UserDefaultsManager.updateCurrentUserSavedStatus(saved: true)
      UserDefaultsManager.updateCurrentUserFaceID(enabled: true)

      // Enable biometric globally for the app
      UserDefaultsManager.setBiometricEnabled(true)
      print("✅ \(biometricType) enabled globally for app - proceeding to authentication")

      // Verify the save worked
      let isBiometricEnabled = UserDefaultsManager.getBiometricEnabled()
      print("🔍 VERIFICATION: Global biometric enabled: \(isBiometricEnabled)")

      // Ensure Firebase user is still available
      if let firebaseUser = AuthenticationManager.shared.currentUser {
        print("✅ Firebase user available for Face ID setup: \(firebaseUser.uid)")
        // Ensure SecureLocalDataManager is authenticated
        SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUser.uid)
        // Now authenticate with the newly enabled Face ID
        self.authenticateWithFaceID()
      } else {
        print("❌ Firebase user lost during Face ID setup - going to login")
        self.handleFaceIDFailure()
      }
    }

    let skipAction = UIAlertAction(title: "skip".localized, style: .cancel) { _ in
      // User chose to skip Face ID setup
      UserDefaultsManager.updateCurrentUserSavedStatus(saved: true)
      // Don't change global biometric setting when user skips
      print("⏭️ User skipped \(biometricType) setup")

      // Ensure Firebase user is still available before navigating
      if let firebaseUser = AuthenticationManager.shared.currentUser {
        print("✅ Firebase user available for dashboard navigation: \(firebaseUser.uid)")
        // Ensure SecureLocalDataManager is authenticated
        SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUser.uid)

        // Final safety check before navigation
        DispatchQueue.main.async {
          self.flowDelegate?.navigateDirectlyToDashboard()
        }
      } else {
        print("❌ Firebase user lost during Face ID skip - going to login")
        self.handleFaceIDFailure()
      }
    }

    alertController.addAction(enableAction)
    alertController.addAction(skipAction)
    present(alertController, animated: true)
  }

  private func showReAuthenticationPrompt() {
    // Legacy user detected - encourage Firebase upgrade
    let alertController = UIAlertController(
      title: "Account Upgrade Required",
      message: "Please sign in again to upgrade your account security.",
      preferredStyle: .alert
    )

    let okAction = UIAlertAction(title: "Sign In", style: .default) { _ in
      self.gradientLayer.removeFromSuperlayer()
      self.navigateToLogin()
    }

    alertController.addAction(okAction)
    present(alertController, animated: true)
  }
}
