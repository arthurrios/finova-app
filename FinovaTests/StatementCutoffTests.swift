//
//  StatementCutoffTests.swift
//  FinovaTests
//
//  A statement is issued on its closing day, so a purchase made that day is on the next one, for
//  every closing day and every month.
//

import XCTest
@testable import Finova

final class StatementCutoffTests: XCTestCase {
    private let service = CreditCardService()
    private let calendar = Calendar.current

    private func card(closingDay: Int) -> CreditCard {
        CreditCard(
            id: 1, name: "Test", lastFourDigits: "1234", cardBrand: .visa,
            closingDay: closingDay, dueDay: 28, creditLimit: nil, cardColor: .blue, userId: "u",
            isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date())
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func lastDay(_ year: Int, _ month: Int) -> Int {
        calendar.range(of: .day, in: .month, for: date(year, month, 1))!.count
    }

    func testEveryClosingDayCutsOffTheSameWayInEveryMonth() {
        for closingDay in 1...31 {
            let card = card(closingDay: closingDay)
            for month in 1...12 {
                let thisClose = min(closingDay, lastDay(2028, month))
                let next = month == 12 ? (2029, 1) : (2028, month + 1)
                let nextClose = date(next.0, next.1, min(closingDay, lastDay(next.0, next.1)))

                XCTAssertEqual(
                    service.calculateClosingDate(card: card, transactionDate: date(2028, month, thisClose)),
                    nextClose, "closing day \(closingDay), month \(month)")
                if thisClose > 1 {
                    XCTAssertEqual(
                        service.calculateClosingDate(card: card, transactionDate: date(2028, month, thisClose - 1)),
                        date(2028, month, thisClose), "closing day \(closingDay), month \(month)")
                }
            }
        }
    }

    func testTheRoutingDateReachesTheMonthsStatementOnEveryClosingDay() {
        for closingDay in 1...31 {
            let card = card(closingDay: closingDay)
            let routed = service.calculateClosingDate(
                card: card, transactionDate: service.routingDate(forStatementMonthOf: date(2028, 3, 1)))
            XCTAssertEqual(routed, date(2028, 3, closingDay), "closing day \(closingDay)")
        }
    }
}
