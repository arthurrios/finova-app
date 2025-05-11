//
//  MonthBugetCard.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

struct MonthBudgetCardType: Codable {
    let month: String
    let usedValue: Int
    var budgetLimit: Int? = nil
    var availableValue: Int? = nil
}
