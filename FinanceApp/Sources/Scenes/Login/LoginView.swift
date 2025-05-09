//
//  LoginView.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

final class LoginView: UIView {
    public weak var delegate: LoginFlowDelegate?

    let containerView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: Metrics.spacing10, leading: Metrics.spacing8, bottom: 0, trailing: Metrics.spacing8)
        view.layer.opacity = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let loginImageView = LogoGraphic()
    
    let welcomeTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "login.welcome.title".localized
        label.fontStyle = Fonts.titleSM
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let welcomeSubtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "login.welcome.subtitle".localized
        label.fontStyle = Fonts.textSM
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let nameTextField = Input(placeholder: "input.name".localized)
    let emailTextField = Input(type: .email, placeholder: "input.email".localized)
    let passwordTextField = Input(type: .password,placeholder: "input.password".localized)
    
    let separator: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let button = Button(label: "login.button".localized)
    
    override init (frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupDelegates()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        loginImageView.translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Colors.gray100
        addSubview(loginImageView)
        addSubview(containerView)
        containerView.addSubview(nameTextField)
        containerView.addSubview(emailTextField)
        containerView.addSubview(passwordTextField)
        containerView.addSubview(welcomeTitleLabel)
        containerView.addSubview(welcomeSubtitleLabel)
        containerView.addSubview(separator)
        containerView.addSubview(button)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            loginImageView.topAnchor.constraint(equalTo: topAnchor),
            loginImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing3),
            loginImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing3),
            
            containerView.topAnchor.constraint(equalTo: loginImageView.bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            welcomeTitleLabel.topAnchor.constraint(equalTo: containerView.layoutMarginsGuide.topAnchor),
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
            
            separator.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: Metrics.spacing7),
            separator.leadingAnchor.constraint(equalTo: passwordTextField.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: passwordTextField.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            
            button.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: Metrics.spacing7),
            button.leadingAnchor.constraint(equalTo: separator.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: separator.trailingAnchor)
        ])
    }
    
    private func setupDelegates() {
        nameTextField.textField.delegate = self
        emailTextField.textField.delegate = self
        passwordTextField.textField.delegate = self
    }
}

extension LoginView: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
