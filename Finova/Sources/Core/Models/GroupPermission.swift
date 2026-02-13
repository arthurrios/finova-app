//
//  GroupPermission.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import Foundation

struct GroupPermissions: Codable, Equatable {
    var canCreateTransactions: Bool
    var canEditTransactions: Bool
    var canDeleteTransactions: Bool
    var canEditBudgets: Bool
    var canEditAllocations: Bool
    var canViewCreditCards: Bool
    var canManageCreditCards: Bool
    var canInviteMembers: Bool

    static let memberDefault = GroupPermissions(
        canCreateTransactions: true,
        canEditTransactions: false,
        canDeleteTransactions: false,
        canEditBudgets: false,
        canEditAllocations: false,
        canViewCreditCards: false,
        canManageCreditCards: false,
        canInviteMembers: false
    )

    static let viewOnly = GroupPermissions(
        canCreateTransactions: false,
        canEditTransactions: false,
        canDeleteTransactions: false,
        canEditBudgets: false,
        canEditAllocations: false,
        canViewCreditCards: false,
        canManageCreditCards: false,
        canInviteMembers: false
    )

    static let canAdd = GroupPermissions(
        canCreateTransactions: true,
        canEditTransactions: false,
        canDeleteTransactions: false,
        canEditBudgets: false,
        canEditAllocations: false,
        canViewCreditCards: true,
        canManageCreditCards: false,
        canInviteMembers: false
    )

    static let fullAccess = GroupPermissions(
        canCreateTransactions: true,
        canEditTransactions: true,
        canDeleteTransactions: true,
        canEditBudgets: true,
        canEditAllocations: true,
        canViewCreditCards: true,
        canManageCreditCards: true,
        canInviteMembers: true
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
            ("canEditTransactions", "permission.editTransactions".localized, canEditTransactions),
            ("canDeleteTransactions", "permission.deleteTransactions".localized, canDeleteTransactions),
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
        default: break
        }
    }
}
