//
//  TransactionRepository.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

final class TransactionRepository: TransactionRepositoryProtocol {
    
    func fetchTransactions() -> [Transaction] {
        return [
            Transaction(title: "Groceries", category: .groceries, amount: 1200_00, type: .outcome, date: DateFormatter.yyyyMMdd.date(from: "2025-03-15")!),
            Transaction(title: "Salary", category: .salary, amount: 3000_00, type: .income, date: DateFormatter.yyyyMMdd.date(from: "2025-03-01")!),
            Transaction(title: "Rent", category: .rent, amount: 1500_00, type: .outcome, date: DateFormatter.yyyyMMdd.date(from: "2025-05-05")!),
            Transaction(title: "Utilities", category: .utilities, amount: 94302_00, type: .outcome, date: DateFormatter.yyyyMMdd.date(from: "2025-05-10")!)
        ]
    }
}
