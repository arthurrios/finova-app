//
//  AuthenticationManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 23/06/25.
//

import AuthenticationServices
import CryptoKit
import FirebaseAuth
import Foundation
import GoogleSignIn
import UIKit

protocol AuthenticationManagerDelegate: AnyObject {
    func authenticationDidComplete(user: User)
    func authenticationDidFail(error: Error)
}

class AuthenticationManager: NSObject {
    
    // MARK: - Singleton
    
    static let shared = AuthenticationManager()
    
    // MARK: - Properties
    
    weak var delegate: AuthenticationManagerDelegate?
    
    override init() {
        super.init()
        setupAuthStateListener()
    }
    
    // MARK: - Public Properties
    
    var currentUser: FirebaseAuth.User? {
        return Auth.auth().currentUser
    }
    
    var isAuthenticated: Bool {
        return currentUser != nil
    }
    
    // MARK: - Private Properties
    
    private var currentNonce: String?
    
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
            
            // Store Google profile image URL for later download
            let profileImageURL = user.profile?.imageURL(withDimension: 200)
            
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )
            
            Auth.auth().signIn(with: credential) { [weak self] authResult, authError in
                self?.handleAuthResult(
                    result: authResult, error: authError, method: "Google Sign-In",
                    googleProfileImageURL: profileImageURL)
            }
        }
    }
    
    // MARK: - Apple Sign-In
    
    func signInWithApple() {
        print("🍎 Attempting Apple Sign-In")
        isHandlingAuthentication = true
        
        // Generate nonce for security
        let nonce = randomNonceString()
        currentNonce = nonce
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
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
    
    // MARK: - Biometric Account Linking (Phase 7)
    private func handleAuthResult(
        result: AuthDataResult?, error: Error?, method: String, googleProfileImageURL: URL? = nil
    ) {
        defer { isHandlingAuthentication = false }
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
        handleSignInWithBiometricValidation(
            firebaseUser: firebaseUser,
            method: method,
            googleProfileImageURL: googleProfileImageURL
        )
    }
    
    private func handleSignInWithBiometricValidation(
        firebaseUser: FirebaseAuth.User,
        method: String,
        googleProfileImageURL: URL? = nil
    ) {
        let newEmail = firebaseUser.email ?? ""
        let validationResult = SecureLocalDataManager.shared.validateDataOwnershipWithBiometrics(
            for: firebaseUser.uid,
            email: newEmail
        )
        switch validationResult {
        case .valid:
            if !BiometricDataManager.shared.hasBiometricData() {
                SecureLocalDataManager.shared.registerFirstTimeUserWithBiometrics(
                    firebaseUID: firebaseUser.uid,
                    email: newEmail
                ) { [weak self] success in
                    if success {
                        self?.handleAuthenticatedUser(
                            firebaseUser, googleProfileImageURL: googleProfileImageURL)
                    } else {
                        self?.delegate?.authenticationDidFail(error: AuthError.biometricRegistrationFailed)
                    }
                }
            } else {
                handleAuthenticatedUser(firebaseUser, googleProfileImageURL: googleProfileImageURL)
            }
        case .requiresBiometricVerification(let existingEmail, let newEmail):
            performBiometricVerificationForAccountLinking(
                existingEmail: existingEmail,
                newEmail: newEmail,
                firebaseUser: firebaseUser,
                method: method,
                googleProfileImageURL: googleProfileImageURL
            )
        case .ownedByDifferentUser(let existingEmail, let newEmail):
            print("🔒 Data owned by different user: \(existingEmail) vs \(newEmail)")
            showDataOwnershipConflictAlert(existingEmail: existingEmail, newEmail: newEmail, firebaseUser: firebaseUser, method: method, googleProfileImageURL: googleProfileImageURL)
        case .accessDenied:
            print("❌ Access denied for security reasons")
            delegate?.authenticationDidFail(error: AuthError.accessDenied)
        }
    }
    
    private func performBiometricVerificationForAccountLinking(
        existingEmail: String,
        newEmail: String,
        firebaseUser: FirebaseAuth.User,
        method: String,
        googleProfileImageURL: URL? = nil
    ) {
        print("🔐 Performing biometric verification for account linking...")
        BiometricDataManager.shared.verifyUserBiometric { [weak self] result in
            switch result {
            case .verified(let linkedEmail):
                print("✅ Biometric verification successful - emails match: \(linkedEmail)")
                self?.showAccountSynchronizationPrompt(
                    existingEmail: existingEmail,
                    newEmail: newEmail,
                    firebaseUser: firebaseUser,
                    method: method,
                    googleProfileImageURL: googleProfileImageURL
                )
            case .verificationFailed:
                print("❌ Biometric verification failed - treating as new user")
                self?.handleNewUserAfterFailedBiometricVerification(
                    firebaseUser: firebaseUser,
                    method: method,
                    googleProfileImageURL: googleProfileImageURL
                )
            case .userCancelled:
                print("🚫 User cancelled biometric verification")
                self?.delegate?.authenticationDidFail(error: AuthError.biometricVerificationCancelled)
            case .userFallback:
                print("🔄 User chose fallback - treating as new user")
                self?.handleNewUserAfterFailedBiometricVerification(
                    firebaseUser: firebaseUser,
                    method: method,
                    googleProfileImageURL: googleProfileImageURL
                )
            case .notAvailable, .noRegisteredBiometric:
                print("⚠️ Biometric authentication not available - treating as new user")
                self?.handleNewUserAfterFailedBiometricVerification(
                    firebaseUser: firebaseUser,
                    method: method,
                    googleProfileImageURL: googleProfileImageURL
                )
            }
        }
    }
    
    private func handleNewUserAfterFailedBiometricVerification(
        firebaseUser: FirebaseAuth.User,
        method: String,
        googleProfileImageURL: URL? = nil
    ) {
        SecureLocalDataManager.shared.registerFirstTimeUserWithBiometrics(
            firebaseUID: firebaseUser.uid,
            email: firebaseUser.email ?? ""
        ) { [weak self] success in
            if success {
                self?.handleAuthenticatedUser(firebaseUser, googleProfileImageURL: googleProfileImageURL)
            } else {
                self?.delegate?.authenticationDidFail(error: AuthError.biometricRegistrationFailed)
            }
        }
    }
    
    private func showAccountSynchronizationPrompt(
        existingEmail: String,
        newEmail: String,
        firebaseUser: FirebaseAuth.User,
        method: String,
        googleProfileImageURL: URL? = nil
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let presentingVC = getCurrentViewController() else {
                print("❌ No presenting view controller for synchronization prompt")
                self?.delegate?.authenticationDidFail(error: AuthError.noPresentingController)
                return
            }
            let alert = UIAlertController(
                title: "🔐 Account Data Found",
                message: """
          We found existing data from your other account:
          \(existingEmail)
          \nWould you like to synchronize and access this data with your current sign-in?
          """,
                preferredStyle: .alert
            )
            alert.addAction(
                UIAlertAction(title: "Synchronize", style: .default) { _ in
                    self?.synchronizeAccountData(
                        firebaseUser: firebaseUser,
                        existingEmail: existingEmail,
                        newEmail: newEmail,
                        method: method,
                        googleProfileImageURL: googleProfileImageURL
                    )
                })
            alert.addAction(
                UIAlertAction(title: "Keep Separate", style: .default) { _ in
                    self?.createSeparateAccount(
                        firebaseUser: firebaseUser,
                        method: method,
                        googleProfileImageURL: googleProfileImageURL
                    )
                })
            presentingVC.present(alert, animated: true)
        }
    }
    
    private func synchronizeAccountData(
        firebaseUser: FirebaseAuth.User,
        existingEmail: String,
        newEmail: String,
        method: String,
        googleProfileImageURL: URL? = nil
    ) {
        print("🔄 User chose to synchronize accounts after biometric verification")
        SecureLocalDataManager.shared.handleBiometricAccountLinking(
            newFirebaseUID: firebaseUser.uid,
            newEmail: newEmail,
            linkToExistingData: true
        ) { [weak self] success in
            if success {
                DispatchQueue.main.async {
                    self?.handleAuthenticatedUser(firebaseUser, googleProfileImageURL: googleProfileImageURL)
                }
            } else {
                DispatchQueue.main.async {
                    self?.delegate?.authenticationDidFail(error: AuthError.synchronizationFailed)
                }
            }
        }
    }
    
    private func createSeparateAccount(
        firebaseUser: FirebaseAuth.User,
        method: String,
        googleProfileImageURL: URL? = nil
    ) {
        print("🆕 User chose to keep accounts separate - creating new account")
        SecureLocalDataManager.shared.handleBiometricAccountLinking(
            newFirebaseUID: firebaseUser.uid,
            newEmail: firebaseUser.email ?? "",
            linkToExistingData: false
        ) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.handleAuthenticatedUser(firebaseUser, googleProfileImageURL: googleProfileImageURL)
                } else {
                    self?.delegate?.authenticationDidFail(error: AuthError.accountCreationFailed)
                }
            }
        }
    }
    
    private func showDataOwnershipConflictAlert(
        existingEmail: String,
        newEmail: String,
        firebaseUser: FirebaseAuth.User,
        method: String,
        googleProfileImageURL: URL? = nil
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let presentingVC = getCurrentViewController() else {
                print("❌ No presenting view controller for data ownership conflict alert")
                self?.delegate?.authenticationDidFail(error: AuthError.noPresentingController)
                return
            }
            
            let alert = UIAlertController(
                title: "🔒 DataOwnership Conflict",
                message: """
          This device contains data owned by: \(existingEmail)
          \nYou're signing in with: \(newEmail)
          \n\nIf this is your data, you can reclaim ownership. Otherwise, start fresh.
          """,
                preferredStyle: .alert
            )
            
            alert.addAction(
                UIAlertAction(title: "Reclaim My Data", style: .default) { _ in
                    self?.handleReclaimDataOwnership(
                        firebaseUser: firebaseUser,
                        method: method,
                        googleProfileImageURL: googleProfileImageURL
                    )
                })
            
            alert.addAction(
                UIAlertAction(title: "Start Fresh", style: .destructive) { _ in
                    self?.handleStartFreshWithNewAccount(
                        firebaseUser: firebaseUser,
                        method: method,
                        googleProfileImageURL: googleProfileImageURL
                    )
                })
            
            alert.addAction(
                UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    self?.delegate?.authenticationDidFail(error: AuthError.userCancelled)
                })
            
            presentingVC.present(alert, animated: true)
        }
    }
    
    private func handleStartFreshWithNewAccount(
        firebaseUser: FirebaseAuth.User,
        method: String,
        googleProfileImageURL: URL? = nil
    ) {
        print("🆕 User chose to start fresh - clearing existing data")
        
        // Clear existing data ownership and user data
        SecureLocalDataManager.shared.clearDataOwnership()
        SecureLocalDataManager.shared.clearUserData()
        
        // Register as new user
        SecureLocalDataManager.shared.registerFirstTimeUserWithBiometrics(
            firebaseUID: firebaseUser.uid,
            email: firebaseUser.email ?? ""
        ) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.handleAuthenticatedUser(firebaseUser, googleProfileImageURL: googleProfileImageURL)
                } else {
                    self?.delegate?.authenticationDidFail(error: AuthError.accountCreationFailed)
                }
            }
        }
    }
    
    private func handleReclaimDataOwnership(
        firebaseUser: FirebaseAuth.User,
        method: String,
        googleProfileImageURL: URL? = nil
    ) {
        print("🔗 User chose to reclaim data ownership")
        
        // Reclaim data ownership for the current user
        SecureLocalDataManager.shared.reclaimDataOwnership(
            for: firebaseUser.uid,
            email: firebaseUser.email ?? ""
        )
        
        // Authenticate the user with the reclaimed data
        SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUser.uid)
        
        // Handle the authenticated user
        DispatchQueue.main.async { [weak self] in
            self?.handleAuthenticatedUser(firebaseUser, googleProfileImageURL: googleProfileImageURL)
        }
    }
    
    private func handleAuthenticatedUser(
        _ firebaseUser: FirebaseAuth.User, googleProfileImageURL: URL? = nil
    ) {
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
        
        // Download and save Google profile image if available
        if let imageURL = googleProfileImageURL {
            downloadAndSaveGoogleProfileImage(imageURL, for: firebaseUser.uid)
        }
        
        delegate?.authenticationDidComplete(user: user)
    }
    
    // MARK: - Google Profile Image Download
    
    private func downloadAndSaveGoogleProfileImage(_ imageURL: URL, for userUID: String) {
        print("📸 Downloading Google profile image from: \(imageURL)")
        
        // First authenticate the manager with the user's UID to check existing images
        SecureLocalDataManager.shared.authenticateUser(firebaseUID: userUID)
        
        // Check if user already has a profile image - don't overwrite existing images
        if SecureLocalDataManager.shared.loadProfileImage() != nil {
            print("ℹ️ User already has a profile image - skipping Google profile image download")
            return
        }
        
        URLSession.shared.dataTask(with: imageURL) { data, _, error in
            if let error = error {
                print("❌ Failed to download Google profile image: \(error.localizedDescription)")
                return
            }
            
            guard let data = data, let image = UIImage(data: data) else {
                print("❌ Failed to create UIImage from downloaded data")
                return
            }
            
            print("✅ Google profile image downloaded successfully")
            
            // Save the image using SecureLocalDataManager
            SecureLocalDataManager.shared.saveProfileImage(image)
            
            print("✅ Google profile image saved to secure storage")
        }.resume()
    }
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError(
                        "Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            return String(format: "%02x", $0)
        }.joined()
        
        return hashString
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
    case appleTokenFailure
    case invalidState
    case biometricRegistrationFailed
    case biometricVerificationCancelled
    case accessDenied
    case synchronizationFailed
    case accountCreationFailed
    case userCancelled
    
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
        case .appleTokenFailure:
            return "auth.error.appleIDToken".localized
        case .invalidState:
            return "auth.error.invalidState".localized
        case .biometricRegistrationFailed:
            return "auth.error.biometricRegistrationFailed".localized
        case .biometricVerificationCancelled:
            return "auth.error.biometricVerificationCancelled".localized
        case .accessDenied:
            return "auth.error.accessDenied".localized
        case .synchronizationFailed:
            return "auth.error.synchronizationFailed".localized
        case .accountCreationFailed:
            return "auth.error.accountCreationFailed".localized
        case .userCancelled:
            return "auth.error.userCancelled".localized
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
        case .appleTokenFailure:
            return "Please try again"
        case .invalidState:
            return "Please contact support if this issue persists"
        case .biometricRegistrationFailed:
            return "Please try again or contact support"
        case .biometricVerificationCancelled:
            return "Please try again or contact support"
        case .accessDenied:
            return "Please contact support if this issue persists"
        case .synchronizationFailed:
            return "Please try again or contact support"
        case .accountCreationFailed:
            return "Please try again or contact support"
        case .userCancelled:
            return "Please try again or contact support"
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

