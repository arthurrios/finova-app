//
//  RegisterViewController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/06/25.
//

import Foundation
import LocalAuthentication
import UIKit

final class RegisterViewController: UIViewController {
    let contentView: RegisterView
    let viewModel: RegisterViewModel
    public weak var flowDelegate: RegisterFlowDelegate?
    
    init(contentView: RegisterView, viewModel: RegisterViewModel, flowDelegate: RegisterFlowDelegate)
    {
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
    
    private func bindViewModel() {
        viewModel.successResult = { [weak self] in
            self?.handleSuccessfulRegistration()
        }
        
        viewModel.errorResult = { [weak self] title, message in
            LoadingManager.shared.hideLoading()
            self?.presentErrorAlert(title: title, message: message)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        animateShow()
        startKeyboardObservers()
    }
    
    private func setup() {
        view.addSubview(contentView)
        buildHierarchy()
    }
    
    private func buildHierarchy() {
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
    }
    
    private func handleSuccessfulRegistration() {
        guard let currentUser = UserDefaultsManager.getUser() else {
            flowDelegate?.navigateToDashboard()
            return
        }
        
        // New Firebase user from registration - always offer Face ID
        askEnableFaceID(for: currentUser)
    }
    
    private func askEnableFaceID(for user: User) {
        // Use FaceIDManager instead of direct LocalAuthentication calls
        guard FaceIDManager.shared.isFaceIDAvailable else {
            // Device doesn't support biometrics
            let updatedUser = User(
                firebaseUID: user.firebaseUID,
                name: user.name,
                email: user.email,
                isUserSaved: true,
                hasFaceIdEnabled: false
            )
            UserDefaultsManager.saveUser(user: updatedUser)
            flowDelegate?.navigateToDashboard()
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
            let updatedUser = User(
                firebaseUID: user.firebaseUID,
                name: user.name,
                email: user.email,
                isUserSaved: true,
                hasFaceIdEnabled: true
            )
            UserDefaultsManager.saveUser(user: updatedUser)
            print("✅ \(biometricType) enabled for new Firebase user")
            self.flowDelegate?.navigateToDashboard()
        }
        
        let noAction = UIAlertAction(title: "skip".localized, style: .cancel) { _ in
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
    }
    
    private func presentErrorAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let retryAction = UIAlertAction(title: "error.tryAgain".localized, style: .default)
        alertController.addAction(retryAction)
        self.present(alertController, animated: true)
    }
    
    func animateShow(completion: (() -> Void)? = nil) {
        contentView.layoutIfNeeded()
        UIView.animate(
            withDuration: 0.7,
            animations: {
                self.contentView.containerView.layer.opacity = 1
            })
    }
}

extension RegisterViewController: RegisterViewDelegate {
    func sendRegisterData(name: String, email: String, password: String, confirmPassword: String) {
        LoadingManager.shared.showLoading(on: self)
        viewModel.registerUser(
            name: name, email: email, password: password, confirmPassword: confirmPassword)
    }
    
    func navigateBackToLogin() {
        flowDelegate?.navigateBackToLogin()
    }
}
