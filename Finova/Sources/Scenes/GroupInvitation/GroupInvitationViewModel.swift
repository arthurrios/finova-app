//
//  GroupInvitationViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit
import Foundation

final class GroupInvitationViewModel {
    let invitation: GroupInvitation
    let permissions: GroupPermissions
    private let repository = BudgetGroupRepository()

    init(invitation: GroupInvitation, permissions: GroupPermissions = .viewOnly) {
        self.invitation = invitation
        self.permissions = permissions
    }

    func acceptInvitation(completion: @escaping (Result<BudgetGroup, Error>) -> Void) {
        // Handle re-join: if the group was previously left/deleted, clean up stale data
        let group: BudgetGroup
        if let existingGroup = repository.fetchGroup(byId: invitation.groupId) {
            // Group exists (possibly soft-deleted) — restore it and purge stale members
            var restored = existingGroup
            restored.name = invitation.groupName
            restored.isDeleted = false
            repository.updateGroup(restored)
            repository.purgeRemovedMembers(forGroupId: invitation.groupId)
            repository.deduplicateMembers(forGroupId: invitation.groupId)
            group = restored
        } else {
            group = BudgetGroup(
                id: invitation.groupId,
                name: invitation.groupName,
                ownerId: invitation.inviterEmail,
                ownerName: invitation.inviterName,
                ownerEmail: invitation.inviterEmail
            )
            repository.insertGroup(group)
        }

        repository.updateInvitationStatus(id: invitation.id, status: "accepted")
        updateRemoteInvitationStatus("accepted")

        // Ensure owner member exists locally (avoid duplicates)
        let existingMembers = repository.fetchMembers(forGroupId: invitation.groupId)
        if !existingMembers.contains(where: { $0.email == invitation.inviterEmail || $0.role == .owner }) {
            let ownerMember = GroupMember(
                groupId: invitation.groupId,
                userId: invitation.inviterEmail, // Placeholder — corrected by sync from CKRecord ownerId
                name: invitation.inviterName,
                email: invitation.inviterEmail,
                role: .owner,
                permissions: .fullAccess,
                lastActive: Date()
            )
            repository.insertMember(ownerMember)
        }

        // Ensure current user member exists locally (avoid duplicates)
        let currentUser = AuthenticationManager.shared.currentUser
        let currentUid = currentUser?.uid ?? ""
        let currentEmail = currentUser?.email ?? ""
        let member: GroupMember
        if !existingMembers.contains(where: { $0.userId == currentUid || (!currentEmail.isEmpty && $0.email == currentEmail) }) {
            member = GroupMember(
                groupId: invitation.groupId,
                userId: currentUid,
                name: UserDefaultsManager.getUser()?.name ?? currentUser?.displayName ?? "User",
                email: currentEmail,
                role: .member,
                permissions: .memberDefault,
                lastActive: Date()
            )
            repository.insertMember(member)
        } else {
            member = existingMembers.first(where: { $0.userId == currentUid || (!currentEmail.isEmpty && $0.email == currentEmail) })!
        }

        // CKShare acceptance — try the stored URL, then retry with latest from public DB
        logInfo("Invitation acceptance: ckShareUrl=\(invitation.ckShareUrl ?? "nil"), groupId=\(invitation.groupId)")
        if let shareURL = invitation.ckShareUrl, let url = URL(string: shareURL) {
            attemptShareAcceptance(url: url, group: group, member: member) { [weak self] success in
                if success {
                    DispatchQueue.main.async { completion(.success(group)) }
                } else {
                    // Share URL might be stale (e.g., owner migrated to zone-based share).
                    // Re-fetch the invitation from public DB to get updated URL.
                    self?.fetchLatestShareUrl(for: self?.invitation.groupId ?? "") { updatedUrlString in
                        if let updatedUrlString = updatedUrlString,
                           updatedUrlString != shareURL,
                           let updatedUrl = URL(string: updatedUrlString) {
                            logInfo("Retrying CKShare acceptance with updated URL from public DB")
                            self?.attemptShareAcceptance(url: updatedUrl, group: group, member: member) { _ in
                                DispatchQueue.main.async { completion(.success(group)) }
                            }
                        } else {
                            logWarning("No updated share URL available — proceeding without CKShare")
                            SyncEngine.shared.performFullSync()
                            DispatchQueue.main.async { completion(.success(group)) }
                        }
                    }
                }
            }
        } else {
            // No share URL at all — try fetching from public DB
            fetchLatestShareUrl(for: invitation.groupId) { [weak self] urlString in
                if let urlString = urlString, let url = URL(string: urlString) {
                    logInfo("Found share URL from public DB: \(urlString)")
                    self?.attemptShareAcceptance(url: url, group: group, member: member) { _ in
                        DispatchQueue.main.async { completion(.success(group)) }
                    }
                } else {
                    SyncEngine.shared.performFullSync()
                    DispatchQueue.main.async { completion(.success(group)) }
                }
            }
        }
    }

