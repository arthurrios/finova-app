//
//  CompactCurrencyLocaleTests.swift
//  FinovaTests
//
//  Compact amounts always used a decimal point, so Portuguese read "R$20.9k" instead of "R$20,9k".
//

import Foundation
import XCTest

@testable import Finova

final class CompactCurrencyLocaleTests: XCTestCase {

    func testCompactAmountsUseTheLocalesDecimalMark() {
        let portuguese = CurrencyUtils.compactString(amountMinor: 2_090_000, locale: Locale(identifier: "pt_BR"))
        let english = CurrencyUtils.compactString(amountMinor: 2_090_000, locale: Locale(identifier: "en_US"))

        XCTAssertTrue(portuguese.hasSuffix("20,9k"), portuguese)
        XCTAssertTrue(english.hasSuffix("20.9k"), english)
    }

    func testWholeCompactAmountsStayWhole() {
        XCTAssertTrue(
            CurrencyUtils.compactString(amountMinor: 25_000_000, locale: Locale(identifier: "pt_BR")).hasSuffix("250k"))
        XCTAssertTrue(
            CurrencyUtils.compactString(amountMinor: 1_500_000_000, locale: Locale(identifier: "pt_BR")).hasSuffix("15M"))
    }
}
