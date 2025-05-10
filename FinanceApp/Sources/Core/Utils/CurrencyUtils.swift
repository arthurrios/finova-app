//
//  CurrencyUtils.swift
//  FinanceApp
//
//  Created by Arthur Rios on 10/05/25.
//

import Foundation

public struct CurrencyUtils {
    
    private static let defaultFractionDigits: [String: Int] = [
        "USD": 2, "EUR": 2, "JPY": 0, "TND": 3
    ]
    
    private static func fractionDigits(for currencyCode: String) -> Int {
        var digits: Int32 = 0
        
        CFNumberFormatterGetDecimalInfoForCurrencyCode(currencyCode as CFString, &digits, nil)
        
        if digits >= 0 { return Int(digits) }
        return defaultFractionDigits[currencyCode] ?? 2
    }
    
    public static func localizedString(amountMinor: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let code = AppConfig.currencyCode
        let fractionDigits = fractionDigits(for: code)
        
        let divisor = NSDecimalNumber(decimal: pow(10, fractionDigits) as Decimal)
        let amountDecimal = NSDecimalNumber(value: amountMinor).dividing(by: divisor)
        
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.locale = locale
        numberFormatter.currencyCode = code
        numberFormatter.minimumFractionDigits = fractionDigits
        numberFormatter.maximumFractionDigits = fractionDigits
        
        return numberFormatter.string(from: amountDecimal) ?? "\(amountDecimal)"
    }
}

public extension Int {
    var currencyString: String {
        CurrencyUtils.localizedString(amountMinor: self)
    }
}

public extension Int {
    var isZero: Bool { self == 0 }
}

