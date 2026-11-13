//
//  AppConfig.swift
//  FinanceApp
//
//  Created by Arthur Rios on 10/05/25.
//

import Foundation

struct AppConfig {
    /// Fallback currency code if none is set and device locale has no currency
    static let fallbackCurrencyCode: String = "USD"

    /// Returns the currency code to use for formatting.
    /// If user has selected "auto", uses device locale currency.
    /// Otherwise, uses the user's selected currency code.
    static var currencyCode: String {
        let savedCode = UserDefaultsManager.getCurrencyCode()
        if savedCode == UserDefaultsManager.currencyAutoValue {
            return Locale.current.currency?.identifier ?? fallbackCurrencyCode
        } else {
            return savedCode
        }
    }

    /// Returns the device's locale currency code (for display in settings)
    static var deviceLocaleCurrencyCode: String {
        return Locale.current.currency?.identifier ?? fallbackCurrencyCode
    }
}
