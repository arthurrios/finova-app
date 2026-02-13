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
        guard let shareURL = invitation.ckShareUrl,
              let url = URL(string: shareURL) else {
            completion(.failure(NSError(domain: "GroupInvitation", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid share URL"])))
            return
        }

        CloudKitManager.shared.container.fetchShareMetadata(with: url) { metadata, error in
            guard let metadata = metadata else {
                completion(.failure(error ?? NSError(domain: "GroupInvitation", code: 2, userInfo: nil)))
                return
            }

            CloudKitManager.shared.container.accept(metadata) { [weak self] _, error in
                guard let self = self else { return }
                if let error = error {
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }

                let group = BudgetGroup(
                    id: self.invitation.groupId,
                    name: self.invitation.groupName,
                    ownerId: "",
                    ownerName: self.invitation.inviterName,
                    ownerEmail: self.invitation.inviterEmail
                )
                self.repository.insertGroup(group)
                self.repository.updateInvitationStatus(id: self.invitation.id, status: "accepted")

                SyncEngine.shared.performFullSync()

                DispatchQueue.main.async { completion(.success(group)) }
            }
        }
    }

    func declineInvitation() {
        repository.updateInvitationStatus(id: invitation.id, status: "declined")
    }
}
