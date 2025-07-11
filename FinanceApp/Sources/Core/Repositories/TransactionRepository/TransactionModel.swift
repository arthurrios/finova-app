//
//  Transaction.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation
import UIKit

typealias UITransactionData = TransactionData<TransactionCategory, TransactionType>

struct Transaction: Codable {
    private let data: UITransactionData
    
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(dateTimestamp))
    }
    
    var mode: TransactionMode {
        if isRecurring == true {
            return .recurring
        } else if hasInstallments == true {
            return .installments
        } else if parentTransactionId != nil && installmentNumber != nil && totalInstallments != nil {
            return .installments
        } else if parentTransactionId != nil && isRecurring != true && installmentNumber == nil {
            return .recurring
        } else {
            return .normal
        }
    }
    
    var id: Int? { data.id }
    var title: String { data.title }
    var amount: Int { data.amount }
    var dateTimestamp: Int { data.dateTimestamp }
    var budgetMonthDate: Int { data.budgetMonthDate }
    var isRecurring: Bool? { data.isRecurring }
    var hasInstallments: Bool? { data.hasInstallments }
    var parentTransactionId: Int? { data.parentTransactionId }
    var installmentNumber: Int? { data.installmentNumber }
    var totalInstallments: Int? { data.totalInstallments }
    var originalAmount: Int? { data.originalAmount }
    var category: TransactionCategory { data.category }
    var type: TransactionType { data.type }
    
    init(data: UITransactionData) {
        self.data = data
    }
}

typealias DBTransactionData = TransactionData<String, String>

struct TransactionModel {
    let data: DBTransactionData
    
    init(
        id: Int? = nil,
        title: String,
        category: String,
        amount: Int,
        type: String,
        dateTimestamp: Int,
        budgetMonthDate: Int,
        isRecurring: Bool? = nil,
        hasInstallments: Bool? = nil,
        parentTransactionId: Int? = nil,
        originalAmount: Int? = nil,
        installmentNumber: Int? = nil,
        totalInstallments: Int? = nil
    ) {
        self.data = DBTransactionData(
            id: id,
            title: title,
            amount: amount,
            dateTimestamp: dateTimestamp,
            budgetMonthDate: budgetMonthDate,
            isRecurring: isRecurring,
            hasInstallments: hasInstallments,
            parentTransactionId: parentTransactionId,
            installmentNumber: installmentNumber,
            totalInstallments: totalInstallments,
            originalAmount: originalAmount,
            category: category,
            type: type
        )
    }
}

extension UITransactionData {
    init(from db: DBTransactionData) throws {
        var cat: TransactionCategory?
        
        cat = TransactionCategory.allCases.first(where: { $0.key == db.category })
        
        if cat == nil {
            cat = TransactionCategory.allCases.first(where: { $0.rawValue == db.category })
        }
        
        if cat == nil {
            cat = TransactionCategory.allCases.first(where: {
                $0.key.lowercased() == db.category.lowercased()
            })
        }
        
        if cat == nil {
            let cleanCategory = db.category.replacingOccurrences(of: "category.", with: "")
            cat = TransactionCategory.allCases.first(where: {
                $0.key.lowercased() == cleanCategory.lowercased()
            })
        }
        
        guard let finalCategory = cat else {
            print("⚠️ Failed to find category for key: '\(db.category)'")
            print("⚠️ Available category keys: \(TransactionCategory.allCases.map { $0.key })")
            print("⚠️ Available category raw values: \(TransactionCategory.allCases.map { $0.rawValue })")
            throw TransactionError.invalidCategory
        }
        
        guard
            let ty = TransactionType.allCases
                .first(where: { String(describing: $0) == db.type })
        else {
            print("⚠️ Failed to find transaction type for key: '\(db.type)'")
            print("⚠️ Available type keys: \(TransactionType.allCases.map { String(describing: $0) })")
            throw TransactionError.invalidType
        }
        
        self = .init(
            id: db.id,
            title: db.title,
            amount: db.amount,
            dateTimestamp: db.dateTimestamp,
            budgetMonthDate: db.budgetMonthDate,
            isRecurring: db.isRecurring,
            hasInstallments: db.hasInstallments,
            parentTransactionId: db.parentTransactionId,
            installmentNumber: db.installmentNumber,
            totalInstallments: db.totalInstallments,
            originalAmount: db.originalAmount,
            category: finalCategory,
            type: ty
        )
    }
}

enum TransactionCategory: String, CaseIterable, Codable {
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
    case transfer = "category.transfer"
    case bankSlip = "category.bankSlip"
    
    //  case debit = "category.debit"
    //  case credit = "category.credit"
    
    var iconName: String {
        let caseName = String(describing: self)
        let generatedIconName =
        "lucide_" + "icon" + caseName.prefix(1).uppercased() + caseName.dropFirst()
        
        if UIImage(named: generatedIconName) != nil {
            return generatedIconName
        } else {
            return "lucide_" + "iconDollar"
        }
    }
    
    func iconName(for transactionType: TransactionType) -> String {
        if self == .transfer {
            let suffix = transactionType == .income ? "Down" : "Up"
            let transferIconName = "lucide_iconTransfer" + suffix
            
            if UIImage(named: transferIconName) != nil {
                return transferIconName
            } else {
                return "lucide_" + "iconDollar"
            }
        } else {
            return self.iconName
        }
    }
    
    var key: String {
        String(describing: self)
    }
    
    var description: String {
        return self.rawValue.localized
    }
    
    static var allValues: [String] {
        return allCases.map { String(describing: $0) }
    }
}
