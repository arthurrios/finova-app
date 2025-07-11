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
