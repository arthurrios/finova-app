//
//  BudgetRepositoryProtocol.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

protocol BudgetRepositoryProtocol {
    func fetchBudgets() -> [BudgetEntry]
}
