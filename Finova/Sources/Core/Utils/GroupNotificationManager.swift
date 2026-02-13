//
//  GroupNotificationManager.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit
import Foundation
import UserNotifications

final class GroupNotificationManager {
    static let shared = GroupNotificationManager()

    private init() {}

    func handleIncomingActivity(_ record: CKRecord) {
        guard let action = record["action"] as? String,
              let actorName = record["actorName"] as? String,
              let detail = record["detail"] as? String,
              let actorId = record["actorId"] as? String else { return }

        // Don't notify for own actions
        guard actorId != AuthenticationManager.shared.currentUser?.uid else { return }

        let content = UNMutableNotificationContent()
        content.title = actorName
        content.body = notificationBody(for: action, detail: detail)
        content.sound = .default
        content.categoryIdentifier = "GROUP_ACTIVITY"

        let request = UNNotificationRequest(
            identifier: record.recordID.recordName,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)

        // Also post to in-app notification history
        NotificationCenter.default.post(name: .groupMemberActionOccurred, object: nil, userInfo: [
            "action": action,
            "actorName": actorName,
            "detail": detail
        ])
    }

    private func notificationBody(for action: String, detail: String) -> String {
        switch GroupNotificationService.GroupAction(rawValue: action) {
        case .transactionCreated:
            return String(format: "notification.group.transactionCreated".localized, detail)
        case .transactionEdited:
            return String(format: "notification.group.transactionEdited".localized, detail)
        case .transactionDeleted:
            return String(format: "notification.group.transactionDeleted".localized, detail)
        case .budgetEdited:
            return String(format: "notification.group.budgetEdited".localized, detail)
        case .memberJoined:
            return String(format: "notification.group.memberJoined".localized, detail)
        case .memberLeft:
            return String(format: "notification.group.memberLeft".localized, detail)
        default:
            return detail
        }
    }
}
