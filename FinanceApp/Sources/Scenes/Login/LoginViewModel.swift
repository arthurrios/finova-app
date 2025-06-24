//
//  LoginViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Firebase
import Foundation

class LoginViewModel {
  var successResult: (() -> Void)?
  var errorResult: ((String, String) -> Void)?

  private let authManager = AuthenticationManager.shared

  init() {
    authManager.delegate = self
  }

  func authenticate(userEmail: String, password: String) {
    authManager.signIn(email: userEmail, password: password)
  }

  func signInWithGoogle() {
    authManager.signInWithGoogle()
  }
}

extension LoginViewModel: AuthenticationManagerDelegate {
  func authenticationDidComplete(user: User) {
    // Authenticate local data manager with Firebase UID
    if let firebaseUID = user.firebaseUID {
      SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)

      // Migrate existing data if needed
      SecureLocalDataManager.shared.migrateOldDataToUser(
        firebaseUID: firebaseUID, userEmail: user.email
      ) { success in
        if success {
          print("✅ Data migration completed successfully")
        } else {
          print("⚠️ Data migration had issues")
        }
      }
    }

    // Check if this is a returning user or new user
    let existingUser = UserDefaultsManager.getUser()
    let isReturningUser = existingUser?.firebaseUID == user.firebaseUID

    let updatedUser = User(
      firebaseUID: user.firebaseUID,
      name: user.name,
      email: user.email,
      isUserSaved: isReturningUser,  // Mark as saved only if returning user
      hasFaceIdEnabled: existingUser?.hasFaceIdEnabled ?? false  // Preserve existing Face ID setting
    )
    UserDefaultsManager.saveUser(user: updatedUser)
    print(
      "✅ User saved - isReturningUser: \(isReturningUser), hasFaceIdEnabled: \(updatedUser.hasFaceIdEnabled)"
    )

    DispatchQueue.main.async {
      self.successResult?()
    }
  }

  func authenticationDidFail(error: any Error) {
    DispatchQueue.main.async {
      let title = FirebaseErrorHandler.localizedTitle(for: error)
      let message = FirebaseErrorHandler.localizedMessage(for: error)
      self.errorResult?(title, message)
    }
  }
}
