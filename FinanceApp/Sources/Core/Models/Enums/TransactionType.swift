//
//  TransactionType.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/05/25.
//

import Foundation

enum TransactionType: String, CaseIterable {
    case income = "Income"
    case expense = "Expense"
    
    var key: String {
        String(describing: self)
    }
}