// MARK: - ASAuthorizationControllerDelegate
extension AuthenticationManager: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            
            guard let nonce = currentNonce else {
                print("❌ Invalid state: A login callback was received, but no login request was sent.")
                isHandlingAuthentication = false
                delegate?.authenticationDidFail(error: AuthError.invalidState)
                return
            }
            
            guard let appleIDToken = appleIDCredential.identityToken else {
                print("❌ Unable to fetch identity token")
                isHandlingAuthentication = false
                delegate?.authenticationDidFail(error: AuthError.appleTokenFailure)
                return
            }
            
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                print("❌ Unable to serialize token string from data: \(appleIDToken.debugDescription)")
                isHandlingAuthentication = false
                delegate?.authenticationDidFail(error: AuthError.appleTokenFailure)
                return
            }
            
            print("✅ Apple ID tokens obtained successfully")
            
            // Initialize the Firebase credential
            let credential = OAuthProvider.credential(
                providerID: AuthProviderID.apple,
                idToken: idTokenString,
                rawNonce: nonce)
            // Sign in with Firebase
            Auth.auth().signIn(with: credential) { [weak self] authResult, error in
                self?.handleAuthResult(result: authResult, error: error, method: "Apple Sign-In")
            }
        }
    }
    
    func authorizationController(
        controller: ASAuthorizationController, didCompleteWithError error: any Error
    ) {
        print("❌ Apple Sign-In failed: \(error.localizedDescription)")
        isHandlingAuthentication = false
        delegate?.authenticationDidFail(error: error)
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension AuthenticationManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let window = getCurrentViewController()?.view.window else {
            return UIWindow()
        }
        return window
    }
}
