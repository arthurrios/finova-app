//
//  TransactionRepresentable.swift
//  FinanceApp
//
//  Created by Arthur Rios on 06/06/25.
//

import Foundation

struct TransactionData<C, T>: Codable where C: Codable, T: Codable {
    let id: Int?
    let title: String
    let amount: Int
    let dateTimestamp: Int
    let budgetMonthDate: Int
    let isRecurring: Bool?
    let hasInstallments: Bool?
    let parentTransactionId: Int?
    let installmentNumber: Int?
    let totalInstallments: Int?
    let originalAmount: Int?
    
    var creditCardId: Int? = nil
    var statementId: Int? = nil
    var isCreditCardStatement: Bool? = nil
    var updatedAt: Date? = nil
    var createdByUid: String? = nil

    /// What to do when this transaction's date lands on a weekend or holiday. Carried on the row, not
    /// read from a setting, so a series keeps the rule it was created with.
    var businessDayRule: BusinessDayRule = .exact
    /// The occurrence date before `businessDayRule` moved it. `nil` on every row written before the
    /// column existed, and read as `dateTimestamp` in that case.
    ///
    /// Regeneration always re-derives from this, never from `dateTimestamp`: deriving from an already
    /// shifted date would let a series walk a few days further every time a month was materialised.
    var unadjustedDateTimestamp: Int? = nil
    /// Which occurrence of its series this row is: the month anchor it was SCHEDULED for.
    ///
    /// Separate from `budgetMonthDate`, which is the month it actually counts in. They differ only
    /// when a business-day rule pushed the date across a month boundary. `nil` on rows written before
    /// the column existed, and read as `budgetMonthDate` in that case.
    var seriesPeriod: Int? = nil

    let category: C
    let type: T
}

enum TransactionError: Error, Equatable {
    case invalidDateFormat
    case invalidCategory
    case invalidType
    case invalidInstallmentCount
    case databaseError
    case transactionNotFound
    case notARecurringTransaction
    case parentTransactionNotFound
    case concurrentModificationError
    case repositoryUnavailable
}

enum TransactionMode: Int, CaseIterable, Codable {
    case normal = 0
    case recurring = 1
    case installments = 2
    
    var title: String {
        switch self {
        case .normal:
            return "transactionMode.normal.title".localized
        case .recurring:
            return "transactionMode.recurring.title".localized
        case .installments:
            return "transactionMode.installments.title".localized
        }
    }
}

enum TransactionComplexityType {
    case simple
    case recurringParent
    case recurringInstance
    case installmentParent
    case installmentInstance
}
