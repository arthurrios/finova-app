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
        let repository = BudgetGroupRepository()
        let group = repository.fetchGroup(byId: groupId)

        let zoneOwnerName: String
        let database: CKDatabase

        if let group = group, group.isOwner {
            zoneOwnerName = CKCurrentUserDefaultName
            database = CloudKitManager.shared.privateDatabase
        } else if let group = group, let storedOwner = group.ckZoneOwner {
            zoneOwnerName = storedOwner
            database = CloudKitManager.shared.sharedDatabase
        } else {
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
        database.add(operation)
    }
}
