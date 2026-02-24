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

    // MARK: - System Fields Persistence

    /// Encodes a CKRecord's system fields (including recordChangeTag) and persists them
    /// so the next push can use `.ifServerRecordUnchanged` with the correct tag.
    private func storeSystemFields(from ckRecord: CKRecord, table: String) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        ckRecord.encodeSystemFields(with: coder)
        coder.finishEncoding()
        DBHelper.shared.saveSystemFields(coder.encodedData, ckRecordName: ckRecord.recordID.recordName, table: table)
    }

    // MARK: - Transaction

    func resolveTransaction(remote: Transaction, ckRecord: CKRecord) {
        let repo = TransactionRepository()
        let recordName = ckRecord.recordID.recordName
        let sharedGroupId = ckRecord["sharedGroupId"] as? String

        // Step 1: Match by CK record name (most reliable)
        if let existing = repo.fetchTransaction(byCKRecordName: recordName) {
            let remoteModDate = ckRecord.modificationDate ?? Date.distantPast
            if let localModDate = repo.lastModifiedDate(for: existing.id ?? 0) {
                if remoteModDate > localModDate {
                    repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
                } else {
                    repo.markSyncPending(for: existing.id ?? 0)
                }
            } else {
                // No local modification timestamp — record was created locally but never synced.
                // Keep the local data; markSyncPending will set ck_modified_at and it will be pushed.
                repo.markSyncPending(for: existing.id ?? 0)
            }
            storeSystemFields(from: ckRecord, table: "Transactions")
            return
        }

        // Step 2: Match recurring instance by parent + month (prevents duplicates from lazy generation)
        // Phase 4C: Use parentCKRecordName from the CK record to find the local parent
        let parentCKRecordName = ckRecord["parentCKRecordName"] as? String
        if let _ = remote.parentTransactionId {
            var localParentId: Int? = nil

            // Primary: resolve parent via CK record name (cross-device safe)
            if let parentCKName = parentCKRecordName,
               let localParent = repo.fetchTransaction(byCKRecordName: parentCKName) {
                localParentId = localParent.id
            }
            // Fallback: try remote parent ID directly (same device scenario)
            if localParentId == nil, let remoteParentId = remote.parentTransactionId {
                localParentId = remoteParentId
            }
            let parentIdsToCheck = Set([localParentId].compactMap { $0 })

            for parentId in parentIdsToCheck {
                if let local = repo.fetchRecurringInstance(parentId: parentId, budgetMonthDate: remote.budgetMonthDate) {
                    let localId = local.id ?? 0
                    let existingCKName = repo.fetchCKRecordName(for: localId)
                    if existingCKName == nil {
                        repo.setCKRecordId(for: localId, ckRecordName: recordName)

                        let remoteModDate = ckRecord.modificationDate ?? Date.distantPast
                        if let localModDate = repo.lastModifiedDate(for: localId) {
                            if remoteModDate > localModDate {
                                repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
                            } else {
                                repo.markSyncPending(for: localId)
                            }
                        } else {
                            repo.markSyncPending(for: localId)
                        }
                        storeSystemFields(from: ckRecord, table: "Transactions")
                        return
                    }
                    // Already linked to a different CK record — skip to avoid duplicate
                    if existingCKName != recordName {
                        return
                    }
                }
            }
        }

        // Creation-date guard: if this CKRecord was first saved to CloudKit AFTER this
        // device's last successful pull, this device has never seen it before.
        // Skip the fuzzy-match steps (3 & 4) — there is no valid local counterpart to
        // link it to, and matching by title/amount/month risks conflating it with a
        // completely different local transaction that silently overwrites Device A's data.
        // (If both devices independently created the same transaction, they will appear
        // as two separate CloudKit records — a visible duplicate is better than silent loss.)
        // Note: if lastSyncDate is nil (never synced), skip this guard so first-sync
        // deduplication still runs normally.
        if let creationDate = ckRecord.creationDate,
           let lastSync = SyncStateManager.shared.lastSyncDate(for: "privateDB"),
           creationDate > lastSync {
            repo.insertFromCloud(remote, ckRecordName: recordName, parentCKRecordName: parentCKRecordName, sharedGroupId: sharedGroupId)
            storeSystemFields(from: ckRecord, table: "Transactions")
            return
        }

        // Step 3: Fallback for recurring instances — match by title + amount + month
        // Handles cases where parent ID mapping failed (e.g. both devices created the parent independently)
        if remote.parentTransactionId != nil {
            let title = remote.title
            let amount = remote.amount
            if let local = repo.fetchMatchingRecurringInstance(
                title: title, amount: amount, budgetMonthDate: remote.budgetMonthDate
            ) {
                let localId = local.id ?? 0
                let existingCKName = repo.fetchCKRecordName(for: localId)
                if existingCKName == nil {
                    repo.setCKRecordId(for: localId, ckRecordName: recordName)

                    let remoteModDate = ckRecord.modificationDate ?? Date.distantPast
                    if let localModDate = repo.lastModifiedDate(for: localId) {
                        if remoteModDate > localModDate {
                            repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
                        } else {
                            repo.markSyncPending(for: localId)
                        }
                    } else {
                        repo.markSyncPending(for: localId)
                    }
                    storeSystemFields(from: ckRecord, table: "Transactions")
                    return
                }
                if existingCKName != recordName {
                    return
                }
            }
        }

        // Step 4: General fallback — match any transaction by title + amount + budget_month_date
        // This catches duplicate parents, normal transactions, and any other unmatched records
        if let local = repo.fetchMatchingTransaction(
            title: remote.title, amount: remote.amount, budgetMonthDate: remote.budgetMonthDate
        ) {
            let localId = local.id ?? 0
            let existingCKName = repo.fetchCKRecordName(for: localId)
            if existingCKName == nil {
                // Link unsynced local record to this CloudKit record
                repo.setCKRecordId(for: localId, ckRecordName: recordName)

                let remoteModDate = ckRecord.modificationDate ?? Date.distantPast
                if let localModDate = repo.lastModifiedDate(for: localId) {
                    if remoteModDate > localModDate {
                        repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
                    } else {
                        repo.markSyncPending(for: localId)
                    }
                } else {
                    repo.markSyncPending(for: localId)
                }
                storeSystemFields(from: ckRecord, table: "Transactions")
                return
            }
            // Already linked to a different CK record — skip to avoid duplicate
            if existingCKName != recordName {
                return
            }
        }

        // Phase 4C: Pass parentCKRecordName so insertFromCloud can remap parent ID
        repo.insertFromCloud(remote, ckRecordName: recordName, parentCKRecordName: parentCKRecordName, sharedGroupId: sharedGroupId)
        storeSystemFields(from: ckRecord, table: "Transactions")
    }

    // MARK: - Budget

    func resolveBudget(remote: BudgetModel, ckRecord: CKRecord) {
        let repo = BudgetRepository()
        let recordName = ckRecord.recordID.recordName

        if let existing = repo.fetchBudget(byCKRecordName: recordName) {
            let remoteModDate = ckRecord.modificationDate ?? Date.distantPast
            if let localModDate = repo.lastModifiedDate(forMonthDate: existing.monthDate) {
                if remoteModDate > localModDate {
                    repo.updateFromCloud(remote, ckRecordName: recordName)
                } else {
                    repo.markSyncPending(forMonthDate: existing.monthDate)
                }
            } else {
                repo.markSyncPending(forMonthDate: existing.monthDate)
            }
            storeSystemFields(from: ckRecord, table: "Budgets")
            return
        }

        if let local = repo.fetchBudget(byMonthDate: remote.monthDate) {
            repo.setCKRecordId(forMonthDate: remote.monthDate, ckRecordName: recordName)

            let remoteModDate = ckRecord.modificationDate ?? Date.distantPast
            if let localModDate = repo.lastModifiedDate(forMonthDate: local.monthDate) {
                if remoteModDate > localModDate {
                    repo.updateFromCloud(remote, ckRecordName: recordName)
                } else {
                    repo.markSyncPending(forMonthDate: local.monthDate)
                }
            } else {
                repo.markSyncPending(forMonthDate: local.monthDate)
            }
            storeSystemFields(from: ckRecord, table: "Budgets")
            return
        }

        repo.insertFromCloud(remote, ckRecordName: recordName)
        storeSystemFields(from: ckRecord, table: "Budgets")
    }

    // MARK: - Credit Card

    func resolveCreditCard(remote: CreditCard, ckRecord: CKRecord) {
        let repo = CreditCardRepository()
        let recordName = ckRecord.recordID.recordName

        if let existing = repo.fetchCard(byCKRecordName: recordName) {
            let remoteModDate = ckRecord.modificationDate ?? Date.distantPast
            if let localModDate = repo.lastModifiedDate(for: existing.id ?? 0) {
                if remoteModDate > localModDate {
                    repo.updateFromCloud(remote, ckRecordName: recordName)
                } else {
                    repo.markSyncPending(for: existing.id ?? 0)
                }
            } else {
                repo.markSyncPending(for: existing.id ?? 0)
            }
            storeSystemFields(from: ckRecord, table: "CreditCards")
            return
        }

        // Phase 3E: Removed local-ID matching step — with UUID-based CK record names,
        // matching by local auto-increment ID is dangerous (cross-device ID collisions).

        repo.insertFromCloud(remote, ckRecordName: recordName)
        storeSystemFields(from: ckRecord, table: "CreditCards")
    }

    // MARK: - Credit Card Statement

    func resolveCreditCardStatement(remote: CreditCardStatement, ckRecord: CKRecord) {
        let repo = StatementRepository()
        let recordName = ckRecord.recordID.recordName

        if let existing = repo.fetchStatement(byCKRecordName: recordName) {
            let remoteModDate = ckRecord.modificationDate ?? Date.distantPast
            if let localModDate = repo.lastModifiedDate(for: existing.id ?? 0) {
                if remoteModDate > localModDate {
                    repo.updateFromCloud(remote, ckRecordName: recordName)
                } else {
                    repo.markSyncPending(for: existing.id ?? 0)
                }
            } else {
                repo.markSyncPending(for: existing.id ?? 0)
            }
            storeSystemFields(from: ckRecord, table: "CreditCardStatements")
            return
        }

        // Phase 3E: Removed local-ID matching step — with UUID-based CK record names,
        // matching by local auto-increment ID is dangerous (cross-device ID collisions).

        repo.insertFromCloud(remote, ckRecordName: recordName)
        storeSystemFields(from: ckRecord, table: "CreditCardStatements")
    }

    // MARK: - Budget Allocation

    func resolveBudgetAllocation(remote: BudgetAllocationModel, ckRecord: CKRecord) {
        let repo = BudgetAllocationRepository()
        let recordName = ckRecord.recordID.recordName

        if let existing = repo.fetchAllocation(byCKRecordName: recordName) {
            let remoteModDate = ckRecord.modificationDate ?? Date.distantPast
            if let localModDate = repo.lastModifiedDate(for: existing.id ?? 0) {
                if remoteModDate > localModDate {
                    repo.updateFromCloud(remote, ckRecordName: recordName)
                } else {
                    repo.markSyncPending(for: existing.id ?? 0)
                }
            } else {
                repo.markSyncPending(for: existing.id ?? 0)
            }
            storeSystemFields(from: ckRecord, table: "BudgetAllocations")
            return
        }

        // Phase 3E: Removed local-ID matching step — with UUID-based CK record names,
        // matching by local auto-increment ID is dangerous (cross-device ID collisions).

        repo.insertFromCloud(remote, ckRecordName: recordName)
        storeSystemFields(from: ckRecord, table: "BudgetAllocations")
    }
}
