//
//  CurrencyUtils.swift
//  FinanceApp
//
//  Created by Arthur Rios on 10/05/25.
//

import Foundation
import UIKit

public struct CurrencyUtils {

  private static let defaultFractionDigits: [String: Int] = [
    "USD": 2, "EUR": 2, "JPY": 0, "TND": 3
  ]

  static func fractionDigits(for currencyCode: String) -> Int {
    var digits: Int32 = 0

    CFNumberFormatterGetDecimalInfoForCurrencyCode(currencyCode as CFString, &digits, nil)

    if digits >= 0 { return Int(digits) }
    return defaultFractionDigits[currencyCode] ?? 2
  }

  public static func localizedString(amountMinor: Int, locale: Locale = .autoupdatingCurrent)
    -> String {
    let code = AppConfig.currencyCode
    let frac = fractionDigits(for: code)
    let divisor = NSDecimalNumber(decimal: pow(10, frac) as Decimal)
    let amountDecimal = NSDecimalNumber(value: amountMinor).dividing(by: divisor)

    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = locale
    formatter.currencyCode = code
    formatter.minimumFractionDigits = frac
    formatter.maximumFractionDigits = frac

    return formatter.string(from: amountDecimal) ?? "\(amountDecimal)"
  }

  public static func localizedAttributedString(
    amountMinor: Int,
    symbolFont: UIFont? = nil,
    font: Fonts? = nil,
    locale: Locale = .autoupdatingCurrent
  ) -> NSAttributedString {
    let code = AppConfig.currencyCode
    let frac = fractionDigits(for: code)
    let divisor = NSDecimalNumber(decimal: pow(10, frac) as Decimal)
    let amountDecimal = NSDecimalNumber(value: amountMinor).dividing(by: divisor)

    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = locale
    formatter.currencyCode = code
    formatter.minimumFractionDigits = frac
    formatter.maximumFractionDigits = frac

    let plain = formatter.string(from: amountDecimal) ?? "\(amountDecimal)"
    let attr = NSMutableAttributedString(string: plain)

    let fullRange = NSRange(location: 0, length: plain.utf16.count)
    let bodyFont = font?.font ?? UIFont.preferredFont(forTextStyle: .body)
    attr.addAttribute(.font, value: bodyFont, range: fullRange)

    if let symbolFont = symbolFont {
      let symbol = formatter.currencySymbol ?? code
      for range in plain.ranges(of: symbol) {
        let nsRange = NSRange(range, in: plain)
        attr.addAttribute(.font, value: symbolFont, range: nsRange)
      }
    }

    return attr
  }
}

extension String {
  fileprivate func ranges(of substring: String) -> [Range<String.Index>] {
    var results: [Range<String.Index>] = []
    var start = startIndex
    while let range = self[start...].range(of: substring) {
      results.append(range)
      start = range.upperBound
    }
    return results
  }
}

extension Int {
  public var currencyString: String {
    CurrencyUtils.localizedString(amountMinor: self)
  }

  public func currencyAttributedString(symbolFont: UIFont? = nil, font: Fonts? = nil)
    -> NSAttributedString {
    CurrencyUtils.localizedAttributedString(amountMinor: self, symbolFont: symbolFont, font: font)
  }

  /// Returns a compact currency string for large amounts (e.g., "R$ 1.5k", "$2.3M")
  /// Uses the dynamic currency symbol from AppConfig
  public var compactCurrencyString: String {
    CurrencyUtils.compactString(amountMinor: self)
  }
}

// MARK: - Compact Currency Formatting
extension CurrencyUtils {

  /// Returns a compact currency string for large amounts
  /// Uses abbreviations like k (thousands), M (millions) for readability
  public static func compactString(amountMinor: Int, locale: Locale = .autoupdatingCurrent) -> String {
    let code = AppConfig.currencyCode
    let frac = fractionDigits(for: code)
    let divisor = pow(10.0, Double(frac))
    let amount = Double(abs(amountMinor)) / divisor
    let prefix = amountMinor < 0 ? "-" : ""

    // Get currency symbol
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = locale
    formatter.currencyCode = code
    let symbol = formatter.currencySymbol ?? code

    // Format based on magnitude
    if amount >= 1_000_000 {
      let millions = amount / 1_000_000
      if millions >= 10 {
        return "\(prefix)\(symbol)\(String(format: "%.0f", millions))M"
      }
      return "\(prefix)\(symbol)\(String(format: "%.1f", millions))M"
    } else if amount >= 1_000 {
      let thousands = amount / 1_000
      if thousands >= 100 {
        return "\(prefix)\(symbol)\(String(format: "%.0f", thousands))k"
      }
      return "\(prefix)\(symbol)\(String(format: "%.1f", thousands))k"
    } else {
      // For smaller values, use regular currency formatting
      return amountMinor.currencyString
    }
  }
}

extension Int {
  public var isZero: Bool { self == 0 }
}
