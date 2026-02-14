//
//  PostSyncActions.swift
//  Finova
//
//  Created by Arthur Rios on 14/02/26.
//

import Foundation

protocol PostSyncActions {
    func performPostSyncFetches(completion: @escaping () -> Void)
}

final class RealPostSyncActions: PostSyncActions {
    func performPostSyncFetches(completion: @escaping () -> Void) {
        let group = DispatchGroup()

        group.enter()
        UIDUserDefaultsManager.shared.fetchBalanceOffsetsFromCloud {
            group.leave()
        }

        group.enter()
        BudgetGroupService.shared.fetchRemoteInvitations {
            group.leave()
        }

        group.notify(queue: DispatchQueue(label: "com.finova.postsync")) {
            completion()
        }
    }
}