    /// Attempts to accept a CKShare via URL. Calls completion with `true` on success, `false` on failure.
    private func attemptShareAcceptance(
        url: URL,
        group: BudgetGroup,
        member: GroupMember,
        completion: @escaping (Bool) -> Void
    ) {
        CloudKitManager.shared.container.fetchShareMetadata(with: url) { [weak self] metadata, error in
            guard let self = self else { completion(false); return }
            guard let metadata = metadata else {
                logError("CKShare metadata fetch failed: \(error?.localizedDescription ?? "unknown") for \(url.absoluteString)")
                completion(false)
                return
            }

            CloudKitManager.shared.container.accept(metadata) { share, error in
                if let error = error {
                    logError("CKShare acceptance failed: \(error.localizedDescription)")
                    SyncEngine.shared.performFullSync()
                    completion(false)
                } else {
                    logInfo("CKShare accepted successfully")
                    if let share = share {
                        let ownerName = share.recordID.zoneID.ownerName
                        self.repository.updateZoneOwner(groupId: self.invitation.groupId, zoneOwner: ownerName)

                        BudgetGroupService.shared.pushGroupMemberRecord(
                            member: member,
                            groupId: self.invitation.groupId,
                            zoneOwner: ownerName
                        ) { _ in }

                        SyncEngine.shared.syncSharedGroupData(
                            groupId: self.invitation.groupId,
                            zoneOwner: ownerName
                        )
                    }

                    let currentUserName = UserDefaultsManager.getUser()?.name
                        ?? AuthenticationManager.shared.currentUser?.displayName
                        ?? "User"
                    GroupNotificationService.shared.logActivity(
                        action: .memberJoined,
                        groupId: self.invitation.groupId,
                        detail: currentUserName
                    )

                    SyncEngine.shared.performFullSync()
                    completion(true)
                }
            }
        }
    }

    /// Fetches the latest share URL for a group from the public DB invitation records.
    /// Uses inviteeEmail (queryable) instead of groupId (not queryable), then filters client-side.
    private func fetchLatestShareUrl(for groupId: String, completion: @escaping (String?) -> Void) {
        guard let email = AuthenticationManager.shared.currentUser?.email else {
            completion(nil)
            return
        }

        // First try: fetch the specific invitation record by known ID (no query needed)
        let recordID = CKRecord.ID(recordName: "invitation-\(invitation.id)")
        CloudKitManager.shared.publicDatabase.fetch(withRecordID: recordID) { [weak self] record, error in
            if let record = record,
               let url = record["ckShareUrl"] as? String, !url.isEmpty {
                logInfo("Found share URL from invitation record: \(url)")
                completion(url)
                return
            }

            // Fallback: query by inviteeEmail (queryable) and filter for groupId client-side
            let predicate = NSPredicate(format: "inviteeEmail == %@", email)
            let query = CKQuery(recordType: "GroupInvitation", predicate: predicate)

            CloudKitManager.shared.publicDatabase.fetch(withQuery: query, desiredKeys: ["ckShareUrl", "groupId"]) { result in
                switch result {
                case .success(let (matchResults, _)):
                    for (_, recordResult) in matchResults {
                        if case .success(let record) = recordResult,
                           let recordGroupId = record["groupId"] as? String,
                           recordGroupId == groupId,
                           let url = record["ckShareUrl"] as? String, !url.isEmpty {
                            completion(url)
                            return
                        }
                    }
                    completion(nil)
                case .failure(let error):
                    logError("Failed to fetch latest share URL from public DB: \(error)")
                    completion(nil)
                }
            }
        }
    }

    func declineInvitation() {
        repository.updateInvitationStatus(id: invitation.id, status: "declined")
        updateRemoteInvitationStatus("declined")
    }

    /// Updates the invitation status in public DB.
    /// Only the record creator (the inviter/owner) can modify it — the invitee's update is best-effort.
    private func updateRemoteInvitationStatus(_ status: String) {
        let recordID = CKRecord.ID(recordName: "invitation-\(invitation.id)")
        CloudKitManager.shared.publicDatabase.fetch(withRecordID: recordID) { record, error in
            guard let record = record else {
                if let error = error {
                    logInfo("Invitation record not found for status update (non-critical): \(error.localizedDescription)")
                }
                return
            }
            record["status"] = status
            CloudKitManager.shared.publicDatabase.save(record) { _, error in
                if let error = error {
                    // Expected to fail when invitee tries to update — only the creator can modify public DB records
                    logInfo("Could not update invitation status in public DB (non-critical): \(error.localizedDescription)")
                }
            }
        }
    }
}
