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

        // Filter invitations: remove duplicates (keep latest per group) and
        // hide invitations for groups the user is already a member of
        let joinedGroupIds = Set(groups.map { $0.id })
        var allInvitations = BudgetGroupService.shared.fetchPendingInvitations()
        allInvitations = allInvitations.filter { !joinedGroupIds.contains($0.groupId) }

        // Deduplicate: keep only the most recent invitation per group
        var seenGroupIds = Set<String>()
        var uniqueInvitations: [GroupInvitation] = []
        let sorted = allInvitations.sorted { $0.createdAt > $1.createdAt }
        for invitation in sorted {
            if seenGroupIds.insert(invitation.groupId).inserted {
                uniqueInvitations.append(invitation)
            }
        }
        pendingInvitations = uniqueInvitations

        onGroupsUpdated?()
    }

    /// `completion` fires after the CloudKit round-trip AND the reload, so the caller can keep a
    /// loading state up for the whole thing rather than dismissing while the group is still being made.
    func createGroup(name: String, completion: ((Bool) -> Void)? = nil) {
        groupService.createGroup(name: name) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.loadGroups()
                    completion?(true)
                case .failure(let error):
                    self?.onError?(error.localizedDescription)
                    completion?(false)
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
        // Via the service, not the repository: it also deletes the group's CloudKit zone, without
        // which the zone lingers and other devices resurrect the group.
        BudgetGroupService.shared.deleteGroup(id: group.id)


        loadGroups()
        NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
    }

    func leaveGroup(at index: Int) {
        guard index < groups.count else { return }
        let group = groups[index]
        guard let userId = AuthenticationManager.shared.currentUser?.uid else { return }
        let members = repository.fetchMembers(forGroupId: group.id)
        if let member = members.first(where: { $0.userId == userId }) {
            repository.removeMember(id: member.id)
        }
        // Soft-delete the group locally so it disappears from this device
        repository.softDeleteGroup(id: group.id)


        loadGroups()
        NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
    }
}
