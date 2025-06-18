//
//  TextField+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 08/05/25.
//

import Foundation
import UIKit

extension UITextField {
  func enableCurrencyMask() {
    keyboardType = .numberPad
    addTarget(self, action: #selector(currencyTextChanged), for: .editingChanged)
  }

  func enableEmailValidation(callback: @escaping (Bool) -> Void) {
    addTarget(self, action: #selector(validateEmail), for: .editingChanged)
    objc_setAssociatedObject(
      self, &AssociatedKeys.validationCallback, callback, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  }

  @objc
  private func currencyTextChanged() {

    let digitsOnly =
      text?.components(separatedBy: CharacterSet.decimalDigits.inverted).joined() ?? ""

    let number = (Double(digitsOnly) ?? 0) / 100

    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencySymbol = ""
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    text = formatter.string(from: NSNumber(value: number))
  }

  @objc private func validateEmail() {
    guard let email = self.text else { return }
    let isValid = isValidEmail(email)
    if let callback = objc_getAssociatedObject(self, &AssociatedKeys.validationCallback)
      as? (Bool) -> Void {
      callback(isValid)
    }
  }

  private func isValidEmail(_ email: String) -> Bool {
    let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
    let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
    return emailPredicate.evaluate(with: email)
  }
}

private struct AssociatedKeys {
  static var validationCallback: UInt8 = 0
}
