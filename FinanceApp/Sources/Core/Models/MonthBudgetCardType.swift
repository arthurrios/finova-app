//
//  MonthBugetCard.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

struct MonthBudgetCardType: Codable {
  let date: Date
  let month: String
  let usedValue: Int
  var budgetLimit: Int?
  var availableValue: Int?
}
