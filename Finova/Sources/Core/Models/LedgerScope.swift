//
//  LedgerScope.swift
//  Finova
//
//  Which ledger a read is against: the user's own, or a group's.
//
//  `DataContext` answers this for the UI (it carries a whole `BudgetGroup`, for titles and chips).
//  `LedgerScope` is its resolved form for queries: the two values a scoped predicate actually needs.
//  A bare `String?` group id cannot express it — a personal read filters on `user_id` and a group
//  read on `shared_group_id`, so the local uid has to travel alongside.
//
//  Resolve it ONCE per render pass and thread it down. Re-resolving per call site is how reads
//  drift apart: several already do, which is why a group could render a budget from one scope and
//  allocations from another.
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

    static func group(_ groupId: String) -> LedgerScope {
        LedgerScope(groupId: groupId, localUid: UIDUserDefaultsManager.shared.currentUserUID)
    }

    init(_ context: DataContext) {
        self.init(groupId: context.groupId, localUid: UIDUserDefaultsManager.shared.currentUserUID)
    }

    /// The user's last active context. Use only where no context is being rendered — a screen that
    /// knows what it is showing should pass that context rather than consult this.
    static var current: LedgerScope {
        LedgerScope(UIDUserDefaultsManager.shared.getLastContext())
    }
}
