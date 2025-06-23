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

      // Check if user has Face ID enabled
      if let localUser = UserDefaultsManager.getUser(), localUser.isUserSaved {
        if localUser.hasFaceIdEnabled {
          print("🔒 Face ID enabled - requesting biometric authentication")
          authenticateWithFaceID()
        } else {
          print("ℹ️ Face ID not enabled - asking user if they want to enable it")
          askToEnableFaceID(for: localUser)
        }
      } else {
        print("ℹ️ No saved user found - going to dashboard")
        flowDelegate?.navigateToDirectlyToDashboard()
      }
    } else {
      print("ℹ️ No Firebase user found, checking local user...")

      // Check for legacy local users (pre-Firebase)
      if let localUser = UserDefaultsManager.getUser(), localUser.isUserSaved {
        if localUser.hasFaceIdEnabled {
          print("🔒 Legacy user has Face ID enabled - requesting authentication")
          authenticateWithFaceID()
        } else {
          print("ℹ️ Legacy user does not have Face ID enabled - asking if they want to enable it")
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
        self.flowDelegate?.navigateToDirectlyToDashboard()
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
            break
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
    navigateToLogin()
  }

  private func logoutUser() {
    // Sign out from Firebase and clear local data
    AuthenticationManager.shared.signOut()
    UserDefaultsManager.removeUser()
    SecureLocalDataManager.shared.signOut()

    // Navigate to login
    gradientLayer.removeFromSuperlayer()
    navigateToLogin()
  }

  private func askToEnableFaceID(for user: User) {
    // Check if Face ID is available on this device
    guard FaceIDManager.shared.isFaceIDAvailable else {
      print("ℹ️ Face ID not available on this device - going to dashboard")
      flowDelegate?.navigateToDirectlyToDashboard()
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
      // Update user to enable Face ID
      let updatedUser = User(
        firebaseUID: user.firebaseUID,
        name: user.name,
        email: user.email,
        isUserSaved: true,
        hasFaceIdEnabled: true
      )
      UserDefaultsManager.saveUser(user: updatedUser)
      print("✅ \(biometricType) enabled and saved - proceeding to authentication")

      // Verify the save worked
      if let savedUser = UserDefaultsManager.getUser() {
        print("🔍 VERIFICATION: Saved user hasFaceIdEnabled: \(savedUser.hasFaceIdEnabled)")
      } else {
        print("❌ ERROR: Failed to save user!")
      }

      // Now authenticate with the newly enabled Face ID
      self.authenticateWithFaceID()
    }

    let skipAction = UIAlertAction(title: "skip".localized, style: .cancel) { _ in
      print("ℹ️ User chose to skip \(biometricType) - going to dashboard")
      self.flowDelegate?.navigateToDirectlyToDashboard()
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
