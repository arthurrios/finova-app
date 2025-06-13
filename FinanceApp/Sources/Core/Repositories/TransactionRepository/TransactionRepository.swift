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
        let _ = try db.insertTransaction(transaction)
    }
    
    func delete(id: Int) throws {
        try db.deleteTransaction(id: id)
    }
}

extension TransactionRepository {
    func fetchRecurringTransactions() -> [Transaction] {
        return fetchTransactions().filter { $0.isRecurring == true }
    }
    
    func fetchTransactionInstancesForRecurring(_ recurringId: Int) -> [Transaction] {
        return fetchTransactions().filter { $0.parentTransactionId == recurringId }
    }
    
    func fetchAllRecurringInstances() -> [Transaction] {

        return fetchTransactions().filter { $0.parentTransactionId != nil }
    }
    
    func insertTransactionAndGetId(_ transaction: TransactionModel) throws -> Int {
        return try db.insertTransaction(transaction)
    }
    
    func updateParentTransactionId(transactionId: Int, parentId: Int) throws {
        try db.updateTransactionParentId(transactionId: transactionId, parentId: parentId)
    }
}
