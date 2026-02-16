//
//  SplashViewController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Firebase
import Foundation
import LocalAuthentication
import UIKit

final class SplashViewController: UIViewController {
  let viewModel = SplashViewModel()
  let contentView: SplashView
  public weak var flowDelegate: SplashFlowDelegate?

  private let gradientLayer = Colors.gradientBlack

  #if DEBUG
  /// Set to `true` to skip login and go straight to Dashboard with test credentials.
  /// Disable this (or set to `false`) when you want to test the normal auth flow.
  private let autoLoginEnabled = true
  /// Set to `true` to clear and repopulate demo data on every auto-login.
  /// Set to `false` to keep existing data untouched.
  private let seedDemoData = false
  private let debugEmail = "jack@email.com"
  private let debugPassword = "Test@123"
  #endif

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
    #if DEBUG
    if autoLoginEnabled {
      performDebugAutoLogin()
      return
    }
    #endif

    if let firebaseUser = AuthenticationManager.shared.currentUser {
      // Set current user UID BEFORE sync starts — sync post-actions need UID
      UIDUserDefaultsManager.shared.currentUserUID = firebaseUser.uid
      DBHelper.shared.backfillUserIds(uid: firebaseUser.uid)

      // One-time cleanup of ghost records inserted by CloudKit sync
      let didCleanup = Self.performCloudGhostCleanupIfNeeded()

      // One-time fix: tag credit cards + missed transactions with shared_group_id for mirror mode
      Self.performMirrorModeCreditCardFixIfNeeded()

      // Trigger iCloud sync on launch (skip if cleanup just ran to prevent re-corruption)
      if !didCleanup {
        let needsRePush = Self.performSyncRePushIfNeeded()
        SyncEngine.shared.performFullSync(forceFullFetch: needsRePush, forceRePush: needsRePush)
      }
      BudgetAllocationRepository.migrateFromUserDefaultsIfNeeded()

      // Check if this user has existing settings
      let existingSettings = UIDUserDefaultsManager.shared.getUserSettings(for: firebaseUser.uid)
      var localUser: User?

      if let settings = existingSettings {
        // Returning user - use their saved settings
        // Smart name preservation: if Firebase has a better name, use it
        var bestName = settings.name
        let firebaseName = firebaseUser.displayName ?? ""
        if !firebaseName.isEmpty && firebaseName != "User"
          && (settings.name.isEmpty || settings.name == "User")
        {
          bestName = firebaseName
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
      } else {
        // Smart name preservation logic for new users
        var finalName = firebaseUser.displayName ?? ""
        if finalName.isEmpty {
          finalName = "User"
        }

        localUser = User(
          firebaseUID: firebaseUser.uid,
          name: finalName,
          email: firebaseUser.email ?? "",
          isUserSaved: true,  // Mark as saved since they're authenticated with Firebase
          hasFaceIdEnabled: false  // New users start with Face ID disabled
        )
      }

      if let user = localUser {
        UserDefaultsManager.saveUserWithUID(user: user)

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
            authenticateWithFaceID()
          } else {
            flowDelegate?.navigateDirectlyToDashboard()
          }
        } else {
          // New user or user without biometric enabled - go to login
          animateLogoUp()
        }
      } else {
        animateLogoUp()
      }
    } else {
      // Check for legacy local users (pre-Firebase)
      if let localUser = UserDefaultsManager.getUser(), localUser.isUserSaved {
        if UserDefaultsManager.getBiometricEnabled() {
          authenticateWithFaceID()
        } else {
          askToEnableFaceID(for: localUser)
        }
      } else {
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
      logError("Face ID not available on this device")
      handleFaceIDFailure()
      return
    }

    let reason = "faceid.reason".localized

    FaceIDManager.shared.authenticateWithBiometrics(reason: reason) { [weak self] success, error in
      guard let self = self else { return }

      if success {
        // Since Face ID authentication was successful, ensure global biometric setting is enabled
        UserDefaultsManager.setBiometricEnabled(true)

        // Ensure Firebase user is still available before navigating
        if let firebaseUser = AuthenticationManager.shared.currentUser {
          // Final safety check before navigation
          DispatchQueue.main.async {
            self.flowDelegate?.navigateDirectlyToDashboard()
          }
        } else {
          logError("Firebase user lost after Face ID authentication")
          self.handleFaceIDFailure()
        }
      } else {
        if let errorDescription = error?.localizedDescription {
          logError("Face ID authentication failed: \(errorDescription)")
        }

        // Check if it's a failed authentication (not user cancellation)
        if let laError = error as? LAError {
          switch laError.code {
          case .authenticationFailed:
            // Face ID doesn't match - logout immediately
            self.logoutUser()
            return
          case .userCancel, .systemCancel:
            // User cancelled - just go to login
            break
          case .biometryLockout:
            // Too many failed attempts - logout for security
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

      // Ensure Firebase user is still available
      if let firebaseUser = AuthenticationManager.shared.currentUser {
        // Now authenticate with the newly enabled Face ID
        self.authenticateWithFaceID()
      } else {
        logError("Firebase user lost during Face ID setup")
        self.handleFaceIDFailure()
      }
    }

    let skipAction = UIAlertAction(title: "skip".localized, style: .cancel) { _ in
      // User chose to skip Face ID setup
      UserDefaultsManager.updateCurrentUserSavedStatus(saved: true)
      // Don't change global biometric setting when user skips

      // Ensure Firebase user is still available before navigating
      if let firebaseUser = AuthenticationManager.shared.currentUser {
        // Final safety check before navigation
        DispatchQueue.main.async {
          self.flowDelegate?.navigateDirectlyToDashboard()
        }
      } else {
        logError("Firebase user lost during Face ID skip")
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

// MARK: - DEBUG Auto-Login
#if DEBUG
extension SplashViewController {
  /// Signs in with test credentials and navigates directly to Dashboard,
  /// skipping splash animations, Face ID prompts, and the login screen entirely.
  private func performDebugAutoLogin() {
    logInfo("[DEBUG] Auto-login: signing in with \(debugEmail)")

    Auth.auth().signIn(withEmail: debugEmail, password: debugPassword) { [weak self] result, error in
      guard let self = self else { return }

      if let error = error {
        logError("[DEBUG] Auto-login failed: \(error.localizedDescription). Falling back to normal flow.")
        DispatchQueue.main.async {
          self.animateLogoUp()
        }
        return
      }

      guard let firebaseUser = result?.user else {
        logError("[DEBUG] Auto-login: no user returned. Falling back to normal flow.")
        DispatchQueue.main.async {
          self.animateLogoUp()
        }
        return
      }

      logInfo("[DEBUG] Auto-login succeeded for UID: \(firebaseUser.uid)")

      // Replicate the same setup that LoginViewModel.authenticationDidComplete performs
      UIDUserDefaultsManager.shared.currentUserUID = firebaseUser.uid
      DBHelper.shared.backfillUserIds(uid: firebaseUser.uid)
      let didCleanup = Self.performCloudGhostCleanupIfNeeded()
      if !didCleanup {
        SyncEngine.shared.performFullSync(forceFullFetch: true)
      }

      let existingSettings = UIDUserDefaultsManager.shared.getUserSettings(for: firebaseUser.uid)

      let user: User
      if let settings = existingSettings {
        var updatedSettings = settings
        updatedSettings.lastSignIn = Date()
        UIDUserDefaultsManager.shared.saveUserSettings(for: firebaseUser.uid, settings: updatedSettings)

        user = User(
          firebaseUID: firebaseUser.uid,
          name: settings.name,
          email: settings.email,
          isUserSaved: settings.isUserSaved,
          hasFaceIdEnabled: settings.hasFaceIdEnabled
        )
      } else {
        let displayName = firebaseUser.displayName ?? "User"
        user = User(
          firebaseUID: firebaseUser.uid,
          name: displayName,
          email: firebaseUser.email ?? "",
          isUserSaved: true,
          hasFaceIdEnabled: false
        )
      }

      UserDefaultsManager.saveUserWithUID(user: user)
      UserDefaultsManager.updateCurrentUserSavedStatus(saved: true)

      if self.seedDemoData {
        DemoSeedGenerator.seed(for: firebaseUser.uid)
      }

      DispatchQueue.main.async {
        if FaceIDManager.shared.deviceSupportsBiometrics && !UserDefaultsManager.getBiometricEnabled() {
          self.askToEnableFaceIDAfterAutoLogin(for: user)
        } else {
          self.flowDelegate?.navigateDirectlyToDashboard()
        }
      }
    }
  }

  private func askToEnableFaceIDAfterAutoLogin(for user: User) {
    guard FaceIDManager.shared.deviceSupportsBiometrics else {
      flowDelegate?.navigateDirectlyToDashboard()
      return
    }

    let biometricType = FaceIDManager.shared.biometricTypeString
    let alertController = UIAlertController(
      title: String(format: "faceid.enable.title".localized, biometricType),
      message: String(format: "faceid.enable.message".localized, biometricType),
      preferredStyle: .alert
    )

    let yesAction = UIAlertAction(
      title: String(format: "faceid.enable.button".localized, biometricType), style: .default
    ) { _ in
      if FaceIDManager.shared.isFaceIDAvailable {
        UserDefaultsManager.setBiometricEnabled(true)
        logInfo("[DEBUG] \(biometricType) enabled globally for app")
        self.flowDelegate?.navigateDirectlyToDashboard()
      } else {
        let settingsAlert = UIAlertController(
          title: biometricType,
          message: String(
            format: "settings.biometric.notEnrolled.message".localized,
            biometricType
          ),
          preferredStyle: .alert
        )
        let openAction = UIAlertAction(
          title: "settings.biometric.openSettings".localized,
          style: .default
        ) { _ in
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
          }
          self.flowDelegate?.navigateDirectlyToDashboard()
        }
        let cancelAction = UIAlertAction(title: "skip".localized, style: .cancel) { _ in
          self.flowDelegate?.navigateDirectlyToDashboard()
        }
        settingsAlert.addAction(openAction)
        settingsAlert.addAction(cancelAction)
        self.present(settingsAlert, animated: true)
      }
    }

    let noAction = UIAlertAction(title: "skip".localized, style: .cancel) { _ in
      self.flowDelegate?.navigateDirectlyToDashboard()
    }

    alertController.addAction(yesAction)
    alertController.addAction(noAction)
    present(alertController, animated: true)
  }
}
#endif

// MARK: - One-Time Sync Re-Push

extension SplashViewController {
  private static let syncRePushKey = "hasPerformedSyncRePush_v4"

  /// One-time: resets all sync_status to 'pending' so data gets re-pushed to CloudKit.
  /// Returns `true` if the re-push was triggered.
  static func performSyncRePushIfNeeded() -> Bool {
    guard !UserDefaults.standard.bool(forKey: syncRePushKey) else {
      return false
    }
    logWarning("[SyncRePush] Triggering one-time full re-push of all data to CloudKit")
    UserDefaults.standard.set(true, forKey: syncRePushKey)
    return true
  }
}

// MARK: - One-Time Mirror Mode Credit Card Fix

extension SplashViewController {
  private static let mirrorCCFixKey = "hasPerformedMirrorCCFix_v1"

  /// One-time: if mirror mode is active, tag credit cards and any missed transactions with shared_group_id.
  static func performMirrorModeCreditCardFixIfNeeded() {
    guard !UserDefaults.standard.bool(forKey: mirrorCCFixKey) else { return }
    guard MirrorModeManager.shared.isEnabled,
          let groupId = MirrorModeManager.shared.linkedGroupId,
          let uid = UIDUserDefaultsManager.shared.currentUserUID
    else {
      // No mirror mode — mark as done so we don't check again
      UserDefaults.standard.set(true, forKey: mirrorCCFixKey)
      return
    }

    logWarning("[MirrorCCFix] Tagging untagged credit cards and transactions with group \(groupId)")

    let db = DBHelper.shared

    // Tag credit cards
    db.executeSyncUpdate(
      "UPDATE CreditCards SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND shared_group_id IS NULL AND is_deleted = 0;",
      textBindings: [groupId, uid]
    )

    // Tag any missed transactions (e.g. installment parents/children)
    db.executeSyncUpdate(
      "UPDATE Transactions SET shared_group_id = ?, sync_status = 'pending' WHERE user_id = ? AND shared_group_id IS NULL AND (is_deleted IS NULL OR is_deleted = 0);",
      textBindings: [groupId, uid]
    )

    TransactionRepository.invalidateCache()
    UserDefaults.standard.set(true, forKey: mirrorCCFixKey)
    logWarning("[MirrorCCFix] Complete")
  }
}

// MARK: - One-Time Cloud Ghost Cleanup

extension SplashViewController {
  private static let cloudGhostCleanupKey = "hasPerformedCloudGhostCleanup_v5"

  /// Runs one-time cleanup to fix data corrupted by CloudKit sync.
  /// Returns `true` if cleanup ran this launch (caller should skip sync).
  @discardableResult
  static func performCloudGhostCleanupIfNeeded() -> Bool {
    guard !UserDefaults.standard.bool(forKey: cloudGhostCleanupKey) else {
      return false
    }

    logWarning("[GhostCleanup-v5] Starting: clean SQLite and reset sync tokens")

    // 1. Clean SQLite (remove CK ghosts)
    let repo = TransactionRepository()
    repo.removeCloudInsertedRecords()

    // 2. Reset CloudKit change tokens so stale records aren't re-pulled
    SyncStateManager.shared.resetAllTokens()

    // 3. Invalidate the in-memory cache one final time (belt-and-suspenders)
    TransactionRepository.invalidateCache()

    UserDefaults.standard.set(true, forKey: cloudGhostCleanupKey)
    logWarning("[GhostCleanup-v5] Complete")
    return true
  }
}
