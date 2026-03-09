//
//  CloudKitManager.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit
import UIKit

enum CloudKitAccountStatus {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
}

protocol CloudKitManagerDelegate: AnyObject {
    func cloudKitAccountStatusDidChange(_ status: CloudKitAccountStatus)
    func cloudKitDidReceiveRemoteNotification(for recordZoneIDs: [CKRecordZone.ID])
}

final class CloudKitManager {
    static let shared = CloudKitManager()

    let container: CKContainer
    let privateDatabase: CKDatabase
    let sharedDatabase: CKDatabase
    let publicDatabase: CKDatabase

    private(set) var accountStatus: CloudKitAccountStatus = .couldNotDetermine
    private(set) var isCloudKitAvailable: Bool = false

    weak var delegate: CloudKitManagerDelegate?

    static let privateZoneID = CKRecordZone.ID(
        zoneName: "FinovaPrivateZone",
        ownerName: CKCurrentUserDefaultName
    )

    private init() {
        container = CKContainer(identifier: "iCloud.com.arthurrios.Finova")
        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase
        publicDatabase = container.publicCloudDatabase
    }

    // MARK: - Account Status

    func checkAccountStatus(completion: @escaping (CloudKitAccountStatus) -> Void) {
        container.accountStatus { [weak self] status, error in
            guard let self = self else { return }

            if let error = error {
                logError("CloudKit account status error: \(error.localizedDescription)")
                self.accountStatus = .couldNotDetermine
                DispatchQueue.main.async { completion(.couldNotDetermine) }
                return
            }

            let mapped: CloudKitAccountStatus
            switch status {
            case .available:
                mapped = .available
                self.isCloudKitAvailable = true
            case .noAccount:
                mapped = .noAccount
                self.isCloudKitAvailable = false
            case .restricted:
                mapped = .restricted
                self.isCloudKitAvailable = false
            case .couldNotDetermine:
                mapped = .couldNotDetermine
                self.isCloudKitAvailable = false
            case .temporarilyUnavailable:
                mapped = .temporarilyUnavailable
                self.isCloudKitAvailable = false
            @unknown default:
                mapped = .couldNotDetermine
                self.isCloudKitAvailable = false
            }

            self.accountStatus = mapped
            DispatchQueue.main.async {
                self.delegate?.cloudKitAccountStatusDidChange(mapped)
                completion(mapped)
            }
        }
    }

    // MARK: - Zone Creation

