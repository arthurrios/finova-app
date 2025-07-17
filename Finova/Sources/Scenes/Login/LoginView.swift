//
//  LoginView.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

final class LoginView: UIView {
    public weak var delegate: LoginViewDelegate?
    
    @IBOutlet private var inputFields: [Input]!
    
    private var isSmallScreen: Bool {
        return UIScreen.main.bounds.height <= 667
    }
    
    let containerView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing6, leading: Metrics.spacing8, bottom: 0, trailing: Metrics.spacing8)
        view.layer.opacity = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let loginImageView = LogoGraphic()
    
    let appLogoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "appLogo")
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true  // Hidden by default
        return imageView
    }()
    
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
    
    let emailTextField = Input(type: .email, placeholder: "input.email".localized)
    let passwordTextField = Input(type: .password, placeholder: "input.password".localized)
    
    let separator: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let button = Button(label: "login.button".localized)
    
    let appleSignInButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("login.appleSignIn".localized, for: .normal)
        button.setTitleColor(Colors.gray700, for: .normal)
        button.titleLabel?.font = Fonts.buttonSM.font
        button.backgroundColor = Colors.gray100
        button.layer.cornerRadius = CornerRadius.large
        button.layer.borderWidth = 1
        button.layer.borderColor = Colors.gray300.cgColor
        
        if let appleIcon = UIImage(systemName: "applelogo") {
            let smallIcon = appleIcon.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            ).withTintColor(Colors.gray700, renderingMode: .alwaysOriginal)
            button.setImage(smallIcon, for: .normal)
        }
        
        button.semanticContentAttribute = .forceRightToLeft
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: -8)
        
        button.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight).isActive = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    let googleSignInButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("login.googleSignIn".localized, for: .normal)
        button.setTitleColor(Colors.gray700, for: .normal)
        button.titleLabel?.font = Fonts.buttonSM.font
        button.backgroundColor = Colors.gray100
        button.layer.cornerRadius = CornerRadius.large
        button.layer.borderWidth = 1
        button.layer.borderColor = Colors.gray300.cgColor
        
        if let icon = UIImage(named: "googleLogo") {
            let smallIcon = icon.resizedPreservingColor(to: CGSize(width: 20, height: 20))
            button.setImage(smallIcon, for: .normal)
        }
        
        button.semanticContentAttribute = .forceRightToLeft
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: -8)
        
        button.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight).isActive = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    let registerLinkContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let dontHaveAccountLabel: UILabel = {
        let label = UILabel()
        label.text = "login.dontHaveAccount".localized
        label.fontStyle = Fonts.textSM
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let registerLinkButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("login.registerLink".localized, for: .normal)
        button.setTitleColor(Colors.mainMagenta, for: .normal)
        button.titleLabel?.font = Fonts.textSM.font
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private var largeScreenConstraints: [NSLayoutConstraint] = []
    private var smallScreenConstraints: [NSLayoutConstraint] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupDelegates()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        loginImageView.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(handleLoginButtonTapped), for: .touchUpInside)
        appleSignInButton.addTarget(self, action: #selector(handleAppleSignInTapped), for: .touchUpInside)
        googleSignInButton.addTarget(
            self, action: #selector(handleGoogleSignInTapped), for: .touchUpInside)
        registerLinkButton.addTarget(
            self, action: #selector(handleRegisterLinkTapped), for: .touchUpInside)
        
        backgroundColor = Colors.gray100
        
        if isSmallScreen {
            loginImageView.isHidden = true
            appLogoImageView.isHidden = false
            addSubview(appLogoImageView)
        } else {
            loginImageView.isHidden = false
            appLogoImageView.isHidden = true
            addSubview(loginImageView)
        }
        
        addSubview(containerView)
        containerView.addSubview(emailTextField)
        containerView.addSubview(passwordTextField)
        containerView.addSubview(welcomeTitleLabel)
        containerView.addSubview(welcomeSubtitleLabel)
        containerView.addSubview(separator)
        containerView.addSubview(button)
        containerView.addSubview(appleSignInButton)
        containerView.addSubview(googleSignInButton)
        containerView.addSubview(registerLinkContainer)
        registerLinkContainer.addSubview(dontHaveAccountLabel)
        registerLinkContainer.addSubview(registerLinkButton)
        
        setupScreenAdaptiveConstraints()
    }
    
    private func setupScreenAdaptiveConstraints() {
        let commonConstraints = [
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            welcomeTitleLabel.leadingAnchor.constraint(
                equalTo: containerView.layoutMarginsGuide.leadingAnchor),
            welcomeTitleLabel.trailingAnchor.constraint(
                equalTo: containerView.layoutMarginsGuide.trailingAnchor),
            
            welcomeSubtitleLabel.topAnchor.constraint(
                equalTo: welcomeTitleLabel.bottomAnchor, constant: Metrics.spacing2),
            welcomeSubtitleLabel.leadingAnchor.constraint(equalTo: welcomeTitleLabel.leadingAnchor),
            welcomeSubtitleLabel.trailingAnchor.constraint(equalTo: welcomeTitleLabel.trailingAnchor),
            
            emailTextField.topAnchor.constraint(
                equalTo: welcomeSubtitleLabel.bottomAnchor, constant: Metrics.spacing5),
            emailTextField.leadingAnchor.constraint(equalTo: welcomeSubtitleLabel.leadingAnchor),
            emailTextField.trailingAnchor.constraint(equalTo: welcomeSubtitleLabel.trailingAnchor),
            
            passwordTextField.topAnchor.constraint(
                equalTo: emailTextField.bottomAnchor, constant: Metrics.spacing3),
            passwordTextField.leadingAnchor.constraint(equalTo: emailTextField.leadingAnchor),
            passwordTextField.trailingAnchor.constraint(equalTo: emailTextField.trailingAnchor),
            
            separator.topAnchor.constraint(
                equalTo: passwordTextField.bottomAnchor, constant: Metrics.spacing3),
            separator.leadingAnchor.constraint(equalTo: passwordTextField.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: passwordTextField.trailingAnchor),
            
            button.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: Metrics.spacing3),
            button.leadingAnchor.constraint(equalTo: separator.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: separator.trailingAnchor),
            
            appleSignInButton.topAnchor.constraint(equalTo: button.bottomAnchor, constant: Metrics.spacing3),
            appleSignInButton.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            appleSignInButton.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            
            googleSignInButton.topAnchor.constraint(
                equalTo: appleSignInButton.bottomAnchor, constant: Metrics.spacing3),
            googleSignInButton.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            googleSignInButton.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            
            registerLinkContainer.topAnchor.constraint(
                equalTo: googleSignInButton.bottomAnchor, constant: 1),
            registerLinkContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            registerLinkContainer.heightAnchor.constraint(equalToConstant: 44),
            
            dontHaveAccountLabel.leadingAnchor.constraint(equalTo: registerLinkContainer.leadingAnchor),
            dontHaveAccountLabel.centerYAnchor.constraint(equalTo: registerLinkContainer.centerYAnchor),
            
            registerLinkButton.leadingAnchor.constraint(
                equalTo: dontHaveAccountLabel.trailingAnchor, constant: Metrics.spacing1),
            registerLinkButton.centerYAnchor.constraint(equalTo: registerLinkContainer.centerYAnchor),
            registerLinkButton.trailingAnchor.constraint(
                lessThanOrEqualTo: registerLinkContainer.trailingAnchor)
        ]
        
        if isSmallScreen {
            // Small screen constraints (similar to register view)
            smallScreenConstraints = [
                // Small logo at top center
                appLogoImageView.topAnchor.constraint(
                    equalTo: safeAreaLayoutGuide.topAnchor, constant: Metrics.spacing5),
                appLogoImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                appLogoImageView.heightAnchor.constraint(equalToConstant: 100),
                appLogoImageView.widthAnchor.constraint(equalToConstant: 100),
                
                // Container starts below small logo
                containerView.topAnchor.constraint(
                    equalTo: appLogoImageView.bottomAnchor, constant: Metrics.spacing5),
                
                // Welcome title starts at container top
                welcomeTitleLabel.topAnchor.constraint(equalTo: containerView.layoutMarginsGuide.topAnchor)
            ]
            
            NSLayoutConstraint.activate(commonConstraints + smallScreenConstraints)
        } else {
            // Large screen constraints (original layout)
            largeScreenConstraints = [
                // Large logo graphic
                loginImageView.topAnchor.constraint(equalTo: topAnchor),
                loginImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing3),
                loginImageView.trailingAnchor.constraint(
                    equalTo: trailingAnchor, constant: -Metrics.spacing3),
                
                // Container starts below large logo
                containerView.topAnchor.constraint(equalTo: loginImageView.bottomAnchor),
                
                // Welcome title starts at container top
                welcomeTitleLabel.topAnchor.constraint(equalTo: containerView.layoutMarginsGuide.topAnchor)
            ]
            
            NSLayoutConstraint.activate(commonConstraints + largeScreenConstraints)
        }
    }
    
    private func setupDelegates() {
        emailTextField.textField.delegate = self
        passwordTextField.textField.delegate = self
    }
    
    @objc
    private func handleLoginButtonTapped() {
        let inputs = [emailTextField, passwordTextField]
        
        let invalids = inputs.filter { !$0.textField.hasText }
        
        invalids.forEach { $0.setError(true) }
        
        guard invalids.isEmpty else { return }
        
        let email = emailTextField.textField.text ?? ""
        let password = passwordTextField.textField.text ?? ""
        delegate?.sendLoginData(email: email, password: password)
    }
    
    @objc
    private func handleRegisterLinkTapped() {
        delegate?.navigateToRegister()
    }
    
    @objc
    private func handleGoogleSignInTapped() {
        delegate?.signInWithGoogle()
    }
    
    @objc
    private func handleAppleSignInTapped() {
        delegate?.signInWithApple()
    }
}

extension LoginView: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
