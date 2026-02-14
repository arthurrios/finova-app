//
//  BudgetGroupsViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import Foundation

final class BudgetGroupsViewModel {
    private let groupService = BudgetGroupService.shared
    private let repository = BudgetGroupRepository()

    private(set) var groups: [BudgetGroup] = []
    private(set) var pendingInvitations: [GroupInvitation] = []
    var onGroupsUpdated: (() -> Void)?
    var onError: ((String) -> Void)?

    var hasPendingInvitations: Bool { !pendingInvitations.isEmpty }
    var isEmpty: Bool { groups.isEmpty && pendingInvitations.isEmpty }

    func loadGroups() {
        groups = repository.fetchAllGroups()
        // Load members for each group
        for i in groups.indices {
            groups[i].members = repository.fetchMembers(forGroupId: groups[i].id)
        }
        pendingInvitations = BudgetGroupService.shared.fetchPendingInvitations()
        onGroupsUpdated?()
    }

    func createGroup(name: String) {
        groupService.createGroup(name: name) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.loadGroups()
                case .failure(let error):
                    self?.onError?(error.localizedDescription)
                }
            }
        }
    }

    func deleteGroup(at index: Int) {
        guard index < groups.count else { return }
        let group = groups[index]
        guard group.isOwner else {
            onError?("sharing.error.onlyOwnerCanDelete".localized)
            return
        }
        repository.softDeleteGroup(id: group.id)
        loadGroups()
    }
}
