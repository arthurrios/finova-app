//
//  BudgetGroupRepository.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import Foundation

final class BudgetGroupRepository {
    private let db = DBHelper.shared

    // MARK: - BudgetGroup CRUD

    func insertGroup(_ group: BudgetGroup) {
        let query = """
            INSERT INTO BudgetGroups (id, name, owner_id, owner_name, owner_email, currency, ck_record_id, ck_share_url, ck_zone_owner, created_at, updated_at, is_deleted)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        db.executeGroupWrite(query, orderedBindings: [
            group.id,
            group.name,
            group.ownerId,
            group.ownerName,
            group.ownerEmail,
            group.currency,
            group.ckRecordId,
            group.ckShareUrl,
            group.ckZoneOwner,
            Int(group.createdAt.timeIntervalSince1970),
            Int(group.updatedAt.timeIntervalSince1970),
            group.isDeleted ? 1 : 0
        ])
    }

    func fetchAllGroups() -> [BudgetGroup] {
        let query = """
            SELECT id, name, owner_id, owner_name, owner_email, currency, ck_record_id, ck_share_url, ck_zone_owner, created_at, updated_at, is_deleted
            FROM BudgetGroups WHERE is_deleted = 0
            """
        var groups = db.fetchBudgetGroupRows(query)

        for i in groups.indices {
            groups[i].members = fetchMembers(forGroupId: groups[i].id)
        }

        return groups
    }

    func fetchGroup(byId id: String) -> BudgetGroup? {
        let query = """
            SELECT id, name, owner_id, owner_name, owner_email, currency, ck_record_id, ck_share_url, ck_zone_owner, created_at, updated_at, is_deleted
            FROM BudgetGroups WHERE id = ?
            """
        guard var group = db.fetchBudgetGroupRows(query, textBindings: [id]).first else { return nil }
        group.members = fetchMembers(forGroupId: group.id)
        return group
    }

    func updateGroup(_ group: BudgetGroup) {
        let query = """
            UPDATE BudgetGroups SET name = ?, owner_id = ?, owner_name = ?, owner_email = ?, currency = ?, ck_record_id = ?, ck_share_url = ?, ck_zone_owner = ?, updated_at = ?, is_deleted = ?
            WHERE id = ?
            """
        db.executeGroupWrite(query, orderedBindings: [
            group.name,
            group.ownerId,
            group.ownerName,
            group.ownerEmail,
            group.currency,
            group.ckRecordId,
            group.ckShareUrl,
            group.ckZoneOwner,
            Int(Date().timeIntervalSince1970),
            group.isDeleted ? 1 : 0,
            group.id
        ])
    }

    func updateZoneOwner(groupId: String, zoneOwner: String) {
        let query = "UPDATE BudgetGroups SET ck_zone_owner = ?, updated_at = ? WHERE id = ?"
        db.executeGroupWrite(query, orderedBindings: [
            zoneOwner,
            Int(Date().timeIntervalSince1970),
            groupId
        ])
    }

    func softDeleteGroup(id: String) {
        let query = "UPDATE BudgetGroups SET is_deleted = 1, updated_at = ? WHERE id = ?"
        db.executeGroupWrite(query, orderedBindings: [
            Int(Date().timeIntervalSince1970),
            id
        ])

        // Un-tag data associated with this group so it returns to personal
        db.executeSyncUpdate(
            "UPDATE Transactions SET shared_group_id = NULL, sync_status = 'pending' WHERE shared_group_id = ?",
            textBindings: [id]
        )
        db.executeSyncUpdate(
            "UPDATE Budgets SET shared_group_id = NULL, sync_status = 'pending' WHERE shared_group_id = ?",
            textBindings: [id]
        )
        db.executeSyncUpdate(
            "UPDATE CreditCards SET shared_group_id = NULL, sync_status = 'pending' WHERE shared_group_id = ?",
            textBindings: [id]
        )
        db.executeSyncUpdate(
            "UPDATE BudgetAllocations SET shared_group_id = NULL, sync_status = 'pending' WHERE shared_group_id = ?",
            textBindings: [id]
        )

        TransactionRepository.invalidateCache()
    }

    // MARK: - GroupMember CRUD

    func insertMember(_ member: GroupMember) {
        let query = """
            INSERT INTO GroupMembers (id, group_id, user_id, name, email, role, permissions, last_active, joined_at, is_removed)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        db.executeGroupWrite(query, orderedBindings: [
            member.id,
            member.groupId,
            member.userId,
            member.name,
            member.email,
            member.role.rawValue,
            member.permissions.asJSON,
            member.lastActive.map { Int($0.timeIntervalSince1970) },
            Int(member.joinedAt.timeIntervalSince1970),
            member.isRemoved ? 1 : 0
        ])
    }

    func fetchMembers(forGroupId groupId: String) -> [GroupMember] {
        let query = """
            SELECT id, group_id, user_id, name, email, role, permissions, last_active, joined_at, is_removed
            FROM GroupMembers WHERE group_id = ? AND is_removed = 0
            """
        return db.fetchGroupMemberRows(query, textBindings: [groupId])
    }

    func fetchMembersIncludingRemoved(forGroupId groupId: String) -> [GroupMember] {
        let query = """
            SELECT id, group_id, user_id, name, email, role, permissions, last_active, joined_at, is_removed
            FROM GroupMembers WHERE group_id = ?
            """
        return db.fetchGroupMemberRows(query, textBindings: [groupId])
    }

