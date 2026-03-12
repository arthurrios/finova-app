//
//  GroupNotificationService.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit
import Foundation
import UIKit

final class GroupNotificationService {
    static let shared = GroupNotificationService()

    enum GroupAction: String {
        case transactionCreated = "transaction_created"
        case transactionEdited = "transaction_edited"
        case transactionDeleted = "transaction_deleted"
        case budgetEdited = "budget_edited"
        case allocationEdited = "allocation_edited"
        case memberJoined = "member_joined"
        case memberLeft = "member_left"
        case memberRemoved = "member_removed"
        case permissionsChanged = "permissions_changed"
        case groupRenamed = "group_renamed"
    }

    func logActivity(
        action: GroupAction,
        groupId: String,
        detail: String,
        targetRecordName: String? = nil,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        // Use BudgetGroupService (not raw repository) to apply ownerId repair (email → UID)
        let allGroups = BudgetGroupService.shared.fetchAllGroups()
        let group = allGroups.first(where: { $0.id == groupId })

        let zoneOwnerName: String
        let database: CKDatabase

        let currentUID = AuthenticationManager.shared.currentUser?.uid ?? "nil"
        logWarning("GroupNotificationService: logActivity — groupId=\(groupId), ownerId=\(group?.ownerId ?? "nil"), isOwner=\(group?.isOwner ?? false), ckZoneOwner=\(group?.ckZoneOwner ?? "nil"), currentUID=\(currentUID)")

        if let group = group, group.isOwner {
            zoneOwnerName = CKCurrentUserDefaultName
            database = CloudKitManager.shared.privateDatabase
        } else if let group = group, let storedOwner = group.ckZoneOwner {
            zoneOwnerName = storedOwner
            database = CloudKitManager.shared.sharedDatabase
        } else {
            logWarning("GroupNotificationService: ⚠️ FALLBACK — writing to own privateDB because ckZoneOwner is nil! This record will NOT be visible to the group owner.")
            zoneOwnerName = CKCurrentUserDefaultName
            database = CloudKitManager.shared.privateDatabase
        }

        let zoneID = CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: zoneOwnerName)
        let recordID = CKRecord.ID(recordName: "activity-\(UUID().uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: "GroupActivity", recordID: recordID)

        guard let user = AuthenticationManager.shared.currentUser else { return }

        let actorName = UserDefaultsManager.getUser()?.name ?? user.displayName ?? "User"

        record["action"] = action.rawValue as CKRecordValue
        record["actorName"] = actorName as CKRecordValue
        record["actorId"] = user.uid as CKRecordValue
        record["detail"] = detail as CKRecordValue
        record["timestamp"] = Date() as CKRecordValue
        if let targetRecordName = targetRecordName {
            record["targetRecordName"] = targetRecordName as CKRecordValue
        }

        let dbName = (database === CloudKitManager.shared.privateDatabase) ? "privateDB" : "sharedDB"
        logWarning("GroupNotificationService: SAVING \(action.rawValue) to \(dbName) zone=Group-\(groupId) record=\(recordID.recordName)")

        // Request background time so both CK uploads complete even if
        // the user closes the app or the screen turns off.
        var bgTaskID = UIBackgroundTaskIdentifier.invalid
        let operationGroup = DispatchGroup()

        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "com.finova.groupActivityUpload") {
            logWarning("GroupNotificationService: background task expired")
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
        }

        // Zone record upload
        operationGroup.enter()
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                logWarning("GroupNotificationService: logActivity SUCCEEDED — \(action.rawValue) in group \(groupId)")
                completion?(.success(()))
            case .failure(let error):
                logError("GroupNotificationService: logActivity FAILED — \(action.rawValue) in group \(groupId): \(error.localizedDescription)")
                completion?(.failure(error))
            }
            operationGroup.leave()
        }
        operation.qualityOfService = .userInitiated
        database.add(operation)

        // Also write a lightweight notification record to the PUBLIC database.
        // CKQuerySubscriptions on private/shared DB don't reliably fire for
        // records written by shared zone participants, so the public DB record
        // is what triggers the visible push notification (same pattern as invitations).
        operationGroup.enter()
        writePublicActivityNotification(
            action: action,
            groupId: groupId,
            actorName: actorName,
            actorId: user.uid,
            detail: detail,
            targetRecordName: targetRecordName
        ) {
            operationGroup.leave()
        }

        // End background task when both uploads finish
        operationGroup.notify(queue: .global(qos: .utility)) {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
        }
    }

    private func writePublicActivityNotification(
        action: GroupAction,
        groupId: String,
        actorName: String,
        actorId: String,
        detail: String,
        targetRecordName: String?,
        completion: (() -> Void)? = nil
    ) {
        let recordID = CKRecord.ID(recordName: "activityNotif-\(UUID().uuidString)")
        let record = CKRecord(recordType: "GroupActivityNotification", recordID: recordID)

        record["action"] = action.rawValue as CKRecordValue
        record["groupId"] = groupId as CKRecordValue
        record["actorName"] = actorName as CKRecordValue
        record["actorId"] = actorId as CKRecordValue
        record["detail"] = detail as CKRecordValue
        record["timestamp"] = Date() as CKRecordValue
        if let targetRecordName = targetRecordName {
            record["targetRecordName"] = targetRecordName as CKRecordValue
        }

        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                logWarning("GroupNotificationService: public notification SAVED — \(action.rawValue) in group \(groupId)")
            case .failure(let error):
                logWarning("GroupNotificationService: public notification FAILED — \(error.localizedDescription)")
            }
            completion?()
        }
        operation.qualityOfService = .userInitiated
        CloudKitManager.shared.publicDatabase.add(operation)
    }
}
