//
//  BudgetModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

struct BudgetEntry {
    let monthKey: String
    let budget: Int
}

struct BudgetModel {
    let monthDate: Int
    let amount: Int
}

struct DisplayBudgetModel {
    let date: Date
    let amount: Int
}
