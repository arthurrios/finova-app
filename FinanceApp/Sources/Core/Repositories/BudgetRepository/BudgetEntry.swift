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
    let date: Date
    let budget: Int
}
