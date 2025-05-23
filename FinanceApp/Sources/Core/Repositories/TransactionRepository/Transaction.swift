//
//  Transaction.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation
import UIKit

struct Transaction {
    let title: String
    let category: TransactionCategory
    let amount: Int
    let type: TransactionType
    let date: Date
}

enum TransactionCategory: String, CaseIterable {
    case market = "category.market"
    case meals = "category.meals"
    case gifts = "category.gifts"
    case salary = "category.salary"
    case utilities = "category.utilities"
    case entertainment = "category.entertainment"
    case transportation = "category.transportation"
    case healthcare = "category.healthcare"
    case subscriptions = "category.subscriptions"
    case education = "category.education"
    case travel = "category.travel"
    case groceries = "category.groceries"
    case insurance = "category.insurance"
    case savings = "category.savings"
    case investments = "category.investments"
    case taxes = "category.taxes"
    case loans = "category.loans"
    case donations = "category.donations"
    case miscellaneous = "category.miscellaneous"
    case clothing = "category.clothing"
    case personalCare = "category.personalCare"
    case homeMaintenance = "category.homeMaintenance"
    case communication = "category.communication"
    case fitness = "category.fitness"
    case debit = "category.debit"
    case credit = "category.credit"
    case bankSlip = "category.bankSlip"

    var iconName: String {
        let caseName = String(describing: self)
        let generatedIconName = "icon" + caseName.prefix(1).uppercased() + caseName.dropFirst()
        
        if UIImage(named: generatedIconName) != nil {
            return generatedIconName
        } else {
            return "iconDollar"
        }
    }

    var description: String {
        return self.rawValue.localized
    }
    
    static var allValues: [String] {
        return allCases.map { String(describing: $0) }
    }
}
