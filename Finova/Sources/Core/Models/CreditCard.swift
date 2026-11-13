//
//  CreditCard.swift
//  Finova
//
//  Created by Arthur Rios on 07/02/26.
//

import Foundation
import UIKit

struct CreditCard: Codable {
    var id: Int?
    var name: String
    var lastFourDigits: String
    var cardBrand: CardBrand
    var closingDay: Int
    var dueDay: Int
    var creditLimit: Int?
    var cardColor: CardColor
    var userId: String
    var isDeleted: Bool
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date
    var sharedGroupId: String?
    var createdByUid: String?
}

enum CardBrand: String, Codable, CaseIterable {
    case visa, mastercard, amex, elo, hipercard, other
    
    var displayName: String {
        "cardBrand.\(rawValue)".localized
    }
    
    var iconName: String {
        switch self {
        case .visa: return "cc_visa"
        case .mastercard: return "cc_mastercard"
        case .amex: return "cc_amex"
        case .elo: return "cc_elo"
        case .hipercard: return "cc_hipercard"
        case .other: return "cc_generic"
        }
    }
}

enum CardColor: String, Codable, CaseIterable {
    case black, purple, blue, green, gold, platinum, red, orange
    
    var startColor: UIColor {
        switch self {
        case .black: return .black
        case .purple: return UIColor(hex: "#8B5CF6")
        case .blue: return UIColor(hex: "#3B82F6")
        case .green: return UIColor(hex: "#10B981")
        case .gold: return UIColor(hex: "#F59E0B")
        case .platinum: return UIColor(hex: "#94A3B8")
        case .red: return UIColor(hex: "#EF4444")
        case .orange: return UIColor(hex: "#F97316")
        }
    }
    
    var endColor: UIColor {
        switch self {
        case .black: return .darkGray
        case .purple: return UIColor(hex: "#6D28D9")
        case .blue: return UIColor(hex: "#1D4ED8")
        case .green: return UIColor(hex: "#059669")
        case .gold: return UIColor(hex: "#D97706")
        case .platinum: return UIColor(hex: "#64748B")
        case .red: return UIColor(hex: "#DC2626")
        case .orange: return UIColor(hex: "#EA580C")
        }
    }
}
