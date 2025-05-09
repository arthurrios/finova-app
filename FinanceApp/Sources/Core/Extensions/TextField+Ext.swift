//
//  TextField+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 08/05/25.
//

import Foundation
import UIKit
import SwiftEmailValidator

extension UITextField {
    func enableCurrencyMask() {
        keyboardType = .numberPad
        addTarget(self, action: #selector(currencyTextChanged), for: .editingChanged)
    }
    
    func enableEmailValidation(callback: @escaping (Bool) -> Void) {
        addTarget(self, action: #selector(validateEmail), for: .editingChanged)
        objc_setAssociatedObject(self, &AssociatedKeys.validationCallback, callback, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    @objc
    private func currencyTextChanged() {
        
        let digitsOnly = text?.components(separatedBy: CharacterSet.decimalDigits.inverted).joined() ?? ""
        
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
        let isValid = EmailSyntaxValidator.correctlyFormatted(
            email,
            compatibility: .ascii
        )
        if let callback = objc_getAssociatedObject(self, &AssociatedKeys.validationCallback) as? (Bool) -> Void {
            callback(isValid)
        }
    }
}

private struct AssociatedKeys {
    static var validationCallback: UInt8 = 0
}
