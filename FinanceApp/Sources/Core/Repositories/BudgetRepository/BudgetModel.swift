//
//  BudgetModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

struct BudgetEntry: Codable {
    let monthKey: String
    let budget: Int
}

struct BudgetModel: Codable {
    let monthDate: Int
    let amount: Int
}

struct DisplayBudgetModel: Codable {
    let date: Date
    let amount: Int
}
