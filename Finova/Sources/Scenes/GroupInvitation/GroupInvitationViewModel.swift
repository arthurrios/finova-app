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
        // Create group locally and update invitation status regardless of CKShare result
        let group = BudgetGroup(
            id: invitation.groupId,
            name: invitation.groupName,
            ownerId: "",
            ownerName: invitation.inviterName,
            ownerEmail: invitation.inviterEmail
        )
        repository.insertGroup(group)
        repository.updateInvitationStatus(id: invitation.id, status: "accepted")
        updateRemoteInvitationStatus("accepted")

        // CKShare acceptance is best-effort — group works via public DB sync
        if let shareURL = invitation.ckShareUrl, let url = URL(string: shareURL) {
            CloudKitManager.shared.container.fetchShareMetadata(with: url) { metadata, error in
                if let metadata = metadata {
                    CloudKitManager.shared.container.accept(metadata) { _, error in
                        if let error = error {
                            logError("CKShare acceptance failed (non-blocking): \(error.localizedDescription)")
                        } else {
                            logInfo("CKShare accepted successfully")
                        }
                        SyncEngine.shared.performFullSync()
                        DispatchQueue.main.async { completion(.success(group)) }
                    }
                } else {
                    logError("CKShare metadata fetch failed (non-blocking): \(error?.localizedDescription ?? "unknown")")
                    SyncEngine.shared.performFullSync()
                    DispatchQueue.main.async { completion(.success(group)) }
                }
            }
        } else {
            SyncEngine.shared.performFullSync()
            DispatchQueue.main.async { completion(.success(group)) }
        }
    }

    func declineInvitation() {
        repository.updateInvitationStatus(id: invitation.id, status: "declined")
        updateRemoteInvitationStatus("declined")
    }

    private func updateRemoteInvitationStatus(_ status: String) {
        let recordID = CKRecord.ID(recordName: "invitation-\(invitation.id)")
        CloudKitManager.shared.publicDatabase.fetch(withRecordID: recordID) { record, error in
            guard let record = record else {
                if let error = error {
                    logError("Failed to fetch invitation record for status update: \(error)")
                }
                return
            }
            record["status"] = status
            CloudKitManager.shared.publicDatabase.save(record) { _, error in
                if let error = error {
                    logError("Failed to update invitation status in public DB: \(error)")
                }
            }
        }
    }
}
