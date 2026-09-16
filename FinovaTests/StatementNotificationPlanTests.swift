//
//  StatementNotificationPlanTests.swift
//  FinovaTests
//
//  What a statement tells the user, and with which figure.
//

import Foundation
import XCTest

@testable import Finova

final class StatementNotificationPlanTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }

    private let now = Date()

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    private func plan(
        closingIn closing: Int = 5,
        dueIn due: Int = 15,
        total: Int = 120_000,
        isPaid: Bool = false
    ) -> [PlannedStatementNotification] {
        StatementNotificationPlan.plan(
            statementId: 7,
            cardName: "TestCard",
            closingDate: day(closing),
            dueDate: day(due),
            totalAmount: total,
            isPaid: isPaid,
            calendar: calendar,
            now: now)
    }

    // MARK: - What gets planned

    func testAnOpenStatementIsAnnouncedAtClosingAndAgainWhenDue() {
        let planned = plan()

        XCTAssertEqual(planned.map(\.kind), [.closed, .paymentDue])
        XCTAssertEqual(planned.map(\.identifier), ["statement_closed_7", "statement_pay_7"])
    }

    func testBothMessagesCarryTheStatementTotal() {
        for item in plan(total: 254_390) {
            XCTAssertEqual(
                item.amountMinor, 254_390,
                "\(item.kind) must name the amount on the statement row")
        }
    }

    func testTheClosingMessageFiresOnTheClosingDayAndThePaymentOneOnTheDueDay() {
        let planned = plan(closingIn: 5, dueIn: 15)
        let closed = planned.first { $0.kind == .closed }
        let due = planned.first { $0.kind == .paymentDue }

        XCTAssertEqual(
            closed?.fireDate, StatementNotificationPlan.fireDate(on: day(5), calendar: calendar))
        XCTAssertEqual(
            due?.fireDate, StatementNotificationPlan.fireDate(on: day(15), calendar: calendar))
    }

    func testAStatementThatHasAlreadyClosedOnlyStillOwesThePaymentReminder() {
        let planned = plan(closingIn: -2, dueIn: 8)

        XCTAssertEqual(planned.map(\.kind), [.paymentDue])
    }

    // MARK: - What is deliberately silent

    func testAPaidStatementSaysNothing() {
        XCTAssertTrue(
            plan(isPaid: true).isEmpty,
            "A settled invoice must not remind anyone of money they no longer owe")
    }

    /// `StatementPaymentService` recalculates the total before it flags the invoice, so the row sits
    /// unpaid at zero for a moment. A reminder scheduled in that window used to read
    /// "your statement of R$ 0,00 is due today".
    func testAStatementWithNothingLeftToPaySaysNothingEvenBeforeItIsFlagged() {
        XCTAssertTrue(plan(total: 0, isPaid: false).isEmpty)
    }

    func testAStatementPastItsDueDateIsNotReAnnounced() {
        XCTAssertTrue(plan(closingIn: -40, dueIn: -3).isEmpty)
    }

    func testAStatementBeyondTheHorizonWaitsItsTurn() {
        XCTAssertTrue(
            plan(closingIn: 40, dueIn: 50).isEmpty,
            "iOS caps pending requests; the monthly reschedule brings these in as they come into range")
    }

    func testOnlyTheDueDateIsPlannedWhenClosingIsInRangeButTheDueDateIsNot() {
        let planned = plan(closingIn: 2, dueIn: 45)

        XCTAssertEqual(planned.map(\.kind), [.closed])
    }

    // MARK: - Sweeping

    func testTheSweepRecognisesEveryStatementIdentifierIncludingTheRetiredOne() {
        XCTAssertTrue(StatementNotificationPlan.isStatementIdentifier("statement_closed_7"))
        XCTAssertTrue(StatementNotificationPlan.isStatementIdentifier("statement_pay_7"))
        XCTAssertTrue(
            StatementNotificationPlan.isStatementIdentifier("statement_due_7"),
            "The old due-soon reminder must still be swept, or an updating app keeps firing it")
        XCTAssertFalse(StatementNotificationPlan.isStatementIdentifier("transaction_7"))
    }
}
