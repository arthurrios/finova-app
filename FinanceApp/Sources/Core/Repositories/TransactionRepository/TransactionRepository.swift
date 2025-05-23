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
            Transaction(title: "Market", category: .market, amount: 450_67, type: .expense, date: DateFormatter.yyyyMMdd.date(from: "2025-05-08")!),
            Transaction(title: "Birthday gift", category: .gifts, amount: 89_90, type: .expense, date: DateFormatter.yyyyMMdd.date(from: "2025-05-06")!),
            Transaction(title: "Energy bill", category: .bankSlip, amount: 243_72, type: .expense, date: DateFormatter.yyyyMMdd.date(from: "2025-05-05")!),
            Transaction(title: "Rent", category: .homeMaintenance, amount: 2240_00, type: .expense, date: DateFormatter.yyyyMMdd.date(from: "2025-05-05")!),
            Transaction(title: "Salary", category: .salary, amount: 5000_00, type: .income, date: DateFormatter.yyyyMMdd.date(from: "2025-05-05")!),
        ]
    }
}
