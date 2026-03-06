//
//  GroupMember.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import Foundation

enum GroupRole: String, Codable {
    case owner
    case member
}

struct GroupMember: Codable, Equatable {
    let id: String
    let groupId: String
    var userId: String
    var name: String
    var email: String
    var role: GroupRole
    var permissions: GroupPermissions
    var lastActive: Date?
    let joinedAt: Date
    var isRemoved: Bool

    init(
        id: String = UUID().uuidString,
        groupId: String,
        userId: String,
        name: String,
        email: String,
        role: GroupRole = .member,
        permissions: GroupPermissions = .memberDefault,
        lastActive: Date? = nil,
        joinedAt: Date = Date(),
        isRemoved: Bool = false
    ) {
        self.id = id
        self.groupId = groupId
        self.userId = userId
        self.name = name
        self.email = email
        self.role = role
        self.permissions = permissions
        self.lastActive = lastActive
        self.joinedAt = joinedAt
        self.isRemoved = isRemoved
    }

    var lastActiveDescription: String {
        guard let lastActive = lastActive else {
            return "sharing.member.neverActive".localized
        }
        let interval = Date().timeIntervalSince(lastActive)
        if interval < 60 {
            return "sharing.member.activeNow".localized
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return String(format: "sharing.member.activeMinutesAgo".localized, minutes)
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return String(format: "sharing.member.activeHoursAgo".localized, hours)
        } else {
            let days = Int(interval / 86400)
            return String(format: "sharing.member.activeDaysAgo".localized, days)
        }
    }
}
