//
//  RegisterView.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/06/25.
//

import Foundation
import UIKit

final class RegisterView: UIView {
    public weak var delegate: RegisterViewDelegate?
    
    let containerView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing7,
            leading: Metrics.spacing8,
            bottom: Metrics.spacing3,
            trailing: Metrics.spacing8)
        view.layer.opacity = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let appLogoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "appLogo")
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let welcomeTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "register.welcome.title".localized
        label.font = Fonts.titleSM.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let welcomeSubtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "register.welcome.subtitle".localized
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let nameTextField = Input(placeholder: "input.name".localized)
    private let emailTextField = Input(type: .email, placeholder: "input.email".localized)
    private let passwordTextField = Input(type: .password, placeholder: "input.password".localized)
    private let confirmPasswordTextField = Input(type: .password, placeholder: "input.confirmPassword".localized)
    
    let separator: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let registerButton = Button(label: "register.button".localized)
    
    let loginLinkContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let alreadyHaveAccountLabel: UILabel = {
        let label = UILabel()
        label.text = "register.alreadyHaveAccount".localized
        label.fontStyle = Fonts.textSM
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let loginLinkButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("register.loginLink".localized, for: .normal)
        button.setTitleColor(Colors.mainMagenta, for: .normal)
        button.titleLabel?.font = Fonts.textSM.font
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupDelegates()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        registerButton.addTarget(self, action: #selector(handleRegisterButtonTapped), for: .touchUpInside)
        loginLinkButton.addTarget(self, action: #selector(handleLoginLinkTapped), for: .touchUpInside)
        
        backgroundColor = Colors.gray100
        addSubview(containerView)
        containerView.addSubview(appLogoImageView)
        containerView.addSubview(welcomeTitleLabel)
        containerView.addSubview(welcomeSubtitleLabel)
        containerView.addSubview(nameTextField)
        containerView.addSubview(emailTextField)
        containerView.addSubview(passwordTextField)
        containerView.addSubview(confirmPasswordTextField)
        containerView.addSubview(separator)
        containerView.addSubview(registerButton)
        containerView.addSubview(loginLinkContainer)
        loginLinkContainer.addSubview(alreadyHaveAccountLabel)
        loginLinkContainer.addSubview(loginLinkButton)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            
            appLogoImageView.topAnchor.constraint(equalTo: containerView.layoutMarginsGuide.topAnchor),
            appLogoImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            appLogoImageView.heightAnchor.constraint(equalToConstant: 100),
            appLogoImageView.widthAnchor.constraint(equalToConstant: 100),
            
            welcomeTitleLabel.topAnchor.constraint(equalTo: appLogoImageView.bottomAnchor, constant: Metrics.spacing8),
            welcomeTitleLabel.leadingAnchor.constraint(equalTo: containerView.layoutMarginsGuide.leadingAnchor),
            welcomeTitleLabel.trailingAnchor.constraint(equalTo: containerView.layoutMarginsGuide.trailingAnchor),
            
            welcomeSubtitleLabel.topAnchor.constraint(equalTo: welcomeTitleLabel.bottomAnchor, constant: Metrics.spacing2),
            welcomeSubtitleLabel.leadingAnchor.constraint(equalTo: welcomeTitleLabel.leadingAnchor),
            welcomeSubtitleLabel.trailingAnchor.constraint(equalTo: welcomeTitleLabel.trailingAnchor),
            
            nameTextField.topAnchor.constraint(equalTo: welcomeSubtitleLabel.bottomAnchor, constant: Metrics.spacing7),
            nameTextField.leadingAnchor.constraint(equalTo: welcomeSubtitleLabel.leadingAnchor),
            nameTextField.trailingAnchor.constraint(equalTo: welcomeSubtitleLabel.trailingAnchor),
            
            emailTextField.topAnchor.constraint(equalTo: nameTextField.bottomAnchor, constant: Metrics.spacing3),
            emailTextField.leadingAnchor.constraint(equalTo: nameTextField.leadingAnchor),
            emailTextField.trailingAnchor.constraint(equalTo: nameTextField.trailingAnchor),
            
            passwordTextField.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: Metrics.spacing3),
            passwordTextField.leadingAnchor.constraint(equalTo: emailTextField.leadingAnchor),
            passwordTextField.trailingAnchor.constraint(equalTo: emailTextField.trailingAnchor),
            
            confirmPasswordTextField.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: Metrics.spacing3),
            confirmPasswordTextField.leadingAnchor.constraint(equalTo: passwordTextField.leadingAnchor),
            confirmPasswordTextField.trailingAnchor.constraint(equalTo: passwordTextField.trailingAnchor),
            
            separator.topAnchor.constraint(equalTo: confirmPasswordTextField.bottomAnchor, constant: Metrics.spacing7),
            separator.leadingAnchor.constraint(equalTo: confirmPasswordTextField.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: confirmPasswordTextField.trailingAnchor),
            
            registerButton.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: Metrics.spacing7),
            registerButton.leadingAnchor.constraint(equalTo: separator.leadingAnchor),
            registerButton.trailingAnchor.constraint(equalTo: separator.trailingAnchor),
            
            loginLinkContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            loginLinkContainer.heightAnchor.constraint(equalToConstant: 44),
            loginLinkContainer.bottomAnchor.constraint(equalTo: containerView.layoutMarginsGuide.bottomAnchor),
            
            alreadyHaveAccountLabel.leadingAnchor.constraint(equalTo: loginLinkContainer.leadingAnchor),
            alreadyHaveAccountLabel.centerYAnchor.constraint(equalTo: loginLinkContainer.centerYAnchor),
            
            loginLinkButton.leadingAnchor.constraint(equalTo: alreadyHaveAccountLabel.trailingAnchor, constant: Metrics.spacing1),
            loginLinkButton.centerYAnchor.constraint(equalTo: loginLinkContainer.centerYAnchor),
            loginLinkButton.trailingAnchor.constraint(lessThanOrEqualTo: loginLinkContainer.trailingAnchor)
        ])
    }
    
    private func setupDelegates() {
        nameTextField.textField.delegate = self
        emailTextField.textField.delegate = self
        passwordTextField.textField.delegate = self
        confirmPasswordTextField.textField.delegate = self
    }
    
    @objc
    private func handleRegisterButtonTapped() {
        let inputs = [nameTextField, emailTextField, passwordTextField, confirmPasswordTextField]
        
        let invalids = inputs.filter { !$0.textField.hasText }
        
        invalids.forEach { $0.setError(true) }
        
        guard invalids.isEmpty else { return }
        
        let name = nameTextField.textField.text ?? ""
        let email = emailTextField.textField.text ?? ""
        let password = passwordTextField.textField.text ?? ""
        let confirmPassword = confirmPasswordTextField.textField.text ?? ""
        
        delegate?.sendRegisterData(name: name, email: email, password: password, confirmPassword: confirmPassword)
    }
    
    @objc
    private func handleLoginLinkTapped() {
        delegate?.navigateBackToLogin()
    }
}

extension RegisterView: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
