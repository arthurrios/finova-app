//
//  RowNormalizer.swift
//  Finova
//
//  The single place a parsed row becomes a `TransactionModel`.
//
//  This mapping IS the contract between the import engine and the rest of the app, and it is pinned
//  by `ImportNormalizationTests`. Four things in it are load-bearing:
//
//  * `amount` is a POSITIVE MAGNITUDE. Direction lives in `type`, and every reader in
//    `TransactionLedgerService` applies it as `type == .income ? +amount : -amount`. A negative
//    `amount` would be double-negated and silently corrupt every balance in the app.
//  * `category` is written as `.key` ("market"), the database spelling — not `.rawValue`
//    ("category.market"), which is the CloudKit spelling.
//  * `budgetMonthDate` comes from `Date.monthAnchor`, the existing helper. Its own documentation
//    warns that several call sites already mix a UTC calendar with this local-timezone anchor;
//    rolling another would add a third convention.
//  * Every recurring, installment and credit-card field is nil. `parentTransactionId` especially:
//    setting it to the row's own id is the self-referencing-parent convention, which flips
//    `Transaction.mode` to `.recurring` and hands the row to the series materializer, where it can
//    occupy a month slot belonging to a genuine series.
//

import Foundation

enum RowNormalizer {

    static func model(
        title: String,
        category: TransactionCategory,
        type: TransactionType,
        date: Date,
        cents: Int
    ) -> TransactionModel {
        TransactionModel(
            title: title,
            category: category.key,
            amount: abs(cents),
            type: type.key,
            dateTimestamp: Int(date.timeIntervalSince1970),
            budgetMonthDate: date.monthAnchor,
            isRecurring: nil,
            hasInstallments: nil,
            parentTransactionId: nil,
            originalAmount: nil,
            installmentNumber: nil,
            totalInstallments: nil,
            creditCardId: nil,
            statementId: nil,
            isCreditCardStatement: nil,
            updatedAt: nil,
            // An imported row is a fact that already happened. `BusinessDayAdjuster` exists to
            // SCHEDULE future occurrences, so it is never invoked here — a transaction that fell on
            // a Saturday keeps its Saturday.
            businessDayRule: .exact,
            // Both default from the row itself inside `DBHelper`, which is correct for anything that
            // never shifts.
            unadjustedDateTimestamp: nil,
            seriesPeriod: nil
        )
    }
}
