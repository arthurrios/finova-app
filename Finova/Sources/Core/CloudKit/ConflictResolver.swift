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
        let recordName = ckRecord.recordID.recordName

        // First check if we already have this cloud record locally (by ck_record_id)
        if let existing = repo.fetchTransaction(byCKRecordName: recordName) {
            // Record exists locally — compare modification dates
            let remoteModDate = ckRecord.modificationDate ?? Date.distantPast
            let localModDate = repo.lastModifiedDate(for: existing.id ?? 0) ?? Date.distantPast

            if remoteModDate > localModDate {
                repo.updateFromCloud(remote, ckRecordName: recordName)
            } else {
                repo.markSyncPending(for: existing.id ?? 0)
            }
            return
        }

        // Fallback: check by local id
        if let remoteId = remote.id,
           let local = repo.fetchTransaction(byId: remoteId) {
            let remoteModDate = ckRecord.modificationDate ?? Date.distantPast
            let localModDate = repo.lastModifiedDate(for: local.id ?? 0) ?? Date.distantPast

            if remoteModDate > localModDate {
                repo.updateFromCloud(remote, ckRecordName: recordName)
            } else {
                repo.markSyncPending(for: local.id ?? 0)
            }
            return
        }

        // Truly new record — insert
        repo.insertFromCloud(remote, ckRecordName: recordName)
    }
}
