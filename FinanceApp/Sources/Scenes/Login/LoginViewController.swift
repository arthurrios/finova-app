//
//  LoginViewController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
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
        contentView.containerView.alpha = 1
        startKeyboardObservers()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopKeyboardObservers()
    }
    
    private func bindViewModel() {
        viewModel.successResult = { [weak self] (userName, userEmail) in
            self?.presentSaveLoginAlert(name: userName, email: userEmail)
        }
        
        viewModel.errorResult = { [weak self] error in
            self?.presentErrorAlert(message: error)
        }
    }
    
    private func presentErrorAlert(message: String) {
        let alertController = UIAlertController(title: "login.error.title".localized, message: message, preferredStyle: .alert)
        let retryAction = UIAlertAction(title: "login.error.tryAgain".localized, style: .default)
        alertController.addAction(retryAction)
        self.present(alertController, animated: true)
    }
  
    private func presentSaveLoginAlert(name: String, email: String) {
        let alertController = UIAlertController(title: "login.alert.title".localized, message: "login.alert.subtitle".localized + "\(name)?", preferredStyle: .alert)
        let okAction = UIAlertAction(title: "login.alert.ok".localized, style: .default) { _ in
            let user = User(name: name, email: email, isUserSaved: true)
            UserDefaultsManager.saveUser(user: user)
            self.flowDelegate?.navigateToDashboard()
        }
        
        let cancelAction = UIAlertAction(title: "login.alert.cancel".localized, style: .cancel) { _ in
            let user = User(name: name, email: email, isUserSaved: false)
            UserDefaultsManager.saveUser(user: user)
            self.flowDelegate?.navigateToDashboard()
        }
        
        alertController.addAction(okAction)
        alertController.addAction(cancelAction)
        present(alertController, animated: true)
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
        UIView.animate(withDuration: 1, animations: {
            self.contentView.containerView.alpha = 1
        }) { _ in
            completion?()
        }
    }
}

extension LoginViewController: LoginViewDelegate {
    func sendLoginData(name: String, email: String, password: String) {
        viewModel.authenticate(userName: name, userEmail: email, password: password)
    }
}
