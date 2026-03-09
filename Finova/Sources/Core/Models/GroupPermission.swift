//
//  GroupPermission.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import Foundation

struct GroupPermissions: Equatable, Encodable {
    var canCreateTransactions: Bool
    var canEditTransactions: Bool
    var canDeleteTransactions: Bool
    var canEditBudgets: Bool
    var canEditAllocations: Bool
    var canViewCreditCards: Bool
    var canManageCreditCards: Bool
    var canInviteMembers: Bool
    var canEditOwnTransactions: Bool
    var canDeleteOwnTransactions: Bool
    var canEditOwnBudgets: Bool
    var canEditOwnAllocations: Bool

    static let memberDefault = GroupPermissions(
        canCreateTransactions: true,
        canEditTransactions: false,
        canDeleteTransactions: false,
        canEditBudgets: false,
        canEditAllocations: false,
        canViewCreditCards: false,
        canManageCreditCards: false,
        canInviteMembers: false,
        canEditOwnTransactions: true,
        canDeleteOwnTransactions: true,
        canEditOwnBudgets: true,
        canEditOwnAllocations: true
    )

    static let viewOnly = GroupPermissions(
        canCreateTransactions: false,
        canEditTransactions: false,
        canDeleteTransactions: false,
        canEditBudgets: false,
        canEditAllocations: false,
        canViewCreditCards: false,
        canManageCreditCards: false,
        canInviteMembers: false,
        canEditOwnTransactions: false,
        canDeleteOwnTransactions: false,
        canEditOwnBudgets: false,
        canEditOwnAllocations: false
    )

    static let canAdd = GroupPermissions(
        canCreateTransactions: true,
        canEditTransactions: false,
        canDeleteTransactions: false,
        canEditBudgets: false,
        canEditAllocations: false,
        canViewCreditCards: true,
        canManageCreditCards: false,
        canInviteMembers: false,
        canEditOwnTransactions: true,
        canDeleteOwnTransactions: true,
        canEditOwnBudgets: true,
        canEditOwnAllocations: true
    )

    static let fullAccess = GroupPermissions(
        canCreateTransactions: true,
        canEditTransactions: true,
        canDeleteTransactions: true,
        canEditBudgets: true,
        canEditAllocations: true,
        canViewCreditCards: true,
        canManageCreditCards: true,
        canInviteMembers: true,
        canEditOwnTransactions: true,
        canDeleteOwnTransactions: true,
        canEditOwnBudgets: true,
        canEditOwnAllocations: true
    )

    var asJSON: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    static func fromJSON(_ json: String) -> GroupPermissions {
        guard let data = json.data(using: .utf8),
              let permissions = try? JSONDecoder().decode(GroupPermissions.self, from: data)
        else { return .memberDefault }
        return permissions
    }

    var allPermissions: [(key: String, label: String, isEnabled: Bool)] {
        return [
            ("canCreateTransactions", "permission.createTransactions".localized, canCreateTransactions),
            ("canEditOwnTransactions", "permission.editOwnTransactions".localized, canEditOwnTransactions),
            ("canDeleteOwnTransactions", "permission.deleteOwnTransactions".localized, canDeleteOwnTransactions),
            ("canEditTransactions", "permission.editTransactions".localized, canEditTransactions),
            ("canDeleteTransactions", "permission.deleteTransactions".localized, canDeleteTransactions),
            ("canEditOwnBudgets", "permission.editOwnBudgets".localized, canEditOwnBudgets),
            ("canEditOwnAllocations", "permission.editOwnAllocations".localized, canEditOwnAllocations),
            ("canEditBudgets", "permission.editBudgets".localized, canEditBudgets),
            ("canEditAllocations", "permission.editAllocations".localized, canEditAllocations),
            ("canViewCreditCards", "permission.viewCreditCards".localized, canViewCreditCards),
            ("canManageCreditCards", "permission.manageCreditCards".localized, canManageCreditCards),
            ("canInviteMembers", "permission.inviteMembers".localized, canInviteMembers),
        ]
    }

    mutating func setPermission(key: String, value: Bool) {
        switch key {
        case "canCreateTransactions": canCreateTransactions = value
        case "canEditTransactions": canEditTransactions = value
        case "canDeleteTransactions": canDeleteTransactions = value
        case "canEditBudgets": canEditBudgets = value
        case "canEditAllocations": canEditAllocations = value
        case "canViewCreditCards": canViewCreditCards = value
        case "canManageCreditCards": canManageCreditCards = value
        case "canInviteMembers": canInviteMembers = value
        case "canEditOwnTransactions": canEditOwnTransactions = value
        case "canDeleteOwnTransactions": canDeleteOwnTransactions = value
        case "canEditOwnBudgets": canEditOwnBudgets = value
        case "canEditOwnAllocations": canEditOwnAllocations = value
        default: break
        }
    }
}

// MARK: - Backward-compatible Codable

extension GroupPermissions: Decodable {
    enum CodingKeys: String, CodingKey {
        case canCreateTransactions, canEditTransactions, canDeleteTransactions
        case canEditBudgets, canEditAllocations
        case canViewCreditCards, canManageCreditCards, canInviteMembers
        case canEditOwnTransactions, canDeleteOwnTransactions
        case canEditOwnBudgets, canEditOwnAllocations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canCreateTransactions = try container.decode(Bool.self, forKey: .canCreateTransactions)
        canEditTransactions = try container.decode(Bool.self, forKey: .canEditTransactions)
        canDeleteTransactions = try container.decode(Bool.self, forKey: .canDeleteTransactions)
        canEditBudgets = try container.decode(Bool.self, forKey: .canEditBudgets)
        canEditAllocations = try container.decode(Bool.self, forKey: .canEditAllocations)
        canViewCreditCards = try container.decode(Bool.self, forKey: .canViewCreditCards)
        canManageCreditCards = try container.decode(Bool.self, forKey: .canManageCreditCards)
        canInviteMembers = try container.decode(Bool.self, forKey: .canInviteMembers)
        // New keys default to true for backward compatibility with old JSON
        canEditOwnTransactions = try container.decodeIfPresent(Bool.self, forKey: .canEditOwnTransactions) ?? true
        canDeleteOwnTransactions = try container.decodeIfPresent(Bool.self, forKey: .canDeleteOwnTransactions) ?? true
        canEditOwnBudgets = try container.decodeIfPresent(Bool.self, forKey: .canEditOwnBudgets) ?? true
        canEditOwnAllocations = try container.decodeIfPresent(Bool.self, forKey: .canEditOwnAllocations) ?? true
    }
}
