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
        return repository.fetchAllGroups()
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

        // Create invitation record
        let invitation = GroupInvitation(
            groupId: group.id,
            groupName: group.name,
            inviterName: userName,
            inviterEmail: userEmail,
            inviteeEmail: email
        )
        repository.insertInvitation(invitation)

        // Push invitation via CloudKit
        pushInvitationToCloud(invitation, group: group, completion: completion)
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
        share.publicPermission = .none // Only explicit participants

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
            completion(.failure(NSError(domain: "BudgetGroupService", code: 3, userInfo: nil)))
            return
        }

        // Fetch the share, add participant
        cloudKit.container.fetchShareMetadata(with: shareURL) { [weak self] metadata, error in
            guard let self = self, let metadata = metadata else {
                completion(.failure(error ?? NSError(domain: "BudgetGroupService", code: 4, userInfo: nil)))
                return
            }

            // Look up the user by email
            self.cloudKit.container.fetchShareParticipant(
                withEmailAddress: invitation.inviteeEmail
            ) { participant, error in
                guard let participant = participant else {
                    completion(.failure(error ?? NSError(domain: "BudgetGroupService", code: 5, userInfo: nil)))
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

        fetchOp.perShareMetadataResultBlock = { url, result in
            switch result {
            case .success(let metadata):
                guard let shareRecordID = metadata.share.recordID as CKRecord.ID? else { return }
                // Fetch and modify the share
                self.cloudKit.privateDatabase.fetch(withRecordID: shareRecordID) { record, error in
                    guard let share = record as? CKShare else { return }
                    share.addParticipant(participant)

                    let saveOp = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
                    saveOp.modifyRecordsResultBlock = { result in
                        switch result {
                        case .success:
                            completion(.success(()))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                    self.cloudKit.privateDatabase.add(saveOp)
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }

        cloudKit.container.add(fetchOp)
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
