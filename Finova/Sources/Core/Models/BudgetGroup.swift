//
//  BudgetGroup.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import Foundation

struct BudgetGroup: Codable, Equatable {
    let id: String
    var name: String
    var ownerId: String
    var ownerName: String
    var ownerEmail: String
    var currency: String       // ISO 4217 code — enforced group-wide
    var ckRecordId: String?
    var ckShareUrl: String?
    var ckZoneOwner: String?
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    var members: [GroupMember] = []
    var sharedCards: [CreditCard] = [] // Cards shared with this group

    static func == (lhs: BudgetGroup, rhs: BudgetGroup) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.ownerId == rhs.ownerId &&
        lhs.currency == rhs.currency &&
        lhs.ckRecordId == rhs.ckRecordId &&
        lhs.ckZoneOwner == rhs.ckZoneOwner &&
        lhs.isDeleted == rhs.isDeleted
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        ownerId: String,
        ownerName: String,
        ownerEmail: String,
        currency: String = "BRL",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.ownerName = ownerName
        self.ownerEmail = ownerEmail
        self.currency = currency
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }

    var isOwner: Bool {
        guard let currentUser = AuthenticationManager.shared.currentUser else { return false }
        // Also match by email to handle the case where ownerId was stored as email
        // (placeholder from invitation acceptance, corrected by sync)
        return ownerId == currentUser.uid || ownerId == currentUser.email
    }
}
