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
            INSERT INTO BudgetGroups (id, name, owner_id, owner_name, owner_email, currency, ck_record_id, ck_share_url, created_at, updated_at, is_deleted)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            Int(group.createdAt.timeIntervalSince1970),
            Int(group.updatedAt.timeIntervalSince1970),
            group.isDeleted ? 1 : 0
        ])
    }

    func fetchAllGroups() -> [BudgetGroup] {
        let query = """
            SELECT id, name, owner_id, owner_name, owner_email, currency, ck_record_id, ck_share_url, created_at, updated_at, is_deleted
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
            SELECT id, name, owner_id, owner_name, owner_email, currency, ck_record_id, ck_share_url, created_at, updated_at, is_deleted
            FROM BudgetGroups WHERE id = ?
            """
        guard var group = db.fetchBudgetGroupRows(query, textBindings: [id]).first else { return nil }
        group.members = fetchMembers(forGroupId: group.id)
        return group
    }

    func updateGroup(_ group: BudgetGroup) {
        let query = """
            UPDATE BudgetGroups SET name = ?, currency = ?, ck_record_id = ?, ck_share_url = ?, updated_at = ?, is_deleted = ?
            WHERE id = ?
            """
        db.executeGroupWrite(query, orderedBindings: [
            group.name,
            group.currency,
            group.ckRecordId,
            group.ckShareUrl,
            Int(Date().timeIntervalSince1970),
            group.isDeleted ? 1 : 0,
            group.id
        ])
    }

    func softDeleteGroup(id: String) {
        let query = "UPDATE BudgetGroups SET is_deleted = 1, updated_at = ? WHERE id = ?"
        db.executeGroupWrite(query, orderedBindings: [
            Int(Date().timeIntervalSince1970),
            id
        ])
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

    func updateMember(_ member: GroupMember) {
        let query = """
            UPDATE GroupMembers SET name = ?, email = ?, role = ?, permissions = ?, last_active = ?, is_removed = ?
            WHERE id = ?
            """
        db.executeGroupWrite(query, orderedBindings: [
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

    func fetchPendingInvitations(forEmail email: String) -> [GroupInvitation] {
        let query = """
            SELECT id, group_id, group_name, inviter_name, inviter_email, invitee_email, status, ck_share_url, created_at, responded_at
            FROM GroupInvitations WHERE invitee_email = ? AND status = 'pending'
            """
        return db.fetchGroupInvitationRows(query, textBindings: [email])
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
