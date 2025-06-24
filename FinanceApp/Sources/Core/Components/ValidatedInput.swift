//
//  ValidatedInput.swift
//  FinanceApp
//
//  Created by Arthur Rios on 25/06/25.
//

import Foundation
import SwiftEmailValidator
import UIKit

protocol ValidatedInputDelegate: AnyObject {
    func validatedInputDidChange(_ input: ValidatedInput, isValid: Bool)
}

class ValidatedInput: UIView {
    
    enum ValidationType {
        case email
        case password
        case confirmPassword(originalPassword: String)
        case name
        case none
    }
    
    // MARK: - Properties
    
    weak var delegate: ValidatedInputDelegate?
    
    private var validationType: ValidationType
    private let inputField: Input
    private let validationLabel: UILabel
    private var validationLabelHeightConstraint: NSLayoutConstraint?
    private var validationLabelTopConstraint: NSLayoutConstraint?
    
    private var isValid: Bool = false {
        didSet {
            updateValidationAppearance()
            delegate?.validatedInputDidChange(self, isValid: isValid)
        }
    }
    
    var text: String? {
        return inputField.textField.text
    }
    
    var textField: UITextField {
        return inputField.textField
    }
    
    // MARK: - Initialization
    
    init(type: ValidationType, placeholder: String) {
        self.validationType = type
        
        switch type {
        case .email:
            self.inputField = Input(type: .email, placeholder: placeholder)
        case .password, .confirmPassword:
            self.inputField = Input(type: .password, placeholder: placeholder)
        default:
            self.inputField = Input(placeholder: placeholder)
        }
        
        self.validationLabel = UILabel()
        
        super.init(frame: .zero)
        setupUI()
        setupValidation()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        
        // Configure validation label
        validationLabel.font = Fonts.textXS.font
        validationLabel.numberOfLines = 0
        validationLabel.translatesAutoresizingMaskIntoConstraints = false
        validationLabel.alpha = 0  // Hidden initially
        
        addSubview(inputField)
        addSubview(validationLabel)
        
        // Create dynamic constraints for validation label
        validationLabelTopConstraint = validationLabel.topAnchor.constraint(
            equalTo: inputField.bottomAnchor, constant: 0)  // Start with 0 spacing when hidden
        validationLabelHeightConstraint = validationLabel.heightAnchor.constraint(equalToConstant: 0)  // Start with 0 height
        
        NSLayoutConstraint.activate([
            // Input field constraints
            inputField.topAnchor.constraint(equalTo: topAnchor),
            inputField.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputField.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            // Validation label constraints (dynamic)
            validationLabelTopConstraint!,
            validationLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing2),
            validationLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -Metrics.spacing2),
            validationLabelHeightConstraint!,
            validationLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    private func setupValidation() {
        inputField.textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        inputField.textField.addTarget(self, action: #selector(editingDidEnd), for: .editingDidEnd)
    }
    
    // MARK: - Validation Logic
    
    @objc private func textDidChange() {
        guard let text = inputField.textField.text, !text.isEmpty else {
            hideValidation()
            isValid = false
            return
        }
        
        validateInput(text)
    }
    
    @objc private func editingDidEnd() {
        guard let text = inputField.textField.text, !text.isEmpty else {
            hideValidation()
            isValid = false
            return
        }
        
        validateInput(text)
    }
    
    private func validateInput(_ text: String) {
        switch validationType {
        case .email:
            validateEmail(text)
        case .password:
            validatePassword(text)
        case .confirmPassword(let originalPassword):
            validateConfirmPassword(text, against: originalPassword)
        case .name:
            validateName(text)
        case .none:
            isValid = true
        }
    }
    
    private func validateEmail(_ email: String) {
        let isValidFormat = EmailSyntaxValidator.correctlyFormatted(
            email,
            compatibility: .ascii
        )
        
        if isValidFormat {
            // Hide validation when email is valid
            hideValidation()
            isValid = true
        } else {
            showValidation(message: "email.validation.invalid".localized, isValid: false)
            isValid = false
        }
    }
    
    private func validatePassword(_ password: String) {
        // Comprehensive Firebase password validation
        let hasMinLength = password.count >= 6
        let hasUppercase = password.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasLowercase = password.range(of: "[a-z]", options: .regularExpression) != nil
        let hasNumber = password.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSpecialChar =
        password.range(
            of: "[!@#$%^&*()_+\\-=\\[\\]{};':\"\\\\|,.<>\\/?]", options: .regularExpression) != nil
        
        let allRequirementsMet =
        hasMinLength && hasUppercase && hasLowercase && hasNumber && hasSpecialChar
        
        if allRequirementsMet {
            // Hide validation when password is fully valid
            hideValidation()
            isValid = true
        } else {
            // Show what's missing
            var missingRequirements: [String] = []
            
            if !hasMinLength {
                missingRequirements.append("• " + "password.validation.minLength".localized)
            }
            if !hasUppercase {
                missingRequirements.append("• " + "password.validation.hasUppercase".localized)
            }
            if !hasLowercase {
                missingRequirements.append("• " + "password.validation.hasUppercase".localized)
            }
            if !hasNumber {
                missingRequirements.append("• " + "password.validation.hasNumber".localized)
            }
            if !hasSpecialChar {
                missingRequirements.append("• " + "password.validation.hasSpecialCharacter".localized)
            }
            
            let message = "password.mustContain".localized + ":\n" + missingRequirements.joined(separator: "\n")
            showValidation(message: message, isValid: false)
            isValid = false
        }
    }
    
    private func validateConfirmPassword(_ confirmPassword: String, against originalPassword: String) {
        let passwordsMatch = confirmPassword == originalPassword && !confirmPassword.isEmpty
        
        if passwordsMatch {
            // Hide validation when passwords match
            hideValidation()
            isValid = true
        } else {
            showValidation(message: "validation.error.passwordsDoNotMatch".localized, isValid: false)
            isValid = false
        }
    }
    
    private func validateName(_ name: String) {
        let isValidName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        isValid = isValidName
        
        if !isValidName {
            showValidation(message: "validation.error.nameRequired".localized, isValid: false)
        } else {
            // Hide validation when name is valid
            hideValidation()
        }
    }
    
    // MARK: - UI Updates
    
    private func showValidation(message: String, isValid: Bool) {
        validationLabel.text = message
        validationLabel.textColor = isValid ? Colors.mainMagenta : Colors.mainRed
        
        // Update constraints to show validation
        validationLabelTopConstraint?.constant = Metrics.spacing1
        validationLabelHeightConstraint?.isActive = false
        
        UIView.animate(
            withDuration: 0.3,
            animations: {
                self.validationLabel.alpha = 1
                self.layoutIfNeeded()
            })
    }
    
    private func hideValidation() {
        // Update constraints to hide validation and reorganize layout
        validationLabelTopConstraint?.constant = 0
        validationLabelHeightConstraint?.isActive = true
        validationLabelHeightConstraint?.constant = 0
        
        UIView.animate(
            withDuration: 0.3,
            animations: {
                self.validationLabel.alpha = 0
                self.layoutIfNeeded()
            })
    }
    
    private func updateValidationAppearance() {
        // Update input field border color based on validation state
        if validationLabel.alpha > 0 && !isValid {
            inputField.layer.borderColor = Colors.mainRed.cgColor
        } else {
            inputField.layer.borderColor = Colors.gray300.cgColor
        }
    }
    
    // MARK: - Public Methods
    
    func setError(_ hasError: Bool) {
        inputField.setError(hasError)
    }
    
    func updateConfirmPasswordValidation(against newPassword: String) {
        // Update the validation type with new password for real-time matching
        if case .confirmPassword = validationType {
            // CRITICAL: Update the stored validationType with the new password
            validationType = .confirmPassword(originalPassword: newPassword)
            
            // If we have text in the confirm password field, validate it against new password
            if let currentText = inputField.textField.text, !currentText.isEmpty {
                validateConfirmPassword(currentText, against: newPassword)
            } else {
                // If field is empty, hide any existing validation
                hideValidation()
                isValid = false
            }
        }
    }
}