    func createPrivateZoneIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        let zone = CKRecordZone(zoneID: CloudKitManager.privateZoneID)
        let operation = CKModifyRecordZonesOperation(
            recordZonesToSave: [zone],
            recordZoneIDsToDelete: nil
        )
        operation.modifyRecordZonesResultBlock = { result in
            switch result {
            case .success:
                logInfo("CloudKit private zone created/verified")
                DispatchQueue.main.async { completion(.success(())) }
            case .failure(let error):
                logError("CloudKit zone creation failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        operation.qualityOfService = .userInitiated
        privateDatabase.add(operation)
    }

    // MARK: - Subscriptions

    func setupPrivateDatabaseSubscription(completion: @escaping (Result<Void, Error>) -> Void) {
        let subscriptionID = "finova-private-changes"
        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let operation = CKModifySubscriptionsOperation(
            subscriptionsToSave: [subscription],
            subscriptionIDsToDelete: nil
        )
        operation.modifySubscriptionsResultBlock = { result in
            switch result {
            case .success:
                logInfo("CloudKit private subscription set up")
                DispatchQueue.main.async { completion(.success(())) }
            case .failure(let error):
                if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                    DispatchQueue.main.async { completion(.success(())) }
                } else {
                    logError("CloudKit subscription failed: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
        operation.qualityOfService = .utility
        privateDatabase.add(operation)
    }

    func setupPublicInvitationSubscription(email: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let oldSubscriptionIDs = [
            "finova-public-invitations-\(email.hashValue)",
            "finova-public-invitations-v2-\(email.hashValue)",
            "finova-public-invitations-v3-\(email.hashValue)"
        ]
        let subscriptionID = "finova-public-invitations-v4-\(email.hashValue)"

        // Delete old subscription versions
        let deleteOp = CKModifySubscriptionsOperation(
            subscriptionsToSave: nil,
            subscriptionIDsToDelete: oldSubscriptionIDs
        )
        deleteOp.modifySubscriptionsResultBlock = { _ in }
        deleteOp.qualityOfService = .utility
        publicDatabase.add(deleteOp)
        let predicate = NSPredicate(format: "inviteeEmail == %@ AND status == %@", email, "pending")
        let subscription = CKQuerySubscription(
            recordType: "GroupInvitation",
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )

        // Use visible alert so iOS delivers reliably in background.
        // Silent-only pushes (content-available without alert) are throttled by iOS.
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.titleLocalizationKey = "budgetGroups.invitation.notificationTitle"
        notificationInfo.alertLocalizationKey = "budgetGroups.invitation.notificationBody"
        notificationInfo.alertLocalizationArgs = ["inviterName", "groupName"]
        notificationInfo.soundName = "default"
        notificationInfo.desiredKeys = ["inviterName", "groupName", "groupId"]
        subscription.notificationInfo = notificationInfo

        let operation = CKModifySubscriptionsOperation(
            subscriptionsToSave: [subscription],
            subscriptionIDsToDelete: nil
        )
        operation.modifySubscriptionsResultBlock = { result in
            switch result {
            case .success:
                logInfo("CloudKit public invitation subscription set up for \(email)")
                DispatchQueue.main.async { completion(.success(())) }
            case .failure(let error):
                if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                    // Subscription already exists
                    DispatchQueue.main.async { completion(.success(())) }
                } else {
                    logError("CloudKit public invitation subscription failed: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
        operation.qualityOfService = .utility
        publicDatabase.add(operation)
    }

    func setupSharedDatabaseSubscription(completion: @escaping (Result<Void, Error>) -> Void) {
        let subscriptionID = "finova-shared-changes"
        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let operation = CKModifySubscriptionsOperation(
            subscriptionsToSave: [subscription],
            subscriptionIDsToDelete: nil
        )
        operation.modifySubscriptionsResultBlock = { result in
            switch result {
            case .success:
                logInfo("CloudKit shared subscription set up")
                DispatchQueue.main.async { completion(.success(())) }
            case .failure(let error):
                if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                    DispatchQueue.main.async { completion(.success(())) }
                } else {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
        operation.qualityOfService = .utility
        sharedDatabase.add(operation)
    }

    // MARK: - Group Activity Subscriptions

    /// Creates CKQuerySubscription for GroupActivity records in each group zone.
    /// Uses visible alerts so iOS delivers push notifications immediately in background.
    func setupGroupActivitySubscriptions() {
        let repo = BudgetGroupRepository()
        let groups = repo.fetchAllGroups().filter { !$0.isDeleted }
        guard !groups.isEmpty else { return }

        for group in groups {
            let subscriptionID = "finova-group-activity-\(group.id)"

            let zoneID: CKRecordZone.ID
            let database: CKDatabase

            if group.isOwner {
                zoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: CKCurrentUserDefaultName)
                database = privateDatabase
            } else if let zoneOwner = group.ckZoneOwner {
                zoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: zoneOwner)
                database = sharedDatabase
            } else {
                continue
            }

            let predicate = NSPredicate(value: true)
            let subscription = CKQuerySubscription(
                recordType: "GroupActivity",
                predicate: predicate,
                subscriptionID: subscriptionID,
                options: [.firesOnRecordCreation]
            )
            subscription.zoneID = zoneID

            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            notificationInfo.titleLocalizationKey = "GROUP_ACTIVITY_TITLE"
            notificationInfo.alertLocalizationKey = "GROUP_ACTIVITY_BODY"
            notificationInfo.alertLocalizationArgs = ["actorName", "action"]
            notificationInfo.soundName = "default"
            notificationInfo.desiredKeys = ["actorName", "action", "detail", "actorId", "targetRecordName"]
            subscription.notificationInfo = notificationInfo

            let operation = CKModifySubscriptionsOperation(
                subscriptionsToSave: [subscription],
                subscriptionIDsToDelete: nil
            )
            operation.modifySubscriptionsResultBlock = { result in
                switch result {
                case .success:
                    logInfo("GroupActivity subscription set up for group \(group.id)")
                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                        // Subscription already exists — fine
                    } else {
                        logError("GroupActivity subscription failed for group \(group.id): \(error.localizedDescription)")
                    }
                }
            }
            operation.qualityOfService = .utility
            database.add(operation)
        }
    }

    // MARK: - Remote Notification Handling

    func handleRemoteNotification(
        userInfo: [AnyHashable: Any],
        completion: @escaping () -> Void
    ) {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)

        guard let _ = notification else {
            completion()
            return
        }

        NotificationCenter.default.post(name: .cloudKitRemoteNotificationReceived, object: nil)
        completion()
    }

    // MARK: - User Record ID

    func fetchCurrentUserRecordID(completion: @escaping (Result<CKRecord.ID, Error>) -> Void) {
        container.fetchUserRecordID { recordID, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
            } else if let recordID = recordID {
                DispatchQueue.main.async { completion(.success(recordID)) }
            }
        }
    }
}
