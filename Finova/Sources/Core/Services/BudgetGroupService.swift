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
        var groups = repository.fetchAllGroups()
        // Repair: if ownerId was stored as email (invitation acceptance bug), replace with Firebase UID
        if let currentUser = AuthenticationManager.shared.currentUser {
            for i in groups.indices where groups[i].ownerId == currentUser.email && groups[i].ownerId != currentUser.uid {
                groups[i].ownerId = currentUser.uid
                repository.updateGroup(groups[i])
                logInfo("Repaired ownerId for group '\(groups[i].name)': email → UID")
            }
        }
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

    /// Public entry point for propagating a share URL to invitation records in public DB.
    /// Called by SyncEngine to ensure invitations have the share URL.
    /// Fix 1d: Includes retry logic for network failures.
    func propagateShareUrl(groupId: String, newUrl: String, retryCount: Int = 0) {
        let maxRetries = 2

        // Query public DB by groupId (now queryable) and update any records missing the share URL
        let predicate = NSPredicate(format: "groupId == %@", groupId)
        let query = CKQuery(recordType: "GroupInvitation", predicate: predicate)

        cloudKit.publicDatabase.fetch(withQuery: query) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let (matchResults, _)):
                var recordsToSave: [CKRecord] = []
                for (_, recordResult) in matchResults {
                    if case .success(let record) = recordResult {
                        let existingUrl = record["ckShareUrl"] as? String ?? ""
                        if existingUrl.isEmpty || existingUrl != newUrl {
                            record["ckShareUrl"] = newUrl
                            recordsToSave.append(record)
                        }
                    }
                }
                guard !recordsToSave.isEmpty else {
                    logInfo("All invitation records for group \(groupId) already have correct share URL")
                    return
                }

                let updateOp = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
                updateOp.modifyRecordsResultBlock = { [weak self] result in
                    switch result {
                    case .success:
                        logInfo("Updated \(recordsToSave.count) invitation(s) with share URL for group \(groupId)")
                    case .failure(let error):
                        logError("Failed to update invitation share URLs: \(error)")
                        if retryCount < maxRetries {
                            let delay = Double(retryCount + 1) * 2.0
                            logWarning("Retrying share URL propagation in \(delay)s (attempt \(retryCount + 1)/\(maxRetries))")
                            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
                                self?.propagateShareUrl(groupId: groupId, newUrl: newUrl, retryCount: retryCount + 1)
                            }
                        }
                    }
                }
                updateOp.qualityOfService = .utility
                self.cloudKit.publicDatabase.add(updateOp)

            case .failure(let error):
                logError("Failed to query invitations for share URL propagation: \(error)")
                if retryCount < maxRetries {
                    let delay = Double(retryCount + 1) * 2.0
                    logWarning("Retrying share URL propagation query in \(delay)s (attempt \(retryCount + 1)/\(maxRetries))")
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.propagateShareUrl(groupId: groupId, newUrl: newUrl, retryCount: retryCount + 1)
                    }
                }
            }
        }
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

        // Re-fetch group from DB to get the latest ckShareUrl (may have been updated since caller got the object)
        let latestGroup = repository.fetchGroup(byId: group.id) ?? group
        let shareUrl = latestGroup.ckShareUrl

        let sendInvitation: (String?) -> Void = { [weak self] finalShareUrl in
            guard let self = self else { return }

            var invitation = GroupInvitation(
                groupId: group.id,
                groupName: group.name,
                inviterName: userName,
                inviterEmail: userEmail,
                inviteeEmail: email
            )
            invitation.ckShareUrl = finalShareUrl
            if finalShareUrl == nil {
                logWarning("Sending invitation without share URL — group '\(group.name)' has no CKShare")
            } else {
                logInfo("Sending invitation with share URL: \(finalShareUrl!)")
            }
            self.repository.insertInvitation(invitation)

            let groupForPush = finalShareUrl != nil ? latestGroup : group
            self.pushInvitationToCloud(invitation, group: groupForPush) { [weak self] _ in
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

        if shareUrl != nil {
            sendInvitation(shareUrl)
        } else {
            // No share URL yet — create the CK zone + share first, then send invitation with fresh URL
            logInfo("Creating CKShare before sending invitation for group '\(group.name)'")
            createCloudKitShare(for: latestGroup) { result in
                switch result {
                case .success(let updatedGroup):
                    sendInvitation(updatedGroup.ckShareUrl)
                case .failure:
                    // Still send invitation — invitee can use fallback URL fetch
                    sendInvitation(nil)
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

    func currentUserCan(
        _ allPermission: WritableKeyPath<GroupPermissions, Bool>,
        own ownPermission: WritableKeyPath<GroupPermissions, Bool>,
        createdByUid: String?,
        in group: BudgetGroup
    ) -> Bool {
        guard let user = AuthenticationManager.shared.currentUser else { return false }

        let userId = user.uid

        // Owner always gets full access
        if group.ownerId == userId { return true }

        let members = repository.fetchMembers(forGroupId: group.id)
        guard let member = members.first(where: { $0.userId == userId }) else { return false }

        // If record was created by current user, check own permission
        if createdByUid == userId {
            return member.permissions[keyPath: ownPermission]
        }

        // Otherwise check all-data permission
        return member.permissions[keyPath: allPermission]
    }

    func fetchPendingInvitations() -> [GroupInvitation] {
        guard let email = AuthenticationManager.shared.currentUser?.email else { return [] }
        return repository.fetchPendingInvitations(forEmail: email)
    }

    func respondToInvitation(id: String, accept: Bool) {
        repository.updateInvitationStatus(id: id, status: accept ? "accepted" : "declined")
    }

    // MARK: - Push GroupMember CKRecord

    /// Pushes a GroupMember CKRecord to the group zone so the owner can discover new members.
    func pushGroupMemberRecord(
        member: GroupMember,
        groupId: String,
        zoneOwner: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let zoneID = CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: zoneOwner)
        let recordID = CKRecord.ID(recordName: "groupMember-\(member.id)", zoneID: zoneID)
        let record = CKRecord(recordType: "GroupMember", recordID: recordID)

        record["groupId"] = member.groupId as CKRecordValue
        record["userId"] = member.userId as CKRecordValue
        record["name"] = member.name as CKRecordValue
        record["email"] = member.email as CKRecordValue
        record["role"] = member.role.rawValue as CKRecordValue
        record["joinedAt"] = member.joinedAt as NSDate
        record["permissions"] = member.permissions.asJSON as CKRecordValue

        // Owner writes to private DB (they own the zone), member writes to shared DB
        let database: CKDatabase
        if zoneOwner == CKCurrentUserDefaultName {
            database = cloudKit.privateDatabase
        } else {
            database = cloudKit.sharedDatabase
        }

        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                logInfo("GroupMember record pushed to group zone for \(member.name)")
                completion(.success(()))
            case .failure(let error):
                logError("Failed to push GroupMember record: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
        operation.qualityOfService = .userInitiated
        database.add(operation)
    }

    // MARK: - Push Member Removal

    /// Pushes a GroupMember CKRecord with isRemoved=1 to the group zone so the member discovers their removal.
    func pushGroupMemberRemoval(
        member: GroupMember,
        groupId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let zoneID = CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: "groupMember-\(member.id)", zoneID: zoneID)
        let record = CKRecord(recordType: "GroupMember", recordID: recordID)

        record["groupId"] = member.groupId as CKRecordValue
        record["userId"] = member.userId as CKRecordValue
        record["name"] = member.name as CKRecordValue
        record["email"] = member.email as CKRecordValue
        record["role"] = member.role.rawValue as CKRecordValue
        record["joinedAt"] = member.joinedAt as NSDate
        record["isRemoved"] = 1 as CKRecordValue

        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                logInfo("GroupMember removal pushed to group zone for \(member.name)")
                completion(.success(()))
            case .failure(let error):
                logError("Failed to push GroupMember removal: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
        operation.qualityOfService = .userInitiated
        cloudKit.privateDatabase.add(operation)
    }

    // MARK: - Share Permission Migration

    /// Upgrades existing CKShares from .none to .readWrite so invitees can accept via URL.
    /// Also performs one-time migration from hierarchical to zone-based shares.
    private func upgradeExistingSharePermissions(groups: [BudgetGroup]) {
        let ownedGroups = groups.filter { $0.isOwner && $0.ckShareUrl != nil }
        guard !ownedGroups.isEmpty else { return }

        // v2 key forces re-run since v1 was set prematurely before async completion
        let needsZoneShareMigration = !UserDefaults.standard.bool(forKey: "hasCompletedZoneShareMigration_v2")

        for group in ownedGroups {
            if needsZoneShareMigration {
                migrateToZoneShare(group: group)
                // Skip permission upgrade — migration handles it
                continue
            }

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

    /// Replaces the existing CKShare for a group with a zone-based CKShare
    /// that shares ALL records in the zone, then propagates the new URL
    /// to pending invitations in public DB.
    private func migrateToZoneShare(group: BudgetGroup) {
        let zoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: CKCurrentUserDefaultName)

        logWarning("Migrating group '\(group.name)' to zone-based share")

        // Use the known share URL to find the old share record
        guard let urlString = group.ckShareUrl, let shareURL = URL(string: urlString) else {
            logError("No share URL for group '\(group.name)' — creating fresh zone share")
            createZoneShareAndPropagate(group: group, zoneID: zoneID, oldShareID: nil)
            return
        }

        let fetchMeta = CKFetchShareMetadataOperation(shareURLs: [shareURL])
        fetchMeta.shouldFetchRootRecord = false

        var oldShareRecordID: CKRecord.ID?

        fetchMeta.perShareMetadataResultBlock = { _, result in
            if case .success(let metadata) = result {
                oldShareRecordID = metadata.share.recordID
            }
        }

        fetchMeta.fetchShareMetadataResultBlock = { [weak self] _ in
            guard let self = self else { return }

            if oldShareRecordID == nil {
                logWarning("Old share not found via URL for '\(group.name)' — creating fresh zone share")
            }

            self.createZoneShareAndPropagate(group: group, zoneID: zoneID, oldShareID: oldShareRecordID)
        }

        fetchMeta.qualityOfService = .userInitiated
        cloudKit.container.add(fetchMeta)
    }

    /// Deletes the old share (if any), creates a zone-based share, updates local DB,
    /// and propagates the new share URL to pending invitations in public DB.
    private func createZoneShareAndPropagate(
        group: BudgetGroup,
        zoneID: CKRecordZone.ID,
        oldShareID: CKRecord.ID?
    ) {
        let doCreate = { [weak self] in
            guard let self = self else { return }

            let newShare = CKShare(recordZoneID: zoneID)
            newShare[CKShare.SystemFieldKey.title] = group.name as CKRecordValue
            newShare.publicPermission = .readWrite

            let saveOp = CKModifyRecordsOperation(recordsToSave: [newShare], recordIDsToDelete: nil)
            saveOp.modifyRecordsResultBlock = { [weak self] result in
                switch result {
                case .success:
                    guard let newURL = newShare.url?.absoluteString else {
                        logError("Zone share created but URL is nil for '\(group.name)'")
                        return
                    }
                    logInfo("Created zone-based share for '\(group.name)' — URL: \(newURL)")

                    // Update local group record
                    var updated = group
                    updated.ckShareUrl = newURL
                    self?.repository.updateGroup(updated)

                    // Propagate new URL to pending invitations in public DB
                    self?.updatePendingInvitationShareUrls(groupId: group.id, newUrl: newURL)

                    // Mark migration complete only after success
                    UserDefaults.standard.set(true, forKey: "hasCompletedZoneShareMigration_v2")
                    logInfo("Zone share migration complete for '\(group.name)'")

                case .failure(let error):
                    logError("Failed to create zone share for '\(group.name)': \(error)")
                    // Do NOT set the flag — migration will retry next time
                }
            }
            saveOp.qualityOfService = .userInitiated
            self.cloudKit.privateDatabase.add(saveOp)
        }

        if let oldID = oldShareID {
            let deleteOp = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [oldID])
            deleteOp.modifyRecordsResultBlock = { result in
                if case .failure(let error) = result {
                    logError("Failed to delete old share for '\(group.name)': \(error) — creating new anyway")
                } else {
                    logInfo("Deleted old hierarchical share for '\(group.name)'")
                }
                doCreate()
            }
            deleteOp.qualityOfService = .userInitiated
            cloudKit.privateDatabase.add(deleteOp)
        } else {
            doCreate()
        }
    }

    /// Updates all pending invitation records in public DB with a new share URL.
    /// Fetches by known record IDs from local DB to avoid needing queryable `groupId` field.
    private func updatePendingInvitationShareUrls(groupId: String, newUrl: String) {
        // Get all locally known invitations and filter for this group's pending ones
        guard let email = AuthenticationManager.shared.currentUser?.email else { return }
        let localInvitations = repository.fetchPendingInvitations(forEmail: email)
            + getAllLocalPendingInvitations(forGroupId: groupId)

        let recordIDs = localInvitations
            .filter { $0.groupId == groupId }
            .map { CKRecord.ID(recordName: "invitation-\($0.id)") }

        guard !recordIDs.isEmpty else {
            logInfo("No local pending invitations found for group \(groupId) to update share URL")
            return
        }

        // Fetch each record by ID (no queryable fields needed), update the URL, and save
        let fetchOp = CKFetchRecordsOperation(recordIDs: recordIDs)

        var recordsToSave: [CKRecord] = []
        let lock = NSLock()

        fetchOp.perRecordResultBlock = { _, result in
            if case .success(let record) = result {
                record["ckShareUrl"] = newUrl
                lock.lock()
                recordsToSave.append(record)
                lock.unlock()
            }
        }

        fetchOp.fetchRecordsResultBlock = { [weak self] result in
            if case .failure(let error) = result {
                logError("Failed to fetch invitation records for URL update: \(error)")
            }
            guard let self = self, !recordsToSave.isEmpty else { return }

            let updateOp = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
            updateOp.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    logInfo("Updated \(recordsToSave.count) pending invitation(s) with new share URL")
                case .failure(let error):
                    logError("Failed to update invitation share URLs: \(error)")
                }
            }
            updateOp.qualityOfService = .utility
            self.cloudKit.publicDatabase.add(updateOp)
        }

        fetchOp.qualityOfService = .utility
        cloudKit.publicDatabase.add(fetchOp)
    }

    /// Fetches all locally stored pending invitations for a specific group (invitations the owner sent).
    private func getAllLocalPendingInvitations(forGroupId groupId: String) -> [GroupInvitation] {
        let query = """
            SELECT id, group_id, group_name, inviter_name, inviter_email, invitee_email, status, ck_share_url, created_at, responded_at
            FROM GroupInvitations WHERE group_id = ? AND status = 'pending'
            """
        return DBHelper.shared.fetchGroupInvitationRows(query, textBindings: [groupId])
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
        // Create the group metadata record
        let recordID = CKRecord.ID(recordName: "budgetGroup-\(group.id)", zoneID: zoneID)
        let record = CKRecord(recordType: "BudgetGroup", recordID: recordID)
        record["name"] = group.name as CKRecordValue
        record["ownerId"] = group.ownerId as CKRecordValue
        record["ownerName"] = group.ownerName as CKRecordValue
        record["ownerEmail"] = group.ownerEmail as CKRecordValue

        // Zone-based share: shares ALL records in the zone (transactions, budgets, etc.)
        // Unlike CKShare(rootRecord:) which only shares the root + its CKReference children,
        // CKShare(recordZoneID:) makes every record in the zone visible to participants.
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = group.name as CKRecordValue
        share.publicPermission = .readWrite

        let operation = CKModifyRecordsOperation(recordsToSave: [record, share], recordIDsToDelete: nil)
        operation.modifyRecordsResultBlock = { [weak self] result in
            switch result {
            case .success:
                var updatedGroup = group
                updatedGroup.ckRecordId = recordID.recordName
                updatedGroup.ckShareUrl = share.url?.absoluteString
                self?.repository.updateGroup(updatedGroup)

                // Fix 1d: Propagate share URL to pending invitations in public DB
                if let newUrl = share.url?.absoluteString {
                    self?.propagateShareUrl(groupId: group.id, newUrl: newUrl)
                }

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
