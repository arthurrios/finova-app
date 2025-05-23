//
//  TransactionRepository.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

final class TransactionRepository: TransactionRepositoryProtocol {
    private let db = DBHelper.shared

    func fetchTransactions() -> [Transaction] {
        (try? db.getTransactions()) ?? []
    }
    
    func insertTransaction(_ transaction: TransactionModel) throws {
        try? db.insertTransaction(transaction)
    }
}
