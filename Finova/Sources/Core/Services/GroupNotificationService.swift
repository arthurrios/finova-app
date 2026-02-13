//
//  GroupNotificationService.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit
import Foundation

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
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let zoneID = CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: "activity-\(UUID().uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: "GroupActivity", recordID: recordID)

        guard let user = AuthenticationManager.shared.currentUser else { return }

        record["action"] = action.rawValue as CKRecordValue
        record["actorName"] = (user.displayName ?? "User") as CKRecordValue
        record["actorId"] = user.uid as CKRecordValue
        record["detail"] = detail as CKRecordValue
        record["timestamp"] = Date() as CKRecordValue

        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                completion?(.success(()))
            case .failure(let error):
                completion?(.failure(error))
            }
        }
        operation.qualityOfService = .utility
        CloudKitManager.shared.privateDatabase.add(operation)
    }
}
