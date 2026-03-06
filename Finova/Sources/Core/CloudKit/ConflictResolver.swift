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
            // Repair stale cross-device creditCardId from a previous failed recovery.
            // If the existing transaction has a creditCardId that references a card with
            // no ck_record_id AND the remote has a different (correctly remapped) ID,
            // always accept the remote to restore correct card linkage.
            let existingCCId = existing.creditCardId
            let needsCardIdRepair = existingCCId != nil &&
                existingCCId != remote.creditCardId &&
                remote.creditCardId != nil &&
                CreditCardRepository().fetchCKRecordName(for: existingCCId!) == nil
            if needsCardIdRepair {
                repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
                storeSystemFields(from: ckRecord, table: "Transactions")
                return
            }

            let remoteUpdatedAt = remote.updatedAt ?? ckRecord.modificationDate ?? Date.distantPast
            if let localModDate = repo.lastModifiedDate(for: existing.id ?? 0) {
                if remoteUpdatedAt > localModDate {
                    repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
                } else {
                    repo.markSyncPending(for: existing.id ?? 0)
                }
            } else {
                // No local modification timestamp — accept cloud data since we have no basis for comparison.
                repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
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

                        let remoteUpdatedAt = remote.updatedAt ?? ckRecord.modificationDate ?? Date.distantPast
                        if let localModDate = repo.lastModifiedDate(for: localId) {
                            if remoteUpdatedAt > localModDate {
                                repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
                            } else {
                                repo.markSyncPending(for: localId)
                            }
                        } else {
                            repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
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

            // Step 2b: Check for a soft-deleted tombstone (is_deleted=1, ck_record_id=NULL) matching
            // this parent+month. hardDeleteLocal clears ck_record_id on tombstones, making them
            // invisible to step 1 and step 2 (both filter is_deleted=0/ck_record_id match).
            // Without this, CloudKit re-delivers the record on the next pull and insertFromCloud
            // creates a duplicate — resurrecting the deleted instance every sync cycle.
            // Re-linking re-queues it as pendingDelete so it gets deleted from CloudKit again.
            for parentId in parentIdsToCheck {
                if repo.restoreTombstoneForInstance(parentId: parentId, budgetMonthDate: remote.budgetMonthDate, ckRecordName: recordName) {
                    storeSystemFields(from: ckRecord, table: "Transactions")
                    return
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

                    let remoteUpdatedAt = remote.updatedAt ?? ckRecord.modificationDate ?? Date.distantPast
                    if let localModDate = repo.lastModifiedDate(for: localId) {
                        if remoteUpdatedAt > localModDate {
                            repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
                        } else {
                            repo.markSyncPending(for: localId)
                        }
                    } else {
                        repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
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

                let remoteUpdatedAt = remote.updatedAt ?? ckRecord.modificationDate ?? Date.distantPast
                if let localModDate = repo.lastModifiedDate(for: localId) {
                    if remoteUpdatedAt > localModDate {
                        repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
                    } else {
                        repo.markSyncPending(for: localId)
                    }
                } else {
                    repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
                }
                storeSystemFields(from: ckRecord, table: "Transactions")
                return
            }
            // Already linked to a different CK record — skip to avoid duplicate
            if existingCKName != recordName {
                return
            }
        }

        // Guard: if a soft-deleted record exists with this CK name, restore its pendingDelete
        // status instead of re-inserting. This prevents resurrection of records the user
        // deleted locally before the CK delete was pushed (e.g. during a reset sync).
        if repo.restorePendingDeleteIfNeeded(ckRecordName: recordName) { return }

        // Phase 4C: Pass parentCKRecordName so insertFromCloud can remap parent ID
        repo.insertFromCloud(remote, ckRecordName: recordName, parentCKRecordName: parentCKRecordName, sharedGroupId: sharedGroupId)
        storeSystemFields(from: ckRecord, table: "Transactions")
    }

    // MARK: - Budget

    func resolveBudget(remote: BudgetModel, ckRecord: CKRecord) {
        let repo = BudgetRepository()
        let recordName = ckRecord.recordID.recordName

        if let existing = repo.fetchBudget(byCKRecordName: recordName) {
            let remoteUpdatedAt = remote.updatedAt ?? ckRecord.modificationDate ?? Date.distantPast
            if let localModDate = repo.lastModifiedDate(forMonthDate: existing.monthDate) {
                if remoteUpdatedAt > localModDate {
                    repo.updateFromCloud(remote, ckRecordName: recordName)
                } else {
                    repo.markSyncPending(forMonthDate: existing.monthDate)
                }
            } else {
                repo.updateFromCloud(remote, ckRecordName: recordName)
            }
            storeSystemFields(from: ckRecord, table: "Budgets")
            return
        }

        if let local = repo.fetchBudget(byMonthDate: remote.monthDate) {
            repo.setCKRecordId(forMonthDate: remote.monthDate, ckRecordName: recordName)

            let remoteUpdatedAt = remote.updatedAt ?? ckRecord.modificationDate ?? Date.distantPast
            if let localModDate = repo.lastModifiedDate(forMonthDate: local.monthDate) {
                if remoteUpdatedAt > localModDate {
                    repo.updateFromCloud(remote, ckRecordName: recordName)
                } else {
                    repo.markSyncPending(forMonthDate: local.monthDate)
                }
            } else {
                repo.updateFromCloud(remote, ckRecordName: recordName)
            }
            storeSystemFields(from: ckRecord, table: "Budgets")
            return
        }

        // Guard: if a soft-deleted budget with this CK name exists (is_deleted=1),
        // restore its pendingDelete status so it gets removed from CloudKit on the next
        // push, rather than re-inserting and immediately re-deleting it every sync cycle.
        if repo.restorePendingDeleteIfNeeded(ckRecordName: recordName) { return }

        repo.insertFromCloud(remote, ckRecordName: recordName)
        storeSystemFields(from: ckRecord, table: "Budgets")
    }

    // MARK: - Credit Card

    func resolveCreditCard(remote: CreditCard, ckRecord: CKRecord) {
        let repo = CreditCardRepository()
        let recordName = ckRecord.recordID.recordName

        if let existing = repo.fetchCard(byCKRecordName: recordName) {
            let remoteUpdatedAt = remote.updatedAt
            if let localModDate = repo.lastModifiedDate(for: existing.id ?? 0) {
                if remoteUpdatedAt > localModDate {
                    repo.updateFromCloud(remote, ckRecordName: recordName)
                } else {
                    repo.markSyncPending(for: existing.id ?? 0)
                }
            } else {
                repo.updateFromCloud(remote, ckRecordName: recordName)
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
            // Repair stale cross-device creditCardId from a previous failed recovery.
            // If the existing statement references a card with no ck_record_id AND the
            // remote (via remapCrossDeviceIDs) has a different creditCardId, the existing
            // row used the wrong source-device local ID — always accept the remote data
            // to fix the reference and restore correct card linkage.
            let needsCardIdRepair = existing.creditCardId != remote.creditCardId &&
                CreditCardRepository().fetchCKRecordName(for: existing.creditCardId) == nil
            if needsCardIdRepair {
                repo.updateFromCloud(remote, ckRecordName: recordName)
                storeSystemFields(from: ckRecord, table: "CreditCardStatements")
                return
            }

            let remoteUpdatedAt = remote.updatedAt
            if let localModDate = repo.lastModifiedDate(for: existing.id ?? 0) {
                if remoteUpdatedAt > localModDate {
                    repo.updateFromCloud(remote, ckRecordName: recordName)
                } else {
                    repo.markSyncPending(for: existing.id ?? 0)
                }
            } else {
                repo.updateFromCloud(remote, ckRecordName: recordName)
            }
            storeSystemFields(from: ckRecord, table: "CreditCardStatements")
            return
        }

        // Phase 3E: Removed local-ID matching step — with UUID-based CK record names,
        // matching by local auto-increment ID is dangerous (cross-device ID collisions).

        // Guard: if a soft-deleted statement with this CK name exists (is_deleted=1),
        // restore its pendingDelete status so it gets removed from CloudKit on the next
        // push, rather than re-inserting and immediately re-deleting it every sync cycle.
        if repo.restorePendingDeleteIfNeeded(ckRecordName: recordName) { return }

        repo.insertFromCloud(remote, ckRecordName: recordName)
        storeSystemFields(from: ckRecord, table: "CreditCardStatements")
    }

    // MARK: - Budget Allocation

    func resolveBudgetAllocation(remote: BudgetAllocationModel, ckRecord: CKRecord) {
        let repo = BudgetAllocationRepository()
        let recordName = ckRecord.recordID.recordName

        if let existing = repo.fetchAllocation(byCKRecordName: recordName) {
            let remoteUpdatedAt = remote.updatedAt ?? ckRecord.modificationDate ?? Date.distantPast
            if let localModDate = repo.lastModifiedDate(for: existing.id ?? 0) {
                if remoteUpdatedAt > localModDate {
                    repo.updateFromCloud(remote, ckRecordName: recordName)
                } else {
                    repo.markSyncPending(for: existing.id ?? 0)
                }
            } else {
                repo.updateFromCloud(remote, ckRecordName: recordName)
            }
            storeSystemFields(from: ckRecord, table: "BudgetAllocations")
            return
        }

        // Phase 3E: Removed local-ID matching step — with UUID-based CK record names,
        // matching by local auto-increment ID is dangerous (cross-device ID collisions).

        // Guard: if a soft-deleted allocation with this CK name exists (is_deleted=1),
        // restore its pendingDelete status so it gets removed from CloudKit on the next
        // push, rather than re-inserting and immediately re-deleting it every sync cycle.
        if repo.restorePendingDeleteIfNeeded(ckRecordName: recordName) { return }

        repo.insertFromCloud(remote, ckRecordName: recordName)
        storeSystemFields(from: ckRecord, table: "BudgetAllocations")
    }
}
