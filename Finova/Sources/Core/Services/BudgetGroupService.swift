//
//  BudgetGroupService.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit
import Foundation

final class BudgetGroupService {
    static let shared = BudgetGroupService()

    private let repository = BudgetGroupRepository()
    private let cloudKit = CloudKitManager.shared

    func createGroup(name: String, completion: @escaping (Result<BudgetGroup, Error>) -> Void) {
        guard let user = AuthenticationManager.shared.currentUser else {
            completion(.failure(NSError(domain: "BudgetGroupService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }

        let userId = user.uid
        let userName = UserDefaultsManager.getUser()?.name ?? user.displayName ?? "User"
        let userEmail = user.email ?? ""

        let group = BudgetGroup(
            name: name,
            ownerId: userId,
            ownerName: userName,
            ownerEmail: userEmail
        )

        // Save locally
        repository.insertGroup(group)

        // Create owner as first member
        let ownerMember = GroupMember(
            groupId: group.id,
            userId: userId,
            name: userName,
            email: userEmail,
            role: .owner,
            permissions: .fullAccess,
            lastActive: Date()
        )
        repository.insertMember(ownerMember)

        // Create CKShare for this group
        createCloudKitShare(for: group) { result in
            switch result {
            case .success(let updatedGroup):
                completion(.success(updatedGroup))
            case .failure(let error):
                // Group exists locally, sync will retry later
                logError("CKShare creation failed: \(error)")
                completion(.success(group))
            }
        }
    }

    func fetchAllGroups() -> [BudgetGroup] {
        let groups = repository.fetchAllGroups()
        // Fix existing shares that have restrictive permissions
        upgradeExistingSharePermissions(groups: groups)
        return groups
    }

    func fetchGroup(byId id: String) -> BudgetGroup? {
        return repository.fetchGroup(byId: id)
    }

    func updateGroup(_ group: BudgetGroup) {
        repository.updateGroup(group)
    }

    func deleteGroup(id: String) {
        repository.softDeleteGroup(id: id)
    }

    func inviteMember(
        email: String,
        toGroup group: BudgetGroup,
        permissions: GroupPermissions = .memberDefault,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard group.isOwner || currentUserCan(\.canInviteMembers, in: group) else {
            completion(.failure(NSError(domain: "BudgetGroupService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No permission to invite members"])))
            return
        }

        guard let user = AuthenticationManager.shared.currentUser else { return }

        let userName = UserDefaultsManager.getUser()?.name ?? user.displayName ?? "User"
        let userEmail = user.email ?? ""

        // Create invitation record with share URL
        var invitation = GroupInvitation(
            groupId: group.id,
            groupName: group.name,
            inviterName: userName,
            inviterEmail: userEmail,
            inviteeEmail: email
        )
        invitation.ckShareUrl = group.ckShareUrl
        repository.insertInvitation(invitation)

        // Push invitation via CloudKit (add participant to share), then save to public DB
        // CKShare participant addition is best-effort; public DB save is the critical path
        pushInvitationToCloud(invitation, group: group) { [weak self] _ in
            self?.saveInvitationToPublicDB(invitation) { saveResult in
                switch saveResult {
                case .success:
                    completion(.success(()))
                case .failure(let error):
                    logError("Failed to save invitation to public DB: \(error)")
                    completion(.failure(error))
                }
            }
        }
    }

    func currentUserCan(_ permission: WritableKeyPath<GroupPermissions, Bool>, in group: BudgetGroup) -> Bool {
        guard let user = AuthenticationManager.shared.currentUser else { return false }

        let userId = user.uid

        if group.ownerId == userId { return true }

        let members = repository.fetchMembers(forGroupId: group.id)
        guard let member = members.first(where: { $0.userId == userId }) else { return false }
        return member.permissions[keyPath: permission]
    }

    func fetchPendingInvitations() -> [GroupInvitation] {
        guard let email = AuthenticationManager.shared.currentUser?.email else { return [] }
        return repository.fetchPendingInvitations(forEmail: email)
    }

    func respondToInvitation(id: String, accept: Bool) {
        repository.updateInvitationStatus(id: id, status: accept ? "accepted" : "declined")
    }

    // MARK: - Share Permission Migration

    /// Upgrades existing CKShares from .none to .readWrite so invitees can accept via URL.
    /// Only runs for groups owned by the current user that have a share URL.
    private func upgradeExistingSharePermissions(groups: [BudgetGroup]) {
        let ownedGroups = groups.filter { $0.isOwner && $0.ckShareUrl != nil }
        guard !ownedGroups.isEmpty else { return }

        for group in ownedGroups {
            guard let urlString = group.ckShareUrl, let shareURL = URL(string: urlString) else { continue }

            let fetchOp = CKFetchShareMetadataOperation(shareURLs: [shareURL])
            fetchOp.shouldFetchRootRecord = false
            fetchOp.perShareMetadataResultBlock = { [weak self] _, result in
                guard let self = self else { return }
                switch result {
                case .success(let metadata):
                    let shareRecordID = metadata.share.recordID
                    self.cloudKit.privateDatabase.fetch(withRecordID: shareRecordID) { record, _ in
                        guard let share = record as? CKShare else { return }
                        guard share.publicPermission != .readWrite else { return }

                        share.publicPermission = .readWrite
                        let saveOp = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
                        saveOp.modifyRecordsResultBlock = { result in
                            switch result {
                            case .success:
                                logInfo("Upgraded CKShare permission to .readWrite for group \(group.name)")
                            case .failure(let error):
                                logError("Failed to upgrade CKShare permission for group \(group.name): \(error)")
                            }
                        }
                        saveOp.qualityOfService = .utility
                        self.cloudKit.privateDatabase.add(saveOp)
                    }
                case .failure(let error):
                    logError("Failed to fetch share metadata for permission upgrade: \(error)")
                }
            }
            fetchOp.qualityOfService = .utility
            cloudKit.container.add(fetchOp)
        }
    }

    // MARK: - CloudKit Share

    private func createCloudKitShare(
        for group: BudgetGroup,
        completion: @escaping (Result<BudgetGroup, Error>) -> Void
    ) {
        let zoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)

        // Create zone first
        let zoneOp = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
        zoneOp.modifyRecordZonesResultBlock = { [weak self] result in
            switch result {
            case .success:
                self?.createShareRecord(for: group, in: zoneID, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
        zoneOp.qualityOfService = .userInitiated
        cloudKit.privateDatabase.add(zoneOp)
    }

    private func createShareRecord(
        for group: BudgetGroup,
        in zoneID: CKRecordZone.ID,
        completion: @escaping (Result<BudgetGroup, Error>) -> Void
    ) {
        // Create the root record for the group
        let recordID = CKRecord.ID(recordName: "budgetGroup-\(group.id)", zoneID: zoneID)
        let record = CKRecord(recordType: "BudgetGroup", recordID: recordID)
        record["name"] = group.name as CKRecordValue
        record["ownerId"] = group.ownerId as CKRecordValue
        record["ownerName"] = group.ownerName as CKRecordValue

        // Create a CKShare rooted on this record
        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = group.name as CKRecordValue
        share.publicPermission = .readWrite // Anyone with the share URL can accept

        let operation = CKModifyRecordsOperation(recordsToSave: [record, share], recordIDsToDelete: nil)
        operation.modifyRecordsResultBlock = { [weak self] result in
            switch result {
            case .success:
                var updatedGroup = group
                updatedGroup.ckRecordId = recordID.recordName
                updatedGroup.ckShareUrl = share.url?.absoluteString
                self?.repository.updateGroup(updatedGroup)
                completion(.success(updatedGroup))
            case .failure(let error):
                completion(.failure(error))
            }
        }
        operation.qualityOfService = .userInitiated
        cloudKit.privateDatabase.add(operation)
    }

    private func pushInvitationToCloud(
        _ invitation: GroupInvitation,
        group: BudgetGroup,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Use CKShare to add participant by email lookup
        guard let shareURLString = group.ckShareUrl,
              let shareURL = URL(string: shareURLString) else {
            logError("CKShare URL missing for group \(group.id) — skipping participant add")
            // Still allow the invitation to be saved to public DB even without CKShare
            completion(.success(()))
            return
        }

        // Fetch the share, add participant
        cloudKit.container.fetchShareMetadata(with: shareURL) { [weak self] metadata, error in
            guard let self = self, let metadata = metadata else {
                logError("Failed to fetch share metadata: \(error?.localizedDescription ?? "unknown")")
                // Allow invitation to proceed via public DB even if share lookup fails
                completion(.success(()))
                return
            }

            // Look up the user by email
            self.cloudKit.container.fetchShareParticipant(
                withEmailAddress: invitation.inviteeEmail
            ) { participant, error in
                guard let participant = participant else {
                    logError("Could not find iCloud participant for \(invitation.inviteeEmail): \(error?.localizedDescription ?? "unknown")")
                    // Allow invitation to proceed via public DB even if participant lookup fails
                    // The invitee can still see the invitation and accept via share URL
                    completion(.success(()))
                    return
                }

                participant.permission = .readWrite

                // Fetch the share record, add participant, save
                self.addParticipantToShare(participant, shareURL: shareURL, completion: completion)
            }
        }
    }

    private func addParticipantToShare(
        _ participant: CKShare.Participant,
        shareURL: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Fetch share by URL, modify it, save back
        let fetchOp = CKFetchShareMetadataOperation(shareURLs: [shareURL])
        fetchOp.shouldFetchRootRecord = true

        fetchOp.perShareMetadataResultBlock = { [weak self] url, result in
            guard let self = self else {
                completion(.success(()))
                return
            }
            switch result {
            case .success(let metadata):
                let shareRecordID = metadata.share.recordID
                // Fetch and modify the share
                self.cloudKit.privateDatabase.fetch(withRecordID: shareRecordID) { record, error in
                    guard let share = record as? CKShare else {
                        logError("Failed to fetch CKShare record: \(error?.localizedDescription ?? "not a CKShare")")
                        completion(.success(()))
                        return
                    }
                    share.addParticipant(participant)

                    let saveOp = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
                    saveOp.modifyRecordsResultBlock = { result in
                        switch result {
                        case .success:
                            logInfo("Participant added to CKShare successfully")
                            completion(.success(()))
                        case .failure(let error):
                            logError("Failed to save participant to CKShare: \(error)")
                            // Still allow invitation to proceed
                            completion(.success(()))
                        }
                    }
                    self.cloudKit.privateDatabase.add(saveOp)
                }
            case .failure(let error):
                logError("Failed to fetch share metadata for participant add: \(error)")
                completion(.success(()))
            }
        }

        cloudKit.container.add(fetchOp)
    }

    // MARK: - Public Database Invitation

    private func saveInvitationToPublicDB(_ invitation: GroupInvitation, completion: @escaping (Result<Void, Error>) -> Void) {
        let recordID = CKRecord.ID(recordName: "invitation-\(invitation.id)")
        let record = CKRecord(recordType: "GroupInvitation", recordID: recordID)

        record["inviteeEmail"] = invitation.inviteeEmail
        record["groupId"] = invitation.groupId
        record["groupName"] = invitation.groupName
        record["inviterName"] = invitation.inviterName
        record["inviterEmail"] = invitation.inviterEmail
        record["ckShareUrl"] = invitation.ckShareUrl
        record["status"] = "pending"
        record["createdAt"] = invitation.createdAt as NSDate

        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                logInfo("Invitation saved to public DB: \(invitation.id)")
                completion(.success(()))
            case .failure(let error):
                logError("Failed to save invitation to public DB: \(error)")
                completion(.failure(error))
            }
        }
        operation.qualityOfService = .userInitiated
        cloudKit.publicDatabase.add(operation)
    }

    func fetchRemoteInvitations(completion: @escaping () -> Void) {
        guard let email = AuthenticationManager.shared.currentUser?.email else {
            logWarning("Cannot fetch invitations: no current user email")
            completion()
            return
        }

        logInfo("Fetching remote invitations for \(email)...")

        let predicate = NSPredicate(format: "inviteeEmail == %@ AND status == %@", email, "pending")
        let query = CKQuery(recordType: "GroupInvitation", predicate: predicate)

        cloudKit.publicDatabase.fetch(withQuery: query) { [weak self] result in
            guard let self = self else {
                completion()
                return
            }

            switch result {
            case .success(let (matchResults, _)):
                logInfo("Found \(matchResults.count) invitation(s) in public DB")
                var newInvitations = false
                for (_, recordResult) in matchResults {
                    switch recordResult {
                    case .success(let record):
                        var invitation = GroupInvitation(
                            id: record.recordID.recordName.replacingOccurrences(of: "invitation-", with: ""),
                            groupId: record["groupId"] as? String ?? "",
                            groupName: record["groupName"] as? String ?? "",
                            inviterName: record["inviterName"] as? String ?? "",
                            inviterEmail: record["inviterEmail"] as? String ?? "",
                            inviteeEmail: record["inviteeEmail"] as? String ?? "",
                            createdAt: record["createdAt"] as? Date ?? Date()
                        )
                        invitation.ckShareUrl = record["ckShareUrl"] as? String

                        if self.repository.fetchInvitation(byId: invitation.id) == nil {
                            self.repository.insertInvitation(invitation)
                            newInvitations = true
                            logInfo("New invitation discovered: \(invitation.groupName) from \(invitation.inviterName)")
                        }
                    case .failure(let error):
                        logError("Failed to fetch individual invitation record: \(error)")
                    }
                }
                if newInvitations {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .groupInvitationReceived, object: nil)
                    }
                }
            case .failure(let error):
                logError("Failed to fetch remote invitations from public DB: \(error)")
                if let ckError = error as? CKError {
                    logError("CKError code: \(ckError.code.rawValue) — ensure 'inviteeEmail' and 'status' are marked as Queryable in CloudKit Dashboard")
                }
            }
            completion()
        }
    }
}

// MARK: - GroupInvitation

struct GroupInvitation: Codable {
    let id: String
    let groupId: String
    let groupName: String
    let inviterName: String
    let inviterEmail: String
    let inviteeEmail: String
    var status: String
    var ckShareUrl: String?
    let createdAt: Date
    var respondedAt: Date?

    init(
        id: String = UUID().uuidString,
        groupId: String,
        groupName: String,
        inviterName: String,
        inviterEmail: String,
        inviteeEmail: String,
        status: String = "pending",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.groupId = groupId
        self.groupName = groupName
        self.inviterName = inviterName
        self.inviterEmail = inviterEmail
        self.inviteeEmail = inviteeEmail
        self.status = status
        self.createdAt = createdAt
    }
}
