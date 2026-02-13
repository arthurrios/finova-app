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
                // Only handle auth state change if not already handling authentication
                if self?.isHandlingAuthentication == false {
                    self?.handleAuthenticatedUser(user)
                }
            } else {
                self?.isHandlingAuthentication = false
            }
        }
    }
    
    // MARK: - Email/Password Authentication
    
    func signIn(email: String, password: String) {
        isHandlingAuthentication = true

        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            self?.handleAuthResult(result: result, error: error, method: "Email/Password", extractedDisplayName: nil)
        }
    }
    
    func register(name: String, email: String, password: String) {
        isHandlingAuthentication = true

        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            if let error = error {
                logError("Registration failed: \(error.localizedDescription)")
                self?.isHandlingAuthentication = false
                self?.delegate?.authenticationDidFail(error: error)
                return
            }

            if let user = result?.user {
                let changeRequest = user.createProfileChangeRequest()
                changeRequest.displayName = name
                changeRequest.commitChanges { [weak self] profileError in
                    if let profileError = profileError {
                        logError("Failed to update display name: \(profileError.localizedDescription)")
                        // Still proceed with authentication even if display name update fails
                        self?.handleAuthResult(result: result, error: error, method: "Registration", extractedDisplayName: name)
                    } else {
                        // Reload the user to get the updated display name
                        user.reload { reloadError in
                            if let reloadError = reloadError {
                                logError("Failed to reload user after display name update: \(reloadError.localizedDescription)")
                            }
                            // Now handle authentication with updated display name
                            self?.handleAuthResult(result: result, error: error, method: "Registration", extractedDisplayName: name)
                        }
                    }
                }
            } else {
                // No user object, handle auth result immediately
                self?.handleAuthResult(result: result, error: error, method: "Registration", extractedDisplayName: name)
            }
        }
    }
    
    // MARK: - Google Sign-In
    
    func signInWithGoogle() {
        isHandlingAuthentication = true

        guard let presentingViewController = getCurrentViewController() else {
            logError("No presenting view controller found for Google Sign-In")
            isHandlingAuthentication = false
            delegate?.authenticationDidFail(error: AuthError.noPresentingController)
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) {
            [weak self] result, error in
            if let error = error {
                logError("Google Sign-In failed: \(error.localizedDescription)")
                self?.isHandlingAuthentication = false
                self?.delegate?.authenticationDidFail(error: error)
                return
            }

            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString
            else {
                logError("Failed to obtain Google tokens")
                self?.isHandlingAuthentication = false
                self?.delegate?.authenticationDidFail(error: AuthError.googleTokenFailure)
                return
            }

            // Extract Google profile name
            let googleDisplayName = user.profile?.name

            // Store Google profile image URL for later download
            let profileImageURL = user.profile?.imageURL(withDimension: 200)

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )

            Auth.auth().signIn(with: credential) { [weak self] authResult, authError in
                self?.handleAuthResult(
                    result: authResult, error: authError, method: "Google Sign-In",
                    googleProfileImageURL: profileImageURL, extractedDisplayName: googleDisplayName)
            }
        }
    }
    
    // MARK: - Apple Sign-In
    
    func signInWithApple() {
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
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()

            // Clear UID-based user settings session
            UIDUserDefaultsManager.shared.signOut()
        } catch {
            logError("Error signing out: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private methods
    
    private func handleAuthResult(
        result: AuthDataResult?, error: Error?, method: String, googleProfileImageURL: URL? = nil, extractedDisplayName: String? = nil
    ) {
        defer { isHandlingAuthentication = false }
        if let error = error {
            logError("\(method) authentication failed: \(error.localizedDescription)")
            delegate?.authenticationDidFail(error: error)
            return
        }
        guard let firebaseUser = result?.user else {
            logError("No user data received from \(method)")
            delegate?.authenticationDidFail(error: AuthError.noUser)
            return
        }
        handleSignInWithBiometricValidation(
            firebaseUser: firebaseUser,
            method: method,
            googleProfileImageURL: googleProfileImageURL,
            extractedDisplayName: extractedDisplayName
        )
    }
    
    private func handleSignInWithBiometricValidation(
        firebaseUser: FirebaseAuth.User,
        method: String,
        googleProfileImageURL: URL? = nil,
        extractedDisplayName: String? = nil
    ) {
        handleAuthenticatedUser(firebaseUser, googleProfileImageURL: googleProfileImageURL, extractedDisplayName: extractedDisplayName)
    }
    
    private func handleAuthenticatedUser(
        _ firebaseUser: FirebaseAuth.User, googleProfileImageURL: URL? = nil, extractedDisplayName: String? = nil
    ) {
        // Smart name resolution: prioritize best available name
        var bestName = "User" // Default fallback

        // Step 1: Check if we have existing UID-based settings with a good name
        if let existingSettings = UIDUserDefaultsManager.shared.getUserSettings(for: firebaseUser.uid),
           !existingSettings.name.isEmpty && existingSettings.name != "User" {
            bestName = existingSettings.name
        }
        // Step 2: Check if we have global UserDefaults with a good name
        else if let existingUser = UserDefaultsManager.getUser(),
                existingUser.firebaseUID == firebaseUser.uid,
                !existingUser.name.isEmpty && existingUser.name != "User" {
            bestName = existingUser.name
        }
        // Step 3: Use extracted name from current login (Apple/Google) if it's better
        else if let extractedName = extractedDisplayName,
                !extractedName.isEmpty && extractedName != "User" {
            bestName = extractedName
        }
        // Step 4: Use Firebase display name if it's better
        else if let firebaseName = firebaseUser.displayName,
                !firebaseName.isEmpty && firebaseName != "User" {
            bestName = firebaseName
        }
        
        let user = User(
            firebaseUID: firebaseUser.uid,
            name: bestName,
            email: firebaseUser.email ?? "",
            isUserSaved: true,
            hasFaceIdEnabled: false
        )
        
        // Download and save Google profile image if available
        if let imageURL = googleProfileImageURL {
            downloadAndSaveGoogleProfileImage(imageURL, for: firebaseUser.uid)
        }
        
        delegate?.authenticationDidComplete(user: user)
    }
    
    // MARK: - Google Profile Image Download
    
    private func downloadAndSaveGoogleProfileImage(_ imageURL: URL, for userUID: String) {
        if ProfileImageManager.shared.loadProfileImage() != nil {
            return
        }

        URLSession.shared.dataTask(with: imageURL) { data, _, error in
            if let error = error {
                logError("Failed to download Google profile image: \(error.localizedDescription)")
                return
            }

            guard let data = data, let image = UIImage(data: data) else {
                logError("Failed to create UIImage from downloaded data")
                return
            }

            ProfileImageManager.shared.saveProfileImage(image)
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
                logError("Invalid state: A login callback was received, but no login request was sent.")
                isHandlingAuthentication = false
                delegate?.authenticationDidFail(error: AuthError.invalidState)
                return
            }

            guard let appleIDToken = appleIDCredential.identityToken else {
                logError("Unable to fetch Apple identity token")
                isHandlingAuthentication = false
                delegate?.authenticationDidFail(error: AuthError.appleTokenFailure)
                return
            }

            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                logError("Unable to serialize Apple token string from data")
                isHandlingAuthentication = false
                delegate?.authenticationDidFail(error: AuthError.appleTokenFailure)
                return
            }

            // Extract Apple user name
            var appleDisplayName: String?
            if let fullName = appleIDCredential.fullName {
                let firstName = fullName.givenName ?? ""
                let lastName = fullName.familyName ?? ""
                if !firstName.isEmpty || !lastName.isEmpty {
                    appleDisplayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                }
            }

            // Initialize the Firebase credential
            let credential = OAuthProvider.credential(
                providerID: AuthProviderID.apple,
                idToken: idTokenString,
                rawNonce: nonce)
            // Sign in with Firebase
            Auth.auth().signIn(with: credential) { [weak self] authResult, error in
                self?.handleAuthResult(result: authResult, error: error, method: "Apple Sign-In", extractedDisplayName: appleDisplayName)
            }
        }
    }
    
    func authorizationController(
        controller: ASAuthorizationController, didCompleteWithError error: any Error
    ) {
        logError("Apple Sign-In failed: \(error.localizedDescription)")
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
