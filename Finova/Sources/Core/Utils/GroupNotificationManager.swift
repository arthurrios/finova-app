//
//  GroupNotificationManager.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit
import Foundation
import UIKit
import UserNotifications

final class GroupNotificationManager {
    static let shared = GroupNotificationManager()

    private static let processedRecordNamesKey = "GroupNotification_ProcessedRecordNames"

    private init() {}

    // MARK: - Deduplication

    private func isAlreadyProcessed(_ recordName: String) -> Bool {
        let processed = UserDefaults.standard.stringArray(forKey: Self.processedRecordNamesKey) ?? []
        return processed.contains(recordName)
    }

    private func markAsProcessed(_ recordName: String) {
        var processed = UserDefaults.standard.stringArray(forKey: Self.processedRecordNamesKey) ?? []
        processed.append(recordName)
        // Keep only last 200 entries to prevent unbounded growth
        if processed.count > 200 {
            processed = Array(processed.suffix(200))
        }
        UserDefaults.standard.set(processed, forKey: Self.processedRecordNamesKey)
    }

    /// Builds a content-based deduplication key so the same logical notification
    /// is not shown twice (once from the public DB fetch, once from the zone sync).
    static func logicalDeduplicationKey(action: String, actorId: String, detail: String) -> String {
        return "logical-\(action)-\(actorId)-\(detail)"
    }

    func handleIncomingActivity(_ record: CKRecord) {
        let recordName = record.recordID.recordName

        // Skip if already processed (deduplication)
        guard !isAlreadyProcessed(recordName) else {
            return
        }
        markAsProcessed(recordName)

        guard let action = record["action"] as? String,
              let actorName = record["actorName"] as? String,
              let detail = record["detail"] as? String,
              let actorId = record["actorId"] as? String else {
            logWarning("GroupNotificationManager: SKIPPED (missing fields) record=\(recordName)")
            return
        }

        // Don't notify for own actions
        guard actorId != AuthenticationManager.shared.currentUser?.uid else {
            logWarning("GroupNotificationManager: SKIPPED (own action) record=\(recordName) action=\(action)")
            return
        }

        // Cross-mechanism dedup: skip if the public DB fetch already showed this
        let logicalKey = Self.logicalDeduplicationKey(action: action, actorId: actorId, detail: detail)
        guard !isAlreadyProcessed(logicalKey) else {
            logWarning("GroupNotificationManager: SKIPPED (already shown via public DB) record=\(recordName)")
            return
        }
        markAsProcessed(logicalKey)

        logWarning("GroupNotificationManager: DELIVERING notification — action=\(action) actor=\(actorName) detail=\(detail)")

        let content = UNMutableNotificationContent()
        content.title = actorName
        content.body = notificationBody(for: action, detail: detail)
        content.sound = .default
        content.categoryIdentifier = "GROUP_ACTIVITY"
        var userInfo: [String: Any] = ["action": action]
        if let targetRecordName = record["targetRecordName"] as? String {
            userInfo["targetRecordName"] = targetRecordName
        }
        content.userInfo = userInfo

        // Use logicalKey as identifier so iOS deduplicates across all paths
        let request = UNNotificationRequest(
            identifier: logicalKey,
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

    /// Triggers a sync to pick up any missed GroupActivity records.
    func fetchAndNotifyRecentActivities(completion: @escaping () -> Void) {
        SyncEngine.shared.performFullSync()
        completion()
    }

    func notificationBody(for action: String, detail: String) -> String {
        switch GroupNotificationService.GroupAction(rawValue: action) {
        case .transactionCreated:
            return String(format: "notification.group.transactionCreated".localized, detail)
        case .transactionEdited:
            return String(format: "notification.group.transactionEdited".localized, detail)
        case .transactionDeleted:
            return String(format: "notification.group.transactionDeleted".localized, detail)
        case .budgetEdited:
            return String(format: "notification.group.budgetEdited".localized, detail)
        case .allocationEdited:
            return String(format: "notification.group.allocationEdited".localized, detail)
        case .memberJoined:
            return String(format: "notification.group.memberJoined".localized, detail)
        case .memberLeft:
            return String(format: "notification.group.memberLeft".localized, detail)
        case .memberRemoved:
            return String(format: "notification.group.memberRemoved".localized, detail)
        case .permissionsChanged:
            return String(format: "notification.group.permissionsChanged".localized, detail)
        case .groupRenamed:
            return String(format: "notification.group.groupRenamed".localized, detail)
        default:
            return detail
        }
    }
}
