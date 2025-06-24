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

  // Enhanced validated inputs
  private let nameInput = ValidatedInput(type: .name, placeholder: "input.name".localized)
  private let emailInput = ValidatedInput(type: .email, placeholder: "input.email".localized)
  private let passwordInput = ValidatedInput(
    type: .password, placeholder: "input.password".localized)
  private let confirmPasswordInput = ValidatedInput(
    type: .confirmPassword(originalPassword: ""), placeholder: "input.confirmPassword".localized)

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

  // Validation state tracking
  private var validationStates: [ValidatedInput: Bool] = [:]

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
    setupDelegates()
    setupValidation()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    registerButton.addTarget(
      self, action: #selector(handleRegisterButtonTapped), for: .touchUpInside)
    loginLinkButton.addTarget(self, action: #selector(handleLoginLinkTapped), for: .touchUpInside)

    backgroundColor = Colors.gray100
    addSubview(containerView)
    containerView.addSubview(appLogoImageView)
    containerView.addSubview(welcomeTitleLabel)
    containerView.addSubview(welcomeSubtitleLabel)
    containerView.addSubview(nameInput)
    containerView.addSubview(emailInput)
    containerView.addSubview(passwordInput)
    containerView.addSubview(confirmPasswordInput)
    containerView.addSubview(separator)
    containerView.addSubview(registerButton)
    containerView.addSubview(loginLinkContainer)
    loginLinkContainer.addSubview(alreadyHaveAccountLabel)
    loginLinkContainer.addSubview(loginLinkButton)

    setupConstraints()
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      // Center the container both horizontally and vertically
      containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
      containerView.centerYAnchor.constraint(equalTo: centerYAnchor),

      // Set container width and height constraints
      containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      containerView.trailingAnchor.constraint(equalTo: trailingAnchor),

      appLogoImageView.topAnchor.constraint(equalTo: containerView.layoutMarginsGuide.topAnchor),
      appLogoImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      appLogoImageView.heightAnchor.constraint(equalToConstant: 100),
      appLogoImageView.widthAnchor.constraint(equalToConstant: 100),

      welcomeTitleLabel.topAnchor.constraint(
        equalTo: appLogoImageView.bottomAnchor, constant: Metrics.spacing8),
      welcomeTitleLabel.leadingAnchor.constraint(
        equalTo: containerView.layoutMarginsGuide.leadingAnchor),
      welcomeTitleLabel.trailingAnchor.constraint(
        equalTo: containerView.layoutMarginsGuide.trailingAnchor),

      welcomeSubtitleLabel.topAnchor.constraint(
        equalTo: welcomeTitleLabel.bottomAnchor, constant: Metrics.spacing2),
      welcomeSubtitleLabel.leadingAnchor.constraint(equalTo: welcomeTitleLabel.leadingAnchor),
      welcomeSubtitleLabel.trailingAnchor.constraint(equalTo: welcomeTitleLabel.trailingAnchor),

      nameInput.topAnchor.constraint(
        equalTo: welcomeSubtitleLabel.bottomAnchor, constant: Metrics.spacing7),
      nameInput.leadingAnchor.constraint(equalTo: welcomeSubtitleLabel.leadingAnchor),
      nameInput.trailingAnchor.constraint(equalTo: welcomeSubtitleLabel.trailingAnchor),

      emailInput.topAnchor.constraint(equalTo: nameInput.bottomAnchor, constant: Metrics.spacing3),
      emailInput.leadingAnchor.constraint(equalTo: nameInput.leadingAnchor),
      emailInput.trailingAnchor.constraint(equalTo: nameInput.trailingAnchor),

      passwordInput.topAnchor.constraint(
        equalTo: emailInput.bottomAnchor, constant: Metrics.spacing3),
      passwordInput.leadingAnchor.constraint(equalTo: emailInput.leadingAnchor),
      passwordInput.trailingAnchor.constraint(equalTo: emailInput.trailingAnchor),

      confirmPasswordInput.topAnchor.constraint(
        equalTo: passwordInput.bottomAnchor, constant: Metrics.spacing3),
      confirmPasswordInput.leadingAnchor.constraint(equalTo: passwordInput.leadingAnchor),
      confirmPasswordInput.trailingAnchor.constraint(equalTo: passwordInput.trailingAnchor),

      separator.topAnchor.constraint(
        equalTo: confirmPasswordInput.bottomAnchor, constant: Metrics.spacing7),
      separator.leadingAnchor.constraint(equalTo: confirmPasswordInput.leadingAnchor),
      separator.trailingAnchor.constraint(equalTo: confirmPasswordInput.trailingAnchor),

      registerButton.topAnchor.constraint(
        equalTo: separator.bottomAnchor, constant: Metrics.spacing7),
      registerButton.leadingAnchor.constraint(equalTo: separator.leadingAnchor),
      registerButton.trailingAnchor.constraint(equalTo: separator.trailingAnchor),

      loginLinkContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
      loginLinkContainer.heightAnchor.constraint(equalToConstant: 44),
      loginLinkContainer.topAnchor.constraint(
        equalTo: registerButton.bottomAnchor, constant: Metrics.spacing3),
      loginLinkContainer.bottomAnchor.constraint(
        equalTo: containerView.layoutMarginsGuide.bottomAnchor),

      alreadyHaveAccountLabel.leadingAnchor.constraint(equalTo: loginLinkContainer.leadingAnchor),
      alreadyHaveAccountLabel.centerYAnchor.constraint(equalTo: loginLinkContainer.centerYAnchor),

      loginLinkButton.leadingAnchor.constraint(
        equalTo: alreadyHaveAccountLabel.trailingAnchor, constant: Metrics.spacing1),
      loginLinkButton.centerYAnchor.constraint(equalTo: loginLinkContainer.centerYAnchor),
      loginLinkButton.trailingAnchor.constraint(
        lessThanOrEqualTo: loginLinkContainer.trailingAnchor)
    ])
  }

  private func setupDelegates() {
    nameInput.textField.delegate = self
    emailInput.textField.delegate = self
    passwordInput.textField.delegate = self
    confirmPasswordInput.textField.delegate = self
  }

  private func setupValidation() {
    // Set up validation delegates
    nameInput.delegate = self
    emailInput.delegate = self
    passwordInput.delegate = self
    confirmPasswordInput.delegate = self

    // Initialize validation states
    validationStates[nameInput] = false
    validationStates[emailInput] = false
    validationStates[passwordInput] = false
    validationStates[confirmPasswordInput] = false

    // Set up password confirmation linkage
    passwordInput.textField.addTarget(
      self, action: #selector(passwordDidChange), for: .editingChanged)
  }

  @objc private func passwordDidChange() {
    let currentPassword = passwordInput.text ?? ""
    confirmPasswordInput.updateConfirmPasswordValidation(against: currentPassword)
  }

  private func updateRegisterButtonState() {
    let allValid = validationStates.values.allSatisfy { $0 }
    registerButton.isEnabled = allValid
    registerButton.alpha = allValid ? 1.0 : 0.6
  }

  @objc
  private func handleRegisterButtonTapped() {
    let inputs = [nameInput, emailInput, passwordInput, confirmPasswordInput]

    // Check for empty fields
    let hasEmptyFields = inputs.contains { input in
      guard let text = input.text else { return true }
      return text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    if hasEmptyFields {
      inputs.forEach { input in
        if let text = input.text, text.trimmingCharacters(in: .whitespaces).isEmpty {
          input.setError(true)
        }
      }
      return
    }

    let name = nameInput.text ?? ""
    let email = emailInput.text ?? ""
    let password = passwordInput.text ?? ""
    let confirmPassword = confirmPasswordInput.text ?? ""

    delegate?.sendRegisterData(
      name: name, email: email, password: password, confirmPassword: confirmPassword)
  }

  @objc
  private func handleLoginLinkTapped() {
    delegate?.navigateBackToLogin()
  }
}

// MARK: - ValidatedInputDelegate

extension RegisterView: ValidatedInputDelegate {
  func validatedInputDidChange(_ input: ValidatedInput, isValid: Bool) {
    validationStates[input] = isValid
    updateRegisterButtonState()
  }
}

// MARK: - UITextFieldDelegate

extension RegisterView: UITextFieldDelegate {
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    textField.resignFirstResponder()
    return true
  }
}
