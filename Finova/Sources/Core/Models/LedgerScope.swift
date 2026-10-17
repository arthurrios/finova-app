//
//  LedgerScope.swift
//  Finova
//
//  Which ledger a read is against. This build has only the user's own ledger.
//
//  The database still holds rows tagged with a `shared_group_id` from builds that had family
//  groups. A personal read must keep excluding them (`groupId == nil` filters on `user_id` and an
//  untagged group column), so the scope keeps its group field even though nothing sets it.
//

import Foundation

struct LedgerScope: Equatable {
    /// nil means the personal ledger.
    let groupId: String?
    /// The signed-in user. Needed even in group scope, to tell "mine" from "another member's".
    let localUid: String?

    var isPersonal: Bool { groupId == nil }

    init(groupId: String?, localUid: String?) {
        self.groupId = groupId
        self.localUid = localUid
    }

    static var personal: LedgerScope {
        LedgerScope(groupId: nil, localUid: UIDUserDefaultsManager.shared.currentUserUID)
    }
}
