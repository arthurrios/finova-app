//
//  LoginViewController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import LocalAuthentication
import UIKit

final class LoginViewController: UIViewController {
    let contentView: LoginView
    let viewModel: LoginViewModel
    public weak var flowDelegate: LoginFlowDelegate?
    
    init(contentView: LoginView, viewModel: LoginViewModel, flowDelegate: LoginFlowDelegate) {
        self.contentView = contentView
        self.viewModel = viewModel
        self.flowDelegate = flowDelegate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        contentView.delegate = self
        setup()
        hideKeyboardWhenTappedAround()
        bindViewModel()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        startKeyboardObservers()
    }
    
    private func bindViewModel() {
        viewModel.successResult = { [weak self] in
            self?.handleSuccessfulAuthentication()
        }
        
        viewModel.errorResult = { [weak self] title, message in
            self?.presentErrorAlert(title: title, message: message)
        }
    }
    
    private func presentErrorAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let retryAction = UIAlertAction(title: "error.tryAgain".localized, style: .default)
        alertController.addAction(retryAction)
        self.present(alertController, animated: true)
    }
    
    private func handleSuccessfulAuthentication() {
        guard let currentUser = UserDefaultsManager.getUser() else {
            // Fallback: go directly to dashboard
            flowDelegate?.navigateToDashboard()
            return
        }
        
        // Check if this is a new Firebase user (first time login)
        if currentUser.isFirebaseUser && !currentUser.isUserSaved {
            // New Firebase user - offer Face ID setup
            askEnableFaceID(for: currentUser)
        } else if currentUser.isUserSaved {
            // Existing user - go to dashboard
            flowDelegate?.navigateToDashboard()
        } else {
            // Legacy user or other case - offer to save and enable Face ID
            presentSaveLoginAlert(for: currentUser)
        }
    }
    
    private func presentSaveLoginAlert(for user: User) {
            let alertController = UIAlertController(
                title: "login.alert.title".localized,
                message: "login.alert.subtitle".localized + "\(user.displayName)?",
                preferredStyle: .alert
            )
            
            let okAction = UIAlertAction(title: "login.alert.ok".localized, style: .default) { _ in
                self.askEnableFaceID(for: user)
            }

            let cancelAction = UIAlertAction(title: "login.alert.cancel".localized, style: .cancel) { _ in
                // Save user without Face ID
                let updatedUser = User(
                    firebaseUID: user.firebaseUID,
                    name: user.name,
                    email: user.email,
                    isUserSaved: true,
                    hasFaceIdEnabled: false
                )
                UserDefaultsManager.saveUser(user: updatedUser)
                self.flowDelegate?.navigateToDashboard()
            }

            alertController.addAction(okAction)
            alertController.addAction(cancelAction)
            present(alertController, animated: true)
        }

        private func askEnableFaceID(for user: User) {
            let context = LAContext()
            var error: NSError?

            let supportsBiometrics = context.canEvaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                error: &error
            )

            if supportsBiometrics {
                let alertController = UIAlertController(
                    title: "faceid.alert.title".localized,
                    message: "faceid.alert.subtitle".localized,
                    preferredStyle: .alert
                )

                let yesAction = UIAlertAction(title: "yes".localized, style: .default) { _ in
                    // Save user with Face ID enabled
                    let updatedUser = User(
                        firebaseUID: user.firebaseUID,
                        name: user.name,
                        email: user.email,
                        isUserSaved: true,
                        hasFaceIdEnabled: true
                    )
                    UserDefaultsManager.saveUser(user: updatedUser)
                    print("✅ Face ID enabled for Firebase user")
                    self.flowDelegate?.navigateToDashboard()
                }

                let noAction = UIAlertAction(title: "no".localized, style: .cancel) { _ in
                    // Save user without Face ID
                    let updatedUser = User(
                        firebaseUID: user.firebaseUID,
                        name: user.name,
                        email: user.email,
                        isUserSaved: true,
                        hasFaceIdEnabled: false
                    )
                    UserDefaultsManager.saveUser(user: updatedUser)
                    self.flowDelegate?.navigateToDashboard()
                }

                alertController.addAction(yesAction)
                alertController.addAction(noAction)
                present(alertController, animated: true)
            } else {
                // Device doesn't support biometrics - save user without Face ID
                let updatedUser = User(
                    firebaseUID: user.firebaseUID,
                    name: user.name,
                    email: user.email,
                    isUserSaved: true,
                    hasFaceIdEnabled: false
                )
                UserDefaultsManager.saveUser(user: updatedUser)
                flowDelegate?.navigateToDashboard()
            }
        }
    
    private func setup() {
        view.addSubview(contentView)
        buildHierarchy()
    }
    
    private func buildHierarchy() {
        setupContentViewToBounds(contentView: contentView)
    }
    
    func animateShow(completion: (() -> Void)? = nil) {
        contentView.layoutIfNeeded()
        UIView.animate(
            withDuration: 0.7,
            animations: {
                self.contentView.containerView.alpha = 1
            })
    }
}

extension LoginViewController: LoginViewDelegate {
    func signInWithGoogle() {
        viewModel.signInWithGoogle()
    }
    
    func sendLoginData(email: String, password: String) {
        viewModel.authenticate(userEmail: email, password: password)
    }
    
    func navigateToRegister() {
        flowDelegate?.navigateToRegister()
    }
}
