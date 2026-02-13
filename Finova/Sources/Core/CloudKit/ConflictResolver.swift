//
//  ConflictResolver.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit
import Foundation

final class ConflictResolver {
    static let shared = ConflictResolver()

    private init() {}

    func resolveTransaction(remote: Transaction, ckRecord: CKRecord) {
        let repo = TransactionRepository()

        guard let remoteId = remote.id,
              let local = repo.fetchTransaction(byId: remoteId) else {
            // New record from cloud - insert locally
            repo.insertFromCloud(remote, ckRecordName: ckRecord.recordID.recordName)
            return
        }

        // Compare modification dates - last writer wins
        let remoteModDate = ckRecord.modificationDate ?? Date.distantPast
        let localModDate = repo.lastModifiedDate(for: local.id ?? 0) ?? Date.distantPast

        if remoteModDate > localModDate {
            repo.updateFromCloud(remote, ckRecordName: ckRecord.recordID.recordName)
        } else {
            repo.markSyncPending(for: local.id ?? 0)
        }
    }
}
