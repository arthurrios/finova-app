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
    private var pollTimer: Timer?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        startPolling()
    }

    @objc private func appDidEnterBackground() {
        stopPolling()
    }

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.performFetch(completion: {})
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

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

    func handleIncomingActivity(_ record: CKRecord) {
        let recordName = record.recordID.recordName

        // Skip if already processed (deduplication for fetchAndNotifyRecentActivities)
        guard !isAlreadyProcessed(recordName) else {
            logWarning("GroupNotificationManager: SKIPPED (already processed) record=\(recordName)")
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

        let request = UNNotificationRequest(
            identifier: recordName,
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

    /// Directly fetches recent GroupActivity records from all group zones.
    /// For member groups: queries the shared database (bypasses unreliable CKQuerySubscription).
    /// For owned groups: queries the private database (catches member-written activities).
    /// Also ensures periodic polling is active to catch records still propagating.
    func fetchAndNotifyRecentActivities(completion: @escaping () -> Void) {
        performFetch(completion: completion)
        // Ensure polling is active (covers first-launch case where
        // didBecomeActiveNotification fires before shared singleton is initialized)
        if pollTimer == nil {
            startPolling()
        }
    }

    private func performFetch(completion: @escaping () -> Void) {
        let repo = BudgetGroupRepository()
        let allGroups = repo.fetchAllGroups().filter { !$0.isDeleted }

        guard !allGroups.isEmpty else {
            logWarning("GroupNotificationManager: performFetch — no groups, skipping")
            completion()
            return
        }

        logWarning("GroupNotificationManager: performFetch — checking \(allGroups.count) group(s)")

        let dispatchGroup = DispatchGroup()
        let cutoff = Date().addingTimeInterval(-300) // last 5 minutes
        let predicate = NSPredicate(format: "timestamp > %@", cutoff as NSDate)

        for group in allGroups {
            let zoneID: CKRecordZone.ID
            let database: CKDatabase

            if group.isOwner {
                zoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: CKCurrentUserDefaultName)
                database = CloudKitManager.shared.privateDatabase
                logWarning("GroupNotificationManager: querying OWNED group '\(group.name)' in privateDB zone=Group-\(group.id)")
            } else if let zoneOwner = group.ckZoneOwner {
                zoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: zoneOwner)
                database = CloudKitManager.shared.sharedDatabase
                logWarning("GroupNotificationManager: querying MEMBER group '\(group.name)' in sharedDB zone=Group-\(group.id) owner=\(zoneOwner)")
            } else {
                let currentUID = AuthenticationManager.shared.currentUser?.uid ?? "nil"
                logWarning("GroupNotificationManager: SKIPPING group '\(group.name)' — ckZoneOwner is nil, isOwner=\(group.isOwner), ownerId=\(group.ownerId), currentUID=\(currentUID)")
                continue
            }

            dispatchGroup.enter()

            let query = CKQuery(recordType: "GroupActivity", predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

            let operation = CKQueryOperation(query: query)
            operation.zoneID = zoneID
            let groupName = group.name
            operation.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record):
                    let action = record["action"] as? String ?? "unknown"
                    logWarning("GroupNotificationManager: RECORD FOUND in '\(groupName)' — action=\(action) record=\(record.recordID.recordName)")
                    self.handleIncomingActivity(record)
                case .failure(let error):
                    logWarning("GroupNotificationManager: record match error in '\(groupName)': \(error.localizedDescription)")
                }
            }
            operation.queryResultBlock = { result in
                if case .failure(let error) = result {
                    logWarning("GroupNotificationManager: query FAILED for '\(groupName)': \(error.localizedDescription)")
                }
                dispatchGroup.leave()
            }
            operation.qualityOfService = .userInitiated
            database.add(operation)
        }

        dispatchGroup.notify(queue: .main) {
            completion()
        }
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
        default:
            return detail
        }
    }
}