    func purgeRemovedMembers(forGroupId groupId: String) {
        let query = "DELETE FROM GroupMembers WHERE group_id = ? AND is_removed = 1"
        db.executeGroupWrite(query, orderedBindings: [groupId])
    }

    /// Removes duplicate member rows, keeping the best record per identity.
    /// Groups by email (or userId if no email), and for owners by role.
    /// Keeps the record with a real UID (not email), latest activity, and active status.
    func deduplicateMembers(forGroupId groupId: String) {
        let all = fetchMembersIncludingRemoved(forGroupId: groupId)
        guard all.count > 2 else { return }

        var bestByKey: [String: GroupMember] = [:]
        var duplicateIds: [String] = []

        for member in all {
            // Use role for owners (one owner per group), email for members
            let key: String
            if member.role == .owner {
                key = "owner"
            } else if !member.email.isEmpty {
                key = member.email.lowercased()
            } else {
                key = member.userId
            }

            if let existing = bestByKey[key] {
                // Pick the better record to keep
                let keepNew = isBetterMember(member, than: existing)
                if keepNew {
                    duplicateIds.append(existing.id)
                    bestByKey[key] = member
                } else {
                    duplicateIds.append(member.id)
                }
            } else {
                bestByKey[key] = member
            }
        }

        for id in duplicateIds {
            db.executeGroupWrite("DELETE FROM GroupMembers WHERE id = ?", orderedBindings: [id])
        }
    }

    /// Returns true if `a` is a better record to keep than `b`.
    private func isBetterMember(_ a: GroupMember, than b: GroupMember) -> Bool {
        // Prefer active over removed
        if a.isRemoved != b.isRemoved { return !a.isRemoved }
        // Prefer real UID (not an email address used as placeholder)
        let aReal = !a.userId.isEmpty && !a.userId.contains("@")
        let bReal = !b.userId.isEmpty && !b.userId.contains("@")
        if aReal != bReal { return aReal }
        // Prefer has lastActive
        if (a.lastActive != nil) != (b.lastActive != nil) { return a.lastActive != nil }
        // Prefer most recently active
        let aTime = a.lastActive ?? a.joinedAt
        let bTime = b.lastActive ?? b.joinedAt
        return aTime > bTime
    }

    func updateMember(_ member: GroupMember) {
        let query = """
            UPDATE GroupMembers SET user_id = ?, name = ?, email = ?, role = ?, permissions = ?, last_active = ?, is_removed = ?
            WHERE id = ?
            """
        db.executeGroupWrite(query, orderedBindings: [
            member.userId,
            member.name,
            member.email,
            member.role.rawValue,
            member.permissions.asJSON,
            member.lastActive.map { Int($0.timeIntervalSince1970) },
            member.isRemoved ? 1 : 0,
            member.id
        ])
    }

    func removeMember(id: String) {
        let query = "UPDATE GroupMembers SET is_removed = 1 WHERE id = ?"
        db.executeGroupWrite(query, orderedBindings: [id])
    }

    func updateMemberLastActive(userId: String, date: Date) {
        let query = "UPDATE GroupMembers SET last_active = ? WHERE user_id = ? AND is_removed = 0"
        db.executeGroupWrite(query, orderedBindings: [
            Int(date.timeIntervalSince1970),
            userId
        ])
    }

    // MARK: - GroupInvitation CRUD

    func insertInvitation(_ invitation: GroupInvitation) {
        let query = """
            INSERT INTO GroupInvitations (id, group_id, group_name, inviter_name, inviter_email, invitee_email, status, ck_share_url, created_at, responded_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        db.executeGroupWrite(query, orderedBindings: [
            invitation.id,
            invitation.groupId,
            invitation.groupName,
            invitation.inviterName,
            invitation.inviterEmail,
            invitation.inviteeEmail,
            invitation.status,
            invitation.ckShareUrl,
            Int(invitation.createdAt.timeIntervalSince1970),
            invitation.respondedAt.map { Int($0.timeIntervalSince1970) }
        ])
    }

    func fetchInvitation(byId id: String) -> GroupInvitation? {
        let query = """
            SELECT id, group_id, group_name, inviter_name, inviter_email, invitee_email, status, ck_share_url, created_at, responded_at
            FROM GroupInvitations WHERE id = ?
            """
        return db.fetchGroupInvitationRows(query, textBindings: [id]).first
    }

    func fetchPendingInvitations(forEmail email: String) -> [GroupInvitation] {
        let query = """
            SELECT id, group_id, group_name, inviter_name, inviter_email, invitee_email, status, ck_share_url, created_at, responded_at
            FROM GroupInvitations WHERE invitee_email = ? AND status = 'pending'
            """
        return db.fetchGroupInvitationRows(query, textBindings: [email])
    }

    func fetchPendingInvitationsForGroup(groupId: String) -> [GroupInvitation] {
        let query = """
            SELECT id, group_id, group_name, inviter_name, inviter_email, invitee_email, status, ck_share_url, created_at, responded_at
            FROM GroupInvitations WHERE group_id = ? AND status = 'pending'
            """
        return db.fetchGroupInvitationRows(query, textBindings: [groupId])
    }

    func updateInvitationStatus(id: String, status: String) {
        let query = "UPDATE GroupInvitations SET status = ?, responded_at = ? WHERE id = ?"
        db.executeGroupWrite(query, orderedBindings: [
            status,
            Int(Date().timeIntervalSince1970),
            id
        ])
    }

    func deleteAllInvitations() {
        db.executeGroupWrite("DELETE FROM GroupInvitations", orderedBindings: [])
    }
}
