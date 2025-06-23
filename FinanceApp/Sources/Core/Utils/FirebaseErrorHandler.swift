//
//  FirebaseErrorHandler.swift
//  FinanceApp
//
//  Created by Arthur Rios on 25/06/25.
//

import FirebaseAuth
import Foundation

struct FirebaseErrorHandler {

  static func localizedMessage(for error: Error) -> String {
    if let authError = error as NSError? {
      switch AuthErrorCode(rawValue: authError.code) {
      case .emailAlreadyInUse:
        return "auth.error.emailAlreadyInUse".localized

      case .invalidEmail:
        return "auth.error.invalidEmail".localized

      case .weakPassword:
        return "auth.error.weakPassword".localized

      case .userNotFound:
        return "auth.error.userNotFound".localized

      case .wrongPassword:
        return "auth.error.wrongPassword".localized

      case .tooManyRequests:
        return "auth.error.tooManyRequests".localized

      case .networkError:
        return "auth.error.networkError".localized

      default:
        return error.localizedDescription
      }
    }

    return error.localizedDescription
  }

  static func localizedTitle(for error: Error) -> String {
    if error is AuthError {
      return "auth.error.title".localized
    }

    // Check if it's a Firebase auth error
    if let authError = error as NSError?, authError.domain == "FIRAuthErrorDomain" {
      return "auth.error.title".localized
    }

    return "validation.error.title".localized
  }
}
