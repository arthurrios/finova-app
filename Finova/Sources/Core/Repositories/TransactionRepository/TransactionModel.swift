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
    // First check if this is a recurring transaction (parent or instance)
    if isRecurring == true {
      return .recurring
    }

    // Check if this is an installment transaction (parent)
    if hasInstallments == true {
      return .installments
    }

    // Check if this is an installment instance
    if parentTransactionId != nil && installmentNumber != nil && totalInstallments != nil {
      return .installments
    }

    // Check if this is a recurring instance (has parent but no installment fields)
    if parentTransactionId != nil && installmentNumber == nil && totalInstallments == nil {
      return .recurring
    }

    return .normal
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

  // Custom Codable implementation to serialize/deserialize correctly
  enum CodingKeys: String, CodingKey {
    case id, title, amount, dateTimestamp, budgetMonthDate
    case isRecurring, hasInstallments, parentTransactionId
    case installmentNumber, totalInstallments, originalAmount
    case category, type
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    let id = try container.decodeIfPresent(Int.self, forKey: .id)
    let title = try container.decode(String.self, forKey: .title)
    let amount = try container.decode(Int.self, forKey: .amount)
    let dateTimestamp = try container.decode(Int.self, forKey: .dateTimestamp)
    let budgetMonthDate = try container.decode(Int.self, forKey: .budgetMonthDate)
    let isRecurring = try container.decodeIfPresent(Bool.self, forKey: .isRecurring)
    let hasInstallments = try container.decodeIfPresent(Bool.self, forKey: .hasInstallments)
    let parentTransactionId = try container.decodeIfPresent(Int.self, forKey: .parentTransactionId)
    let installmentNumber = try container.decodeIfPresent(Int.self, forKey: .installmentNumber)
    let totalInstallments = try container.decodeIfPresent(Int.self, forKey: .totalInstallments)
    let originalAmount = try container.decodeIfPresent(Int.self, forKey: .originalAmount)

    // Decode category and type as strings, then convert to enums
    let categoryString = try container.decode(String.self, forKey: .category)
    let typeString = try container.decode(String.self, forKey: .type)

    // Debug: Log the decoded values
    guard let category = TransactionCategory.allCases.first(where: { $0.key == categoryString })
    else {
      logError("Failed to find category for key: '\(categoryString)'")
      throw TransactionError.invalidCategory
    }

    guard let type = TransactionType.allCases.first(where: { String(describing: $0) == typeString })
    else {
      logError("Failed to find type for key: '\(typeString)'")
      throw TransactionError.invalidType
    }

    let uiData = UITransactionData(
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

    self.data = uiData
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encodeIfPresent(data.id, forKey: .id)
    try container.encode(data.title, forKey: .title)
    try container.encode(data.amount, forKey: .amount)
    try container.encode(data.dateTimestamp, forKey: .dateTimestamp)
    try container.encode(data.budgetMonthDate, forKey: .budgetMonthDate)
    try container.encodeIfPresent(data.isRecurring, forKey: .isRecurring)
    try container.encodeIfPresent(data.hasInstallments, forKey: .hasInstallments)
    try container.encodeIfPresent(data.parentTransactionId, forKey: .parentTransactionId)
    try container.encodeIfPresent(data.installmentNumber, forKey: .installmentNumber)
    try container.encodeIfPresent(data.totalInstallments, forKey: .totalInstallments)
    try container.encodeIfPresent(data.originalAmount, forKey: .originalAmount)

    // Encode category and type as strings
    try container.encode(data.category.key, forKey: .category)
    try container.encode(String(describing: data.type), forKey: .type)
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

    // Handle empty or nil categories by defaulting to miscellaneous
    let categoryKey = db.category.isEmpty ? "miscellaneous" : db.category

    cat = TransactionCategory.allCases.first(where: { $0.key == categoryKey })

    if cat == nil {
      cat = TransactionCategory.allCases.first(where: { $0.rawValue == categoryKey })
    }

    if cat == nil {
      cat = TransactionCategory.allCases.first(where: {
        $0.key.lowercased() == categoryKey.lowercased()
      })
    }

    if cat == nil {
      let cleanCategory = categoryKey.replacingOccurrences(of: "category.", with: "")
      cat = TransactionCategory.allCases.first(where: {
        $0.key.lowercased() == cleanCategory.lowercased()
      })
    }

    let finalCategory: TransactionCategory
    if let category = cat {
      finalCategory = category
    } else {
      logWarning("Failed to find category for key: '\(db.category)', using fallback: miscellaneous")
      finalCategory = .miscellaneous
    }

    let finalType: TransactionType
    if let ty = TransactionType.allCases.first(where: { String(describing: $0) == db.type }) {
      finalType = ty
    } else {
      logWarning("Failed to find transaction type for key: '\(db.type)', using fallback: expense")
      finalType = .expense
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
      type: finalType
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

  var displayName: String {
    return self.rawValue.localized
  }
}
