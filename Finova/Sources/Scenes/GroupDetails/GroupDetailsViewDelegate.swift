//
//  GroupDetailsViewDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

protocol GroupDetailsViewDelegate: AnyObject {
    func handleDidTapBackButton()
    func didTapInvite()
    func didTapLeaveGroup()
    func didTapDeleteGroup()
    func didTapRenameGroup()
    func didTapCurrency()
    func didSelectMember(_ member: GroupMember)
    func didTapMigrateData()
}
