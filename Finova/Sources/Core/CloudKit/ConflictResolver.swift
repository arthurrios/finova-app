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

    /// The database this resolver applies inbound records to.
    ///
    /// Injectable so a test can stand up two resolvers over two genuinely separate databases —
    /// without this, both "devices" in the cross-device tests resolved into `DBHelper.shared`,
    /// i.e. into each other, which is why those tests could never detect a sync bug.
    private let db: DBHelper

    init(db: DBHelper = .shared) {
        self.db = db
    }

    // MARK: - System Fields Persistence

    /// Encodes a CKRecord's system fields (including recordChangeTag) and persists them
    /// so the next push can use `.ifServerRecordUnchanged` with the correct tag. Also persists
    /// the record's deterministic version (`rev`/`revDevice`) so subsequent conflict decisions
    /// are clock-independent. Called after EVERY inbound apply, so this is the single place that
    /// keeps the local row's version in sync with the server's.
    /// Persists the stable identity and uuid foreign keys an inbound record carries.
    ///
    /// Called alongside `storeSystemFields` on every apply path. Unlike the `*CKRecordName` side
    /// channels these are always present (a uuid exists from row creation), so the relationship
    /// survives even when the referenced row has not arrived yet — `resolveUuidForeignKeys()`
    /// converts it to a local integer on this or a later pass.
    private func storeInboundUuids(from ckRecord: CKRecord, table: String) {
        db.applyInboundUuids(
            table: table,
            ckRecordName: ckRecord.recordID.recordName,
            uuid: ckRecord["uuid"] as? String,
            creditCardUuid: ckRecord["creditCardUuid"] as? String,
            statementUuid: ckRecord["statementUuid"] as? String,
            parentUuid: (ckRecord["parentTransactionUuid"] as? String)
                ?? (ckRecord["parentAllocationUuid"] as? String)
        )
    }

    private func storeSystemFields(from ckRecord: CKRecord, table: String) {
        storeInboundUuids(from: ckRecord, table: table)

        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        ckRecord.encodeSystemFields(with: coder)
        coder.finishEncoding()
        db.saveSystemFields(coder.encodedData, ckRecordName: ckRecord.recordID.recordName, table: table)

        // Persist the incoming version. Only store a real (>0) rev — a record from an older
        // client without a rev leaves the local rev untouched (stays in timestamp-fallback mode).
        if let remoteRev = ckRecord["rev"] as? Int, remoteRev > 0 {
            db.setRev(
                table: table,
                ckRecordName: ckRecord.recordID.recordName,
                rev: remoteRev,
                device: ckRecord["revDevice"] as? String
            )
        }
    }

    /// Deterministic conflict decision: should the REMOTE record be applied over the local row?
    ///
    /// When BOTH sides carry a real version (rev > 0), compares (rev, revDevice) — higher rev
    /// wins, ties broken by a stable device-id string compare. This is clock-independent and
    /// avoids the unreliable `updated_at`/`ck_modified_at` timestamps. When either side lacks a
    /// rev (legacy data, or mid-migration before rev has propagated), falls back to the existing
    /// timestamp last-writer-wins — so behavior is unchanged until rev is present on both sides.
    private func remoteShouldWin(ckRecord: CKRecord, remoteUpdatedAt: Date, localModDate: Date?) -> Bool {
        let remoteRev = ckRecord["rev"] as? Int ?? 0
        let (localRev, localDevice) = db.fetchRevAnyTable(ckRecordName: ckRecord.recordID.recordName)
        if remoteRev > 0 && localRev > 0 {
            if remoteRev != localRev { return remoteRev > localRev }
            let remoteDevice = ckRecord["revDevice"] as? String ?? ""
            return remoteDevice >= (localDevice ?? "")
        }
        // Fallback: timestamp LWW (current behavior). No local basis → cloud wins, as today.
        guard let localModDate = localModDate else { return true }
        return remoteUpdatedAt >= localModDate
    }

    // MARK: - Transaction

    func resolveTransaction(remote: Transaction, ckRecord: CKRecord) {
        let repo = TransactionRepository(db: db)
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
                CreditCardRepository(db: db).fetchCKRecordName(for: existingCCId!) == nil
            if needsCardIdRepair {
                repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
                storeSystemFields(from: ckRecord, table: "Transactions")
                return
            }

            let remoteUpdatedAt = remote.updatedAt ?? ckRecord.modificationDate ?? Date.distantPast
            if let localModDate = repo.lastModifiedDate(for: existing.id ?? 0) {
                if remoteShouldWin(ckRecord: ckRecord, remoteUpdatedAt: remoteUpdatedAt, localModDate: localModDate) {
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
                            if remoteShouldWin(ckRecord: ckRecord, remoteUpdatedAt: remoteUpdatedAt, localModDate: localModDate) {
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
                    // Already linked to a different CK record
                    if existingCKName != recordName {
                        // Group record: re-link local to group-zone CK name and update
                        if sharedGroupId != nil {
                            repo.deleteSoftDeletedByCKRecordName(recordName)
                            repo.overwriteCKRecordId(for: localId, ckRecordName: recordName)
                            repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
                            storeSystemFields(from: ckRecord, table: "Transactions")
                            return
                        }
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
        // Exception: group records (sharedGroupId != nil) bypass this guard because they
        // are expected to have a valid local counterpart synced from the private zone —
        // the group-zone creation date is always recent (when pushed to the group zone)
        // and would incorrectly skip the fuzzy-match that finds the existing local record.
        if sharedGroupId == nil,
           let creationDate = ckRecord.creationDate,
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
                        if remoteShouldWin(ckRecord: ckRecord, remoteUpdatedAt: remoteUpdatedAt, localModDate: localModDate) {
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
                    // Group record: re-link local to group-zone CK name and update
                    if sharedGroupId != nil {
                        repo.deleteSoftDeletedByCKRecordName(recordName)
                        repo.overwriteCKRecordId(for: localId, ckRecordName: recordName)
                        repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
                        storeSystemFields(from: ckRecord, table: "Transactions")
                        return
                    }
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
                    if remoteShouldWin(ckRecord: ckRecord, remoteUpdatedAt: remoteUpdatedAt, localModDate: localModDate) {
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
            // Already linked to a different CK record
            if existingCKName != recordName {
                // Group record: re-link local to group-zone CK name and update
                if sharedGroupId != nil {
                    repo.deleteSoftDeletedByCKRecordName(recordName)
                    repo.overwriteCKRecordId(for: localId, ckRecordName: recordName)
                    repo.updateFromCloud(remote, ckRecordName: recordName, sharedGroupId: sharedGroupId)
                    storeSystemFields(from: ckRecord, table: "Transactions")
                    return
                }
                return
            }
        }

        // Guard: if a soft-deleted record exists with this CK name, restore its pendingDelete
        // status instead of re-inserting. This prevents resurrection of records the user
        // deleted locally before the CK delete was pushed (e.g. during a reset sync).
        // Exception: group records — a soft-deleted row with the group CK name is a stale
        // duplicate from a previous sync. Hard-delete it and fall through to fresh insert.
        if sharedGroupId != nil {
            repo.deleteSoftDeletedByCKRecordName(recordName)
        } else {
            if repo.restorePendingDeleteIfNeeded(ckRecordName: recordName) { return }
        }

        // Phase 4C: Pass parentCKRecordName so insertFromCloud can remap parent ID
        repo.insertFromCloud(remote, ckRecordName: recordName, parentCKRecordName: parentCKRecordName, sharedGroupId: sharedGroupId)
        storeSystemFields(from: ckRecord, table: "Transactions")
    }

    // MARK: - Budget

    func resolveBudget(remote: BudgetModel, ckRecord: CKRecord) {
        let repo = BudgetRepository(db: db)
        let recordName = ckRecord.recordID.recordName

        if let existing = repo.fetchBudget(byCKRecordName: recordName) {
            let remoteUpdatedAt = remote.updatedAt ?? ckRecord.modificationDate ?? Date.distantPast
            if let localModDate = repo.lastModifiedDate(forMonthDate: existing.monthDate) {
                if remoteShouldWin(ckRecord: ckRecord, remoteUpdatedAt: remoteUpdatedAt, localModDate: localModDate) {
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
                if remoteShouldWin(ckRecord: ckRecord, remoteUpdatedAt: remoteUpdatedAt, localModDate: localModDate) {
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
        let repo = CreditCardRepository(db: db)
        let recordName = ckRecord.recordID.recordName

        if let existing = repo.fetchCard(byCKRecordName: recordName) {
            let remoteUpdatedAt = remote.updatedAt
            if let localModDate = repo.lastModifiedDate(for: existing.id ?? 0) {
                if remoteShouldWin(ckRecord: ckRecord, remoteUpdatedAt: remoteUpdatedAt, localModDate: localModDate) {
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
        let repo = StatementRepository(db: db)
        let recordName = ckRecord.recordID.recordName

        if let existing = repo.fetchStatement(byCKRecordName: recordName) {
            // Repair stale cross-device creditCardId from a previous failed recovery.
            // If the existing statement references a card with no ck_record_id AND the
            // remote (via remapCrossDeviceIDs) has a different creditCardId, the existing
            // row used the wrong source-device local ID — always accept the remote data
            // to fix the reference and restore correct card linkage.
            let needsCardIdRepair = existing.creditCardId != remote.creditCardId &&
                CreditCardRepository(db: db).fetchCKRecordName(for: existing.creditCardId) == nil
            if needsCardIdRepair {
                repo.updateFromCloud(remote, ckRecordName: recordName)
                storeSystemFields(from: ckRecord, table: "CreditCardStatements")
                return
            }

            let remoteUpdatedAt = remote.updatedAt
            if let localModDate = repo.lastModifiedDate(for: existing.id ?? 0) {
                if remoteShouldWin(ckRecord: ckRecord, remoteUpdatedAt: remoteUpdatedAt, localModDate: localModDate) {
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

        // Step 2: Match by creditCardId + closingDate (prevents cross-device duplicates)
        if let existingId = repo.findStatement(
            creditCardId: remote.creditCardId, closingDate: remote.closingDate
        ) {
            let existingCKName = repo.fetchCKRecordName(for: existingId)
            if existingCKName == nil {
                // Unsynced local statement — link to this CK record and update
                repo.setCKRecordId(for: existingId, ckRecordName: recordName)
                let remoteUpdatedAt = remote.updatedAt
                if let localModDate = repo.lastModifiedDate(for: existingId) {
                    if remoteShouldWin(ckRecord: ckRecord, remoteUpdatedAt: remoteUpdatedAt, localModDate: localModDate) {
                        repo.updateFromCloud(remote, ckRecordName: recordName)
                    } else {
                        repo.markSyncPending(for: existingId)
                    }
                } else {
                    repo.updateFromCloud(remote, ckRecordName: recordName)
                }
                storeSystemFields(from: ckRecord, table: "CreditCardStatements")
                return
            }
            // Already linked to a different CK record — same card+period exists, skip duplicate
            if existingCKName != recordName {
                storeSystemFields(from: ckRecord, table: "CreditCardStatements")
                return
            }
        }

        // Guard: if a soft-deleted statement with this CK name exists (is_deleted=1),
        // restore its pendingDelete status so it gets removed from CloudKit on the next
        // push, rather than re-inserting and immediately re-deleting it every sync cycle.
        if repo.restorePendingDeleteIfNeeded(ckRecordName: recordName) { return }

        repo.insertFromCloud(remote, ckRecordName: recordName)
        storeSystemFields(from: ckRecord, table: "CreditCardStatements")
    }

    // MARK: - Budget Allocation

    func resolveBudgetAllocation(remote: BudgetAllocationModel, ckRecord: CKRecord) {
        let repo = BudgetAllocationRepository(db: db)
        let recordName = ckRecord.recordID.recordName

        if let existing = repo.fetchAllocation(byCKRecordName: recordName) {
            let remoteUpdatedAt = remote.updatedAt ?? ckRecord.modificationDate ?? Date.distantPast
            if let localModDate = repo.lastModifiedDate(for: existing.id ?? 0) {
                if remoteShouldWin(ckRecord: ckRecord, remoteUpdatedAt: remoteUpdatedAt, localModDate: localModDate) {
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

        // Natural-key deduplication: check if an allocation with the same month_date +
        // category_key + shared_group_id already exists locally (unsynced or with a different
        // CK record name). This prevents duplicates when the same allocation is created on
        // two devices before the first sync merges them.
        if let localMatch = repo.fetchAllocation(byMonthDate: remote.monthDate, categoryKey: remote.categoryKey, sharedGroupId: remote.sharedGroupId) {
            let remoteUpdatedAt = remote.updatedAt ?? ckRecord.modificationDate ?? Date.distantPast
            if let localModDate = repo.lastModifiedDate(for: localMatch.id ?? 0) {
                if remoteShouldWin(ckRecord: ckRecord, remoteUpdatedAt: remoteUpdatedAt, localModDate: localModDate) {
                    repo.updateFromCloud(remote, localId: localMatch.id ?? 0, ckRecordName: recordName)
                } else {
                    repo.linkCKRecordName(recordName, toLocalId: localMatch.id ?? 0)
                }
            } else {
                repo.updateFromCloud(remote, localId: localMatch.id ?? 0, ckRecordName: recordName)
            }
            storeSystemFields(from: ckRecord, table: "BudgetAllocations")
            return
        }

        repo.insertFromCloud(remote, ckRecordName: recordName)
        storeSystemFields(from: ckRecord, table: "BudgetAllocations")
    }
}
