//
//  TransactionTestFixtures.swift
//  FinovaTests
//
//  The transaction factory many suites share. It used to live in the CloudKit sync test helpers,
//  which this build no longer has.
//

import Foundation

@testable import Finova

enum TransactionTestFixtures {

    static func makeTransactionModel(
        title: String = "Test Transaction",
        category: String = "market",
        amount: Int = 5000,
        type: String = "expense",
        dateTimestamp: Int? = nil,
        budgetMonthDate: Int? = nil,
        isRecurring: Bool? = nil,
        hasInstallments: Bool? = nil,
        parentTransactionId: Int? = nil,
        installmentNumber: Int? = nil,
        totalInstallments: Int? = nil,
        originalAmount: Int? = nil,
        creditCardId: Int? = nil,
        statementId: Int? = nil,
        isCreditCardStatement: Bool? = nil
    ) -> TransactionModel {
        let now = Date()
        let ts = dateTimestamp ?? Int(now.timeIntervalSince1970)
        let bmd = budgetMonthDate ?? now.monthAnchor

        return TransactionModel(
            title: title,
            category: category,
            amount: amount,
            type: type,
            dateTimestamp: ts,
            budgetMonthDate: bmd,
            isRecurring: isRecurring,
            hasInstallments: hasInstallments,
            parentTransactionId: parentTransactionId,
            originalAmount: originalAmount,
            installmentNumber: installmentNumber,
            totalInstallments: totalInstallments,
            creditCardId: creditCardId,
            statementId: statementId,
            isCreditCardStatement: isCreditCardStatement
        )
    }
}
