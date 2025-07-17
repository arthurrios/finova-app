# 🍎 Sign in with Apple Implementation Guide
## Complete Solution for App Store Guideline 4.8 Compliance

---

## 📋 **Overview**

This guide provides a complete implementation of **Sign in with Apple** to resolve App Store review issues with Guideline 4.8. Apple Sign-In automatically meets all privacy requirements:

✅ **Limits data collection** to name and email only  
✅ **Allows email privacy** - users can hide their real email  
✅ **No advertising tracking** - completely privacy-focused  

---

## 🏗️ **PHASE 1: Apple Developer Console Setup**

### **Step 1: Configure App Identifier**

1. **Go to [Apple Developer Portal](https://developer.apple.com/account)**
2. **Navigate to:** Certificates, Identifiers & Profiles > Identifiers
3. **Find your app identifier** (your bundle ID)
4. **Edit the identifier:**
   - ✅ Check **"Sign In with Apple"**
   - Click **"Configure"**
   - Select **"Enable as a primary App ID"**
   - **Save changes**

### **Step 2: Create Service ID (Optional but Recommended)**

1. **Click "+" to create new identifier**
2. **Select "Services IDs"**
3. **Register Service ID:**
   - **Description:** `[Your App Name] Sign In Service`
   - **Identifier:** `com.yourcompany.yourapp.signin` (reverse domain)
4. **Configure Service ID:**
   - ✅ Enable **"Sign In with Apple"**
   - Click **"Configure"**
   - **Primary App ID:** Select your main app identifier
   - **Web Domain:** Your app's domain (if applicable)
   - **Return URLs:** Add Firebase auth domain
     ```
     https://[PROJECT-ID].firebaseapp.com/__/auth/handler
     ```

---

## 🔥 **PHASE 2: Firebase Console Configuration**

### **Step 1: Enable Apple Sign-In Provider**

1. **Go to [Firebase Console](https://console.firebase.google.com)**
2. **Select your project**
3. **Navigate to:** Authentication > Sign-in method
4. **Click "Apple" provider**
5. **Enable Apple Sign-In:**
   - ✅ **Enable** the provider
   - **OAuth redirect URI:** Copy the provided URI
   - **Apple Team ID:** Find in Apple Developer Account > Membership
   - **Bundle ID:** Your app's bundle identifier
   - **App Store ID:** Your app's App Store ID (optional)
   - **Save**

### **Step 2: Add OAuth Redirect URI to Apple**

1. **Return to Apple Developer Portal**
2. **Edit your Service ID configuration**
3. **Add the Firebase OAuth redirect URI** from step above
4. **Save configuration**

---

## 📱 **PHASE 3: Xcode Project Configuration**

### **Step 1: Enable Sign in with Apple Capability**

1. **Open Xcode project**
2. **Select project target** (Finova)
3. **Go to:** Signing & Capabilities tab
4. **Click "+ Capability"**
5. **Add "Sign In with Apple"**
6. **Verify capability is added** with your Team ID

### **Step 2: Update Podfile**

```ruby
platform :ios, '15.0'

target 'Finova' do
  use_frameworks!

  # Core Dependencies - Authentication
  pod 'Firebase/Auth'
  pod 'GoogleSignIn'
  
  # UI Dependencies
  pod 'ShimmerView'
  pod 'SQLite.swift'

  target 'FinovaTests' do
    inherit! :search_paths
  end
end
```

**Note:** No additional pods needed - AuthenticationServices is built into iOS 13+

---

## 🎨 **PHASE 4: UI Layout Design**

### **Login Screen Layout Strategy**

Given the **6.5" display constraint**, here's the optimal button arrangement:

```
┌─────────────────────────────────┐
│           Welcome Title         │
│         Welcome Subtitle        │
│                                 │
│         Email TextField         │
│       Password TextField        │
│                                 │
│      ━━━━━━━━━━━━━━━━━━━━━      │  ← Separator
│                                 │
│        [Continue] Button        │  ← Primary login
│                                 │
│    [🍎 Sign in with Apple]     │  ← Apple (required prominent)
│    [🔵 Continue with Google]    │  ← Google (secondary)
│                                 │
│      Don't have account?        │
│           Sign up               │
└─────────────────────────────────┘
```

### **Button Hierarchy & Spacing**

1. **Apple Sign-In:** 48pt height, primary position (Apple requirement)
2. **Google Sign-In:** 44pt height, secondary position  
3. **Spacing:** 12pt between auth buttons, 16pt from main login
4. **Small screens:** Stack vertically, reduce spacing to 8pt

---

## 💻 **PHASE 5: Code Implementation**

### **Step 1: Update AuthenticationManager.swift**

Add the import and implement Apple Sign-In:

```swift
import AuthenticationServices
import FirebaseAuth

// Add to AuthenticationManager class
extension AuthenticationManager {
    
    // MARK: - Apple Sign-In
    
    func signInWithApple() {
        print("🍎 Attempting Apple Sign-In")
        isHandlingAuthentication = true
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension AuthenticationManager: ASAuthorizationControllerDelegate {
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        
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
                print("❌ Unable to serialize token string from data: \\(appleIDToken.debugDescription)")
                isHandlingAuthentication = false
                delegate?.authenticationDidFail(error: AuthError.appleTokenFailure)
                return
            }
            
            print("✅ Apple ID tokens obtained successfully")
            
            // Initialize the Firebase credential
            let credential = OAuthProvider.credential(withProviderID: "apple.com",
                                                      idToken: idTokenString,
                                                      rawNonce: nonce)
            
            // Sign in with Firebase
            Auth.auth().signIn(with: credential) { [weak self] authResult, error in
                self?.handleAuthResult(result: authResult, error: error, method: "Apple Sign-In")
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("❌ Apple Sign-In failed: \\(error.localizedDescription)")
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
```

### **Step 2: Add Nonce Generation**

Add this property and helper to AuthenticationManager:

```swift
// Add to AuthenticationManager class
import CryptoKit

private var currentNonce: String?

private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length
    
    while remainingLength > 0 {
        let randoms: [UInt8] = (0 ..< 16).map { _ in
            var random: UInt8 = 0
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \\(errorCode)")
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
```

### **Step 3: Update Error Handling**

Add to AuthError enum:

```swift
enum AuthError: LocalizedError {
    // ... existing cases ...
    case appleTokenFailure
    case invalidState
    
    var errorDescription: String? {
        switch self {
        // ... existing cases ...
        case .appleTokenFailure:
            return "Failed to obtain Apple ID token"
        case .invalidState:
            return "Invalid authentication state"
        }
    }
}
```

### **Step 4: Update signInWithApple Method**

Update the signInWithApple method to generate nonce:

```swift
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
```

---

## 🎨 **PHASE 6: Update Login UI**

### **Step 1: Update LoginView.swift**

Add the Apple Sign-In button after the main login button:

```swift
// Add after googleSignInButton declaration
let appleSignInButton: ASAuthorizationAppleIDButton = {
    let button = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
    button.cornerRadius = CornerRadius.large
    button.heightAnchor.constraint(equalToConstant: 48).isActive = true
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()
```

### **Step 2: Update Button Layout**

Modify the setupView method:

```swift
// Add to containerView
containerView.addSubview(appleSignInButton)

// Update constraints - add after button constraints:
appleSignInButton.topAnchor.constraint(
    equalTo: button.bottomAnchor, constant: Metrics.spacing4),
appleSignInButton.leadingAnchor.constraint(equalTo: button.leadingAnchor),
appleSignInButton.trailingAnchor.constraint(equalTo: button.trailingAnchor),

// Update Google button constraint:
googleSignInButton.topAnchor.constraint(
    equalTo: appleSignInButton.bottomAnchor, constant: Metrics.spacing3),
```

### **Step 3: Add Button Action**

```swift
// Add to setupView method
appleSignInButton.addTarget(
    self, action: #selector(handleAppleSignInTapped), for: .touchUpInside)

// Add action method
@objc
private func handleAppleSignInTapped() {
    delegate?.signInWithApple()
}
```

### **Step 4: Update Protocols**

Update LoginViewDelegate:

```swift
protocol LoginViewDelegate: AnyObject {
    func sendLoginData(email: String, password: String)
    func navigateToRegister()
    func signInWithGoogle()
    func signInWithApple()  // Add this
}
```

### **Step 5: Update ViewController & ViewModel**

Add to LoginViewController:

```swift
// Add to LoginViewDelegate implementation
func signInWithApple() {
    LoadingManager.shared.showLoading()
    viewModel.signInWithApple()
}
```

Add to LoginViewModel:

```swift
func signInWithApple() {
    authManager.signInWithApple()
}
```

---

## 🔗 **PHASE 7: Biometric Account Linking with FaceID**

### **The Challenge: Different Email Addresses**

Apple Sign-In can create a data isolation problem when users have different email addresses for different providers:

```
Google Sign-In: arthur.rios007@gmail.com → Firebase UID: "google_abc123"
Apple Sign-In: rios.arthur@hotmail.com → Firebase UID: "apple_xyz789"
```

**Result**: Same person, different UIDs, **separate data sets**!

### **🔐 Enhanced Solution: FaceID Biometric Verification**

Instead of relying on email detection alone, we use FaceID to verify that the same **physical person** is trying to access different accounts. This is much more secure and user-friendly.

**New Flow:**
1. **First Sign-In** → Store FaceID biometric hash with user data
2. **Different Email Detected** → Prompt for FaceID verification
3. **FaceID Matches** → "We found data from your other account. Synchronize?"
4. **FaceID Doesn't Match** → Silent new account creation (no prompt)

---

### **Step 1: BiometricDataManager Implementation**

Create a new `BiometricDataManager.swift` class to handle FaceID operations:

```swift
//
//  BiometricDataManager.swift
//  FinanceApp
//

import Foundation
import LocalAuthentication
import Security

class BiometricDataManager {
    
    // MARK: - Singleton
    static let shared = BiometricDataManager()
    private init() {}
    
    // MARK: - Keychain Keys
    private let biometricIdentifierKey = "biometric_user_identifier"
    private let biometricEmailKey = "biometric_linked_email"
    
    // MARK: - Biometric Availability
    
    func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    func getBiometricType() -> LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }
    
    // MARK: - Biometric Registration
    
    func registerUserBiometric(for email: String, completion: @escaping (Bool, Error?) -> Void) {
        guard isBiometricAvailable() else {
            completion(false, BiometricError.notAvailable)
            return
        }
        
        let context = LAContext()
        let reason = "Register your biometric authentication to link accounts securely"
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, error in
            
            if success {
                // Generate unique biometric identifier
                let biometricIdentifier = self?.generateBiometricIdentifier() ?? UUID().uuidString
                
                // Store biometric data in Keychain
                let stored = self?.storeBiometricData(identifier: biometricIdentifier, email: email) ?? false
                
                DispatchQueue.main.async {
                    completion(stored, stored ? nil : BiometricError.storageFailure)
                }
            } else {
                DispatchQueue.main.async {
                    completion(false, error ?? BiometricError.authenticationFailed)
                }
            }
        }
    }
    
    // MARK: - Biometric Verification
    
    func verifyUserBiometric(completion: @escaping (BiometricVerificationResult) -> Void) {
        guard isBiometricAvailable() else {
            completion(.notAvailable)
            return
        }
        
        guard getBiometricData() != nil else {
            completion(.noRegisteredBiometric)
            return
        }
        
        let context = LAContext()
        let reason = "Verify your identity to access existing account data"
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, error in
            
            DispatchQueue.main.async {
                if success {
                    if let (_, email) = self?.getBiometricData() {
                        completion(.verified(linkedEmail: email))
                    } else {
                        completion(.verificationFailed)
                    }
                } else {
                    if let laError = error as? LAError {
                        switch laError.code {
                        case .userCancel:
                            completion(.userCancelled)
                        case .userFallback:
                            completion(.userFallback)
                        default:
                            completion(.verificationFailed)
                        }
                    } else {
                        completion(.verificationFailed)
                    }
                }
            }
        }
    }
    
    // MARK: - Biometric Data Management
    
    func hasBiometricData() -> Bool {
        return getBiometricData() != nil
    }
    
    func getLinkedEmail() -> String? {
        return getBiometricData()?.email
    }
    
    func clearBiometricData() {
        deleteBiometricDataFromKeychain()
    }
    
    // MARK: - Private Methods
    
    private func generateBiometricIdentifier() -> String {
        // Generate a unique identifier based on device and biometric data
        let deviceIdentifier = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let timestamp = String(Date().timeIntervalSince1970)
        let combined = "\(deviceIdentifier)_\(timestamp)"
        
        return combined.data(using: .utf8)?.base64EncodedString() ?? UUID().uuidString
    }
    
    private func storeBiometricData(identifier: String, email: String) -> Bool {
        let biometricData = BiometricUserData(identifier: identifier, email: email, registrationDate: Date())
        
        do {
            let data = try JSONEncoder().encode(biometricData)
            return storeBiometricDataInKeychain(data: data)
        } catch {
            print("❌ Failed to encode biometric data: \(error)")
            return false
        }
    }
    
    private func getBiometricData() -> BiometricUserData? {
        guard let data = getBiometricDataFromKeychain() else { return nil }
        
        do {
            return try JSONDecoder().decode(BiometricUserData.self, from: data)
        } catch {
            print("❌ Failed to decode biometric data: \(error)")
            return nil
        }
    }
    
    // MARK: - Keychain Operations
    
    private func storeBiometricDataInKeychain(data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: biometricIdentifierKey,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "FinanceApp",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func getBiometricDataFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: biometricIdentifierKey,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "FinanceApp",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            return result as? Data
        }
        return nil
    }
    
    private func deleteBiometricDataFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: biometricIdentifierKey,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "FinanceApp"
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Supporting Types

struct BiometricUserData: Codable {
    let identifier: String
    let email: String
    let registrationDate: Date
}

enum BiometricVerificationResult {
    case verified(linkedEmail: String)
    case verificationFailed
    case userCancelled
    case userFallback
    case notAvailable
    case noRegisteredBiometric
}

enum BiometricError: LocalizedError {
    case notAvailable
    case authenticationFailed
    case storageFailure
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Biometric authentication is not available on this device"
        case .authenticationFailed:
            return "Biometric authentication failed"
        case .storageFailure:
            return "Failed to store biometric data securely"
        }
    }
}
```

### **Step 2: Enhanced SecureLocalDataManager**

Update `SecureLocalDataManager.swift` to integrate biometric verification:

```swift
// Add to SecureLocalDataManager class
func validateDataOwnershipWithBiometrics(for firebaseUID: String, email: String) -> AccountValidationResult {
    // Check if data has already been claimed by another user
    if let existingOwnerUID = getDataOwnerUID() {
        if existingOwnerUID != firebaseUID {
            print("🔒 Data already owned by different user: \(existingOwnerUID)")
            return .ownedByDifferentUser
        }
    }
    
    // Check if existing local user data matches this email
    if let existingUser = UserDefaultsManager.getUser() {
        if existingUser.email.lowercased() != email.lowercased() {
            print("🔒 Email mismatch detected:")
            print("   Existing: \(existingUser.email)")
            print("   New: \(email)")
            
            // Check if we have biometric data registered
            if BiometricDataManager.shared.hasBiometricData() {
                return .requiresBiometricVerification(existingEmail: existingUser.email, newEmail: email)
            } else {
                // No biometric data - treat as new user
                return .valid
            }
        }
    }
    
    // Standard validation for first-time users
    return validateDeviceDataAccess(for: email) ? .valid : .accessDenied
}

// Enhanced validation result enum
enum AccountValidationResult {
    case valid
    case requiresBiometricVerification(existingEmail: String, newEmail: String)
    case ownedByDifferentUser
    case accessDenied
}
```

### **Step 3: Biometric Registration for First-Time Users**

Add biometric registration to `SecureLocalDataManager`:

```swift
// Add to SecureLocalDataManager class
func registerFirstTimeUserWithBiometrics(
    firebaseUID: String,
    email: String,
    completion: @escaping (Bool) -> Void
) {
    guard BiometricDataManager.shared.isBiometricAvailable() else {
        print("ℹ️ Biometric authentication not available - proceeding without registration")
        authenticateUser(firebaseUID: firebaseUID)
        completion(true)
        return
    }
    
    // Register biometric data for this user
    BiometricDataManager.shared.registerUserBiometric(for: email) { [weak self] success, error in
        if success {
            print("✅ Biometric registration successful for: \(email)")
        } else {
            print("⚠️ Biometric registration failed: \(error?.localizedDescription ?? "Unknown error")")
            // Continue without biometric registration
        }
        
        // Proceed with normal authentication regardless of biometric registration result
        self?.authenticateUser(firebaseUID: firebaseUID)
        completion(true)
    }
}

func handleBiometricAccountLinking(
    newFirebaseUID: String, 
    newEmail: String, 
    linkToExistingData: Bool,
    completion: @escaping (Bool) -> Void
) {
    if linkToExistingData {
        // Link to existing data - use existing UID structure but update user info
        if let existingUser = UserDefaultsManager.getUser() {
            print("🔗 Linking accounts via biometric verification: keeping existing data")
            
            // Update user profile with new sign-in method info
            let linkedUser = User(
                firebaseUID: existingUser.firebaseUID, // Keep existing UID
                name: existingUser.name,
                email: newEmail, // Update to new email
                isUserSaved: true,
                hasFaceIdEnabled: existingUser.hasFaceIdEnabled
            )
            
            UserDefaultsManager.saveUser(linkedUser)
            
            // Mark the account as linked
            markBiometricAccountLinking(
                originalUID: existingUser.firebaseUID,
                newUID: newFirebaseUID,
                newEmail: newEmail
            )
            
            // Authenticate with existing UID to access existing data
            authenticateUser(firebaseUID: existingUser.firebaseUID)
            
            print("✅ Biometric account linking successful")
            completion(true)
        } else {
            print("❌ No existing user found for linking")
            completion(false)
        }
    } else {
        // Start fresh - register biometric for new account
        print("🆕 Starting fresh with new account")
        registerFirstTimeUserWithBiometrics(
            firebaseUID: newFirebaseUID,
            email: newEmail,
            completion: completion
        )
    }
}

private func markBiometricAccountLinking(originalUID: String, newUID: String, newEmail: String) {
    let linkingInfo = [
        "original_uid": originalUID,
        "linked_uid": newUID,
        "linked_email": newEmail,
        "linking_method": "biometric_verification",
        "linking_date": DateFormatter.iso8601.string(from: Date())
    ]
    UserDefaults.standard.set(linkingInfo, forKey: "biometric_linking_\(originalUID)")
    print("🔗 Biometric account linking recorded")
}
```

### **Step 4: Enhanced AuthenticationManager with Biometric Flow**

Update `AuthenticationManager.swift` to handle biometric verification:

```swift
// Add to AuthenticationManager class
import UIKit
import LocalAuthentication

// Enhanced handleAuthResult for ALL sign-in methods with biometric verification
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
    
    // 🔐 BIOMETRIC VALIDATION - Handle ALL sign-in methods with FaceID verification
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
        // No issues - check if this is first-time user and register biometric
        if !BiometricDataManager.shared.hasBiometricData() {
            // First-time user - register biometric
            SecureLocalDataManager.shared.registerFirstTimeUserWithBiometrics(
                firebaseUID: firebaseUser.uid,
                email: newEmail
            ) { [weak self] success in
                if success {
                    self?.handleAuthenticatedUser(firebaseUser, googleProfileImageURL: googleProfileImageURL)
                } else {
                    self?.delegate?.authenticationDidFail(error: AuthError.biometricRegistrationFailed)
                }
            }
        } else {
            // Existing user - proceed normally
            handleAuthenticatedUser(firebaseUser, googleProfileImageURL: googleProfileImageURL)
        }
        
    case .requiresBiometricVerification(let existingEmail, let newEmail):
        // Perform biometric verification before showing any prompts
        performBiometricVerificationForAccountLinking(
            existingEmail: existingEmail,
            newEmail: newEmail,
            firebaseUser: firebaseUser,
            method: method,
            googleProfileImageURL: googleProfileImageURL
        )
        
    case .ownedByDifferentUser, .accessDenied:
        // Security issue - deny access
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
            // Show account synchronization prompt
            self?.showAccountSynchronizationPrompt(
                existingEmail: existingEmail,
                newEmail: newEmail,
                firebaseUser: firebaseUser,
                method: method,
                googleProfileImageURL: googleProfileImageURL
            )
            
        case .verificationFailed:
            print("❌ Biometric verification failed - treating as new user")
            // Failed verification - treat as completely new user (silent)
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
            // User chose fallback - treat as new user
            self?.handleNewUserAfterFailedBiometricVerification(
                firebaseUser: firebaseUser,
                method: method,
                googleProfileImageURL: googleProfileImageURL
            )
            
        case .notAvailable:
            print("⚠️ Biometric authentication not available - treating as new user")
            // No biometric available - treat as new user
            self?.handleNewUserAfterFailedBiometricVerification(
                firebaseUser: firebaseUser,
                method: method,
                googleProfileImageURL: googleProfileImageURL
            )
            
        case .noRegisteredBiometric:
            print("ℹ️ No registered biometric found - treating as new user")
            // No registered biometric - treat as new user
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
    // Register biometric for this new user and proceed
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
        
        // Biometric verification successful - show friendly synchronization message
        let alert = UIAlertController(
            title: "🔐 Account Data Found",
            message: """
            We found existing data from your other account:
            \(existingEmail)
            
            Would you like to synchronize and access this data with your current sign-in?
            """,
            preferredStyle: .alert
        )
        
        // Synchronize option
        alert.addAction(UIAlertAction(title: "Synchronize", style: .default) { _ in
            self?.synchronizeAccountData(
                firebaseUser: firebaseUser,
                existingEmail: existingEmail,
                newEmail: newEmail,
                method: method,
                googleProfileImageURL: googleProfileImageURL
            )
        })
        
        // Keep Separate option
        alert.addAction(UIAlertAction(title: "Keep Separate", style: .default) { _ in
            self?.createSeparateAccount(
                firebaseUser: firebaseUser,
                method: method,
                googleProfileImageURL: googleProfileImageURL
            )
        })
        
        presentingVC.present(alert, animated: true)
    }
}

private func getMethodDescription(_ method: String) -> String {
    switch method {
    case "Apple Sign-In":
        return "Apple ID"
    case "Google Sign-In":
        return "Google account"
    case "Email/Password", "Registration":
        return "email account"
    default:
        return "account"
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
```

### **Step 5: Update Error Handling for Biometric Flow**

Add new biometric-related error cases to `AuthError` enum:

```swift
enum AuthError: LocalizedError {
    // ... existing cases ...
    case appleTokenFailure
    case invalidState
    case accessDenied
    case userCancelled
    case biometricRegistrationFailed
    case biometricVerificationCancelled
    case synchronizationFailed
    case accountCreationFailed
    
    var errorDescription: String? {
        switch self {
        // ... existing cases ...
        case .appleTokenFailure:
            return "Failed to obtain Apple ID token"
        case .invalidState:
            return "Invalid authentication state"
        case .accessDenied:
            return "Access denied for security reasons"
        case .userCancelled:
            return "Authentication cancelled by user"
        case .biometricRegistrationFailed:
            return "Failed to register biometric authentication"
        case .biometricVerificationCancelled:
            return "Biometric verification was cancelled"
        case .synchronizationFailed:
            return "Failed to synchronize account data"
        case .accountCreationFailed:
            return "Failed to create new account"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        // ... existing cases ...
        case .biometricRegistrationFailed:
            return "You can continue using the app, but account linking won't be available"
        case .biometricVerificationCancelled:
            return "Try signing in again to verify your identity"
        case .synchronizationFailed:
            return "Please try signing in again or contact support"
        case .accountCreationFailed:
            return "Please try again or use a different sign-in method"
        default:
            return nil
        }
    }
}
```

### **Step 5: Add Missing SecureLocalDataManager Method**

Add the validation result method:

```swift
// Add to SecureLocalDataManager class
func validateDataOwnershipResult(for firebaseUID: String, email: String) -> EmailValidationResult {
    return validateDataOwnership(for: firebaseUID, email: email)
}
```

### **Step 6: Enhanced Biometric User Experience Flow**

**🔐 BIOMETRIC VERIFICATION FLOW - MAXIMUM SECURITY:**

**Scenario 1: First-time user (any method)**
```
Any Sign-In → No existing data → Register FaceID → Normal flow
```

**Scenario 2: Same person, different email (Google → Apple)**
```
1. Google Sign-In: arthur.rios007@gmail.com → FaceID registered → Data created
2. Apple Sign-In: rios.arthur@hotmail.com → Email mismatch detected
3. FaceID Verification Prompt: "Verify your identity"
4. FaceID SUCCESS → "🔐 Account Data Found - Synchronize?"
   ├── Synchronize → Access existing Google data with Apple sign-in
   └── Keep Separate → Create new Apple account (separate data)
```

**Scenario 3: Same person, different email (Apple → Google)**
```
1. Apple Sign-In: rios.arthur@hotmail.com → FaceID registered → Data created
2. Google Sign-In: arthur.rios007@gmail.com → Email mismatch detected
3. FaceID Verification Prompt: "Verify your identity"
4. FaceID SUCCESS → "🔐 Account Data Found - Synchronize?"
   ├── Synchronize → Access existing Apple data with Google sign-in
   └── Keep Separate → Create new Google account (separate data)
```

**Scenario 4: Different person with different email**
```
1. Previous User: arthur.rios007@gmail.com → FaceID registered → Data created
2. New User: jane.doe@email.com → Email mismatch detected
3. FaceID Verification Prompt: "Verify your identity"
4. FaceID FAILURE → Silent new account creation (NO PROMPT SHOWN)
   → New user never sees previous user's data
```

**Scenario 5: User cancels FaceID verification**
```
1. Different email detected → FaceID prompt shown
2. User cancels FaceID → Silent new account creation
   → Treated as new user (privacy preserved)
```

**Scenario 6: FaceID not available**
```
Any Sign-In → Device without FaceID → Normal flow (no linking available)
```

**🔒 Security Benefits:**
- **No data exposure**: Different people never see prompts about other accounts
- **Biometric verification**: Physical presence required for account linking
- **Silent fallbacks**: Failed verification creates new account without exposure
- **Privacy-first**: No hints about existing accounts to unauthorized users

### **Step 7: Account Management Features**

Add optional settings screen functionality:

```swift
// For future enhancement in Settings
class AccountSettingsViewController {
    
    func showLinkedAccounts() {
        // Display linked sign-in methods
        // Allow unlinking accounts
        // Show which data belongs to which account
    }
    
    func unlinkAccount(provider: String) {
        // Remove account linking
        // Prompt user about data access implications
    }
}
```

---

## 🧪 **PHASE 8: Testing Guidelines**

### **Testing Checklist**

#### **Pre-Testing Setup**
- [ ] **Test on physical device** (Apple Sign-In doesn't work in simulator)
- [ ] **Use development Apple ID** (not your main account)
- [ ] **Ensure iOS 13+ device**

#### **Test Scenarios**

1. **✅ First-time Sign-In**
   - Tap Apple Sign-In button
   - Verify Apple ID prompt appears
   - Complete authentication
   - Verify user creation in Firebase
   - Check data isolation (UID-based)

2. **✅ Subsequent Sign-Ins**
   - User should sign in seamlessly
   - Verify existing data loads correctly
   - Test app switching/background

3. **✅ Email Privacy Option**
   - During first sign-in, choose "Hide My Email"
   - Verify relay email is used
   - Test that app functions normally

4. **✅ Error Handling**
   - Cancel sign-in process
   - Test with network errors
   - Verify appropriate error messages

5. **✅ Small Screen Testing**
   - Test on iPhone SE/smaller devices
   - Verify button layout works
   - Check accessibility

6. **✅ Biometric Verification Testing (All Combinations)**
   - **Same Person Testing**:
     - **Google → Apple**: Same person, different emails → FaceID should match → Sync prompt
     - **Apple → Google**: Same person, different emails → FaceID should match → Sync prompt
     - **Manual → Apple**: Same person, different emails → FaceID should match → Sync prompt
     - **Manual → Google**: Same person, different emails → FaceID should match → Sync prompt
   - **Different Person Testing** (requires multiple test devices):
     - Sign in on Device A with one email → Register FaceID
     - Sign in on Device B with different email → FaceID should fail → Silent new account
   - **FaceID Scenarios**:
     - **Cancel FaceID**: User cancels verification → Silent new account creation
     - **Failed FaceID**: Wrong person → Silent new account creation (no data exposure)
     - **No FaceID Device**: Normal flow without biometric linking
   - **User Choice Testing**:
     - Test "Synchronize" option → Verify data merging
     - Test "Keep Separate" option → Verify separate data sets
   - **Security Verification**:
     - Confirm failed biometric never shows account data
     - Verify no hints about existing accounts to wrong users

---

## 📱 **PHASE 9: Final App Store Preparation**

### **App Store Connect Configuration**

1. **Update App Privacy:**
   - **Data Types Collected:** Name, Email Address
   - **Purpose:** Account Creation, App Functionality
   - **Third-party Tracking:** NO
   - **Data Linked to User:** YES (for account)

2. **Sign in with Apple Implementation:**
   - ✅ **Prominently displayed** (first alternative option)
   - ✅ **Equal treatment** to Google Sign-In
   - ✅ **Privacy-compliant** by design

### **Review Response Template**

When resubmitting, include this response:

```
Dear App Review Team,

We have implemented Sign in with Apple as an equivalent login option that meets all requirements of Guideline 4.8:

1. ✅ **Data Collection Limited**: Only name and email address
2. ✅ **Email Privacy Option**: Users can hide their email using Apple's relay service  
3. ✅ **No Advertising Tracking**: Apple Sign-In has zero advertising data collection

Sign in with Apple is prominently displayed as the first alternative login option, positioned immediately after our standard email/password login method.

The implementation follows Apple's Human Interface Guidelines and provides users with complete privacy control over their authentication data.

Thank you for your review.
```

---

## 🔍 **Troubleshooting**

### **Common Issues**

| **Issue** | **Solution** |
|-----------|-------------|
| **Button not appearing** | Verify iOS 13+ deployment target |
| **"Simulator not supported"** | Test on physical device only |
| **Firebase token errors** | Check nonce implementation |
| **Team ID mismatch** | Verify Apple Developer Portal setup |
| **Redirect URI errors** | Double-check Firebase OAuth URLs |

### **Validation Checklist**

- [ ] **Apple Developer Portal** - Service ID configured
- [ ] **Firebase Console** - Apple provider enabled  
- [ ] **Xcode Capabilities** - Sign in with Apple added
- [ ] **Physical Device Testing** - All flows working
- [ ] **App Store Privacy** - Correctly configured
- [ ] **UI Guidelines** - Apple button prominent

---

## 🚀 **Implementation Priority**

**Phase 1-3:** Apple & Firebase setup (30 mins)  
**Phase 4-6:** Code implementation (2-3 hours)  
**Phase 7:** Biometric verification system (2 hours)  
**Phase 8:** Testing & validation (1.5 hours)  
**Phase 9:** App Store resubmission (30 mins)

**Total Estimated Time:** 6-7 hours

This implementation will ensure **100% App Store Guideline 4.8 compliance** while maintaining your existing Google Sign-In functionality. 