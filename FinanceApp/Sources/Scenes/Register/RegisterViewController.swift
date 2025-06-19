//
//  RegisterViewController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/06/25.
//

import Foundation
import UIKit

final class RegisterViewController: UIViewController {
    let contentView: RegisterView
    let viewModel: RegisterViewModel
    public weak var flowDelegate: RegisterFlowDelegate?
    
    init(contentView: RegisterView, viewModel: RegisterViewModel, flowDelegate: RegisterFlowDelegate) {
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
    
    func animateShow(completion: (() -> Void)? = nil) {
        contentView.layoutIfNeeded()
        UIView.animate(withDuration: 0.7, animations: {
            self.contentView.containerView.layer.opacity = 1
        })
    }
}

extension RegisterViewController: RegisterViewDelegate {
    func sendRegisterData(name: String, email: String, password: String, confirmPassword: String) {
        //
    }
    
    func navigateBackToLogin() {
        //
    }
}
