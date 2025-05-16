//
//  Transaction.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

struct Transaction {
    let title: String
    let category: TransactionCategory
    let amount: Int
    let type: TransactionType
    let date: Date
}

enum TransactionType: String {
    case income
    case outcome
}

enum TransactionCategory: String, CaseIterable {
    case market = "Market"
    case meals = "Meals"
    case gifts = "Gifts"
    case billing = "Billing"
    case salary = "Salary"
    case utilities = "Utilities"
    case entertainment = "Entertainment"
    case transportation = "Transportation"
    case healthcare = "Healthcare"
    case subscriptions = "Subscriptions"
    case education = "Education"
    case travel = "Travel"
    case groceries = "Groceries"
    case insurance = "Insurance"
    case savings = "Savings"
    case investments = "Investments"
    case taxes = "Taxes"
    case loans = "Loans"
    case donations = "Donations"
    case miscellaneous = "Miscellaneous"
    case clothing = "Clothing"
    case personalCare = "Personal Care"
    case homeMaintenance = "Home Maintenance"
    case communication = "Communication"
    case fitness = "Fitness"
    
    var iconName: String {
        let caseName = String(describing: self)
        return "icon" + caseName.prefix(1).uppercased() + caseName.dropFirst()
    }
    
    static var allValues: [String] {
        return allCases.map { String(describing: $0) }
    }
}
