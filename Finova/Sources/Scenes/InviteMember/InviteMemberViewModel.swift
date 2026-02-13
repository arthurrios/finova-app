//
//  InviteMemberViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import Foundation

final class InviteMemberViewModel {
    private let groupService = BudgetGroupService.shared

    let group: BudgetGroup
    var email: String = ""
    var currentPermissions: GroupPermissions = .viewOnly

    var onPermissionsUpdated: ((GroupPermissions) -> Void)?

    init(group: BudgetGroup) {
        self.group = group
    }

    func applyPreset(_ preset: GroupPermissions) {
        currentPermissions = preset
        onPermissionsUpdated?(currentPermissions)
    }

    func updatePermission(key: String, value: Bool) {
        currentPermissions.setPermission(key: key, value: value)
    }

    func sendInvitation(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !email.isEmpty else {
            completion(.failure(NSError(domain: "", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "invite.error.emptyEmail".localized])))
            return
        }

        groupService.inviteMember(
            email: email,
            toGroup: group,
            permissions: currentPermissions
        ) { result in
            DispatchQueue.main.async { completion(result) }
        }
    }
}
