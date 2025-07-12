//
//  AppConfig.swift
//  FinanceApp
//
//  Created by Arthur Rios on 10/05/25.
//

import Foundation

struct AppConfig {
    static var defaultCurrencyCode: String = "USD"
    
    static var useDeviceLocaleCurrency: Bool = true
    
    static var currencyCode: String {
        if useDeviceLocaleCurrency {
            return Locale.current.currency?.identifier ?? "USD"
        } else {
            return defaultCurrencyCode
        }
    }
}
