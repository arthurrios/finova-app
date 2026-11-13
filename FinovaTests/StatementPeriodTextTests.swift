//
//  StatementPeriodTextTests.swift
//  FinovaTests
//
//  The statement screen's period started ON the previous closing date, but a purchase made that day
//  belongs to the previous statement — so the range claimed a day this statement does not cover.
//

import Foundation
import XCTest

@testable import Finova

final class StatementPeriodTextTests: XCTestCase {

    func testThePeriodStartsOnThePreviousClosing() {
        let calendar = Calendar.current
        let closing = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let due = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let card = CreditCard(
            id: 1, name: "Card", lastFourDigits: "4242", cardBrand: .visa,
            closingDay: 5, dueDay: 15, creditLimit: nil, cardColor: .blue, userId: "u",
            isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date())
        let statement = CreditCardStatement(
            id: 1, creditCardId: 1, closingDate: closing, dueDate: due, totalAmount: 0,
            isPaid: false, paidDate: nil, paidAmount: nil, isDatesOverridden: false, userId: "u",
            createdAt: Date(), updatedAt: Date())

        let viewModel = StatementDetailsViewModel(card: card, statement: statement)

        XCTAssertEqual(
            viewModel.periodText, "05/09/2026 — 04/10/2026",
            "A purchase on 5 September is on October's statement, and one on 5 October on November's")
    }

    func testAMonthEndCardStartsOnItsRealPreviousClosing() {
        // A card closing on the 31st closes on 30 April and on 31 March. Subtracting a month from
        // 30 April gave 30 March, so April's period claimed a day that is on March's statement.
        let calendar = Calendar.current
        let closing = calendar.date(from: DateComponents(year: 2026, month: 4, day: 30))!
        let due = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let card = CreditCard(
            id: 1, name: "Card", lastFourDigits: "4242", cardBrand: .visa,
            closingDay: 31, dueDay: 10, creditLimit: nil, cardColor: .blue, userId: "u",
            isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date())
        let statement = CreditCardStatement(
            id: 1, creditCardId: 1, closingDate: closing, dueDate: due, totalAmount: 0,
            isPaid: false, paidDate: nil, paidAmount: nil, isDatesOverridden: false, userId: "u",
            createdAt: Date(), updatedAt: Date())

        let viewModel = StatementDetailsViewModel(card: card, statement: statement)

        XCTAssertEqual(viewModel.periodText, "31/03/2026 — 29/04/2026")
    }
}
