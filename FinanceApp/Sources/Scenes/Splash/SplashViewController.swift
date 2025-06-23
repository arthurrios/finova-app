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
            if let localUser = UserDefaultsManager.getUser(),
               localUser.isUserSaved && localUser.hasFaceIdEnabled {
                print("🔒 Face ID enabled - requesting biometric authentication")
                authenticateWithFaceID()
            } else {
                print("ℹ️ Face ID not enabled - going directly to dashboard")
                flowDelegate?.navigateToDirectlyToDashboard()
            }
        } else {
            print("ℹ️ No Firebase user found, checking local user...")
            
            // Check for legacy local users (pre-Firebase)
            if let localUser = UserDefaultsManager.getUser(), localUser.isUserSaved {
                if localUser.hasFaceIdEnabled {
                    authenticateWithFaceID()
                } else {
                    // Legacy user without Firebase - might need re-authentication
                    showReAuthenticationPrompt()
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
        let context = LAContext()
        var authError: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) {
            let reason = "faceid.reason".localized
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("✅ Face ID authentication successful")
                        self.flowDelegate?.navigateToDirectlyToDashboard()
                    } else {
                        print("❌ Face ID authentication failed: \(error?.localizedDescription ?? "Unknown error")")
                        self.handleFaceIDFailure()
                    }
                }
            }
        } else {
            print("❌ Face ID not available: \(authError?.localizedDescription ?? "Unknown error")")
            handleFaceIDFailure()
        }
    }
    
    private func handleFaceIDFailure() {
        // If user has Firebase account, show login
        // If legacy user, also show login for re-authentication
        gradientLayer.removeFromSuperlayer()
        navigateToLogin()
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
