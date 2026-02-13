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
    let ownerId: String
    let ownerName: String
    let ownerEmail: String
    var currency: String       // ISO 4217 code — enforced group-wide
    var ckRecordId: String?
    var ckShareUrl: String?
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
        return ownerId == currentUser.uid
    }
}
