//
//  PostSyncActions.swift
//  Finova
//
//  Created by Arthur Rios on 14/02/26.
//

import CloudKit
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

        group.enter()
        Self.recoverMissingBudgets {
            group.leave()
        }

        group.notify(queue: DispatchQueue(label: "com.finova.postsync")) {
            // Destructive CC repairs may run ONLY on a device that both (a) originally held the
            // buggy data AND (b) has completed a verified full pull — the same gate
            // DashboardViewModel already applies. The original-device flag alone is unreliable: a
            // second device flips it true after its first large push (SyncEngine sets it whenever
            // totalRecords > batchSize), at which point a half-hydrated device would "repair" clean
            // cloud data and push the damage back up.
            let isOriginalDevice = UserDefaults.standard.bool(forKey: "hasCompletedInitialCloudPush_v1")
            let hydrated = UserDefaults.standard.bool(forKey: "syncFullPullVerified_v2")
            if isOriginalDevice && hydrated {
                Self.repairCreditCardDataIntegrity()
            } else {
                logWarning("[PostSync] Skipping repairCreditCardDataIntegrity — originalDevice=\(isOriginalDevice), hydrated=\(hydrated)")
            }

            // Fix 2b: Ensure owner pushes personal offset to group zone after sync.
            // Covers the case where offset was set before the group existed.
            if MirrorModeManager.shared.isEnabled,
               let groupId = MirrorModeManager.shared.linkedGroupId {
                let offsetManager = UIDUserDefaultsManager.shared
                let offset = offsetManager.getCurrentUserBalanceOffset()
                if offset != 0 {
                    let groupRepo = BudgetGroupRepository()
                    if let linkedGroup = groupRepo.fetchGroup(byId: groupId), linkedGroup.isOwner {
                        let groupOffset = offsetManager.getGroupBalanceOffset(groupId: groupId)
                        if groupOffset != offset {
                            logWarning("[PostSync] Owner offset mismatch — pushing personal (\(offset)) to group zone (was \(groupOffset))")
                            offsetManager.setGroupBalanceOffset(offset, groupId: groupId)
                        }
                    }
                }
            }

            completion()
        }
    }

    /// Recovers budgets from CloudKit if they're completely missing locally.
    /// Searches both the private zone and all group zones (mirror mode pushes to group zones).
    private static func recoverMissingBudgets(completion: @escaping () -> Void) {
        let db = DBHelper.shared
        let budgetCount = db.fetchSingleInt("SELECT COUNT(*) FROM Budgets;") ?? 0
        let allocCount = db.fetchSingleInt(
            "SELECT COUNT(*) FROM BudgetAllocations WHERE (is_deleted IS NULL OR is_deleted = 0);"
        ) ?? 0

        guard budgetCount == 0 && allocCount > 0 else {
            completion()
            return
        }

        logWarning("[BudgetRecovery] 0 budgets but \(allocCount) allocations — fetching budgets from CloudKit")

        let dispatchGroup = DispatchGroup()
        var totalRecovered = 0

        // Collect all zones to search: private zone + all group zones
        var zonesToSearch: [CKRecordZone.ID] = [CloudKitManager.privateZoneID]
        let groups = BudgetGroupRepository().fetchAllGroups()
        for group in groups {
            let zoneID = CKRecordZone.ID(
                zoneName: "Group-\(group.id)",
                ownerName: group.isOwner ? CKCurrentUserDefaultName : (group.ckZoneOwner ?? CKCurrentUserDefaultName)
            )
            zonesToSearch.append(zoneID)
        }

        logWarning("[BudgetRecovery] Searching \(zonesToSearch.count) zone(s): \(zonesToSearch.map { $0.zoneName })")

        for zoneID in zonesToSearch {
            dispatchGroup.enter()
            let query = CKQuery(recordType: "Budget", predicate: NSPredicate(value: true))
            let operation = CKQueryOperation(query: query)
            operation.zoneID = zoneID
            operation.qualityOfService = .userInitiated

            var zoneCount = 0

            operation.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record):
                    guard let budget = BudgetModel.fromCKRecord(record) else { return }
                    ConflictResolver.shared.resolveBudget(remote: budget, ckRecord: record)
                    zoneCount += 1
                case .failure(let error):
                    logError("[BudgetRecovery] Record fetch error in \(zoneID.zoneName): \(error)")
                }
            }

            operation.queryCompletionBlock = { _, error in
                if let error = error {
                    logError("[BudgetRecovery] Query failed for \(zoneID.zoneName): \(error)")
                } else if zoneCount > 0 {
                    logWarning("[BudgetRecovery] Found \(zoneCount) budget(s) in \(zoneID.zoneName)")
                }
                totalRecovered += zoneCount
                dispatchGroup.leave()
            }

            // Use private DB for private zone and owner group zones, shared DB for member zones
            let isSharedZone = groups.contains(where: { !$0.isOwner && "Group-\($0.id)" == zoneID.zoneName })
            let database = isSharedZone ? CloudKitManager.shared.sharedDatabase : CloudKitManager.shared.privateDatabase
            database.add(operation)
        }

        dispatchGroup.notify(queue: .global(qos: .userInitiated)) {
            logWarning("[BudgetRecovery] Recovery complete — \(totalRecovered) budget(s) total")
            completion()
        }
    }

    /// Comprehensive credit card data integrity repair that runs after every sync.
    /// 1. Fixes orphaned creditCardId on statements and transactions (card ID changed after recovery)
    /// 2. Deletes orphaned statements that can't be fixed
    /// 3. Recreates missing statements from transactions
    private static func repairCreditCardDataIntegrity() {
        guard let userId = UIDUserDefaultsManager.shared.currentUserUID else {
            logWarning("[CCRepair] No current user UID — skipping repair")
            return
        }
        TransactionRepository.invalidateCache()

        let cardRepo = CreditCardRepository()
        let stmtRepo = StatementRepository()
        let txRepo = TransactionRepository()
        let db = DBHelper.shared

        let cards = cardRepo.fetchAllCards(userId: userId)
        logWarning("[CCRepair] Starting repair — \(cards.count) card(s) found for user")

        // Safety: skip repair when no cards exist locally — this likely means
        // credit cards haven't been resolved yet (e.g., fresh sync, recovery sync,
        // or cards live in a group zone). Running repair here would destructively
        // delete valid statements and orphan transactions.
        if cards.isEmpty {
            logWarning("[CCRepair] No local cards — skipping repair to avoid data loss")
            return
        }

        // === Step 1: Fix orphaned creditCardId references ===
        var didRepairOrphans = false

        // Find statements whose credit_card_id doesn't match any existing card
        let orphanedStmts = db.fetchIntIntPairs(
            """
            SELECT s.id, s.credit_card_id FROM CreditCardStatements s
            LEFT JOIN CreditCards c ON s.credit_card_id = c.id
            WHERE c.id IS NULL AND s.credit_card_id > 0;
            """
        )

        // Find transactions whose credit_card_id doesn't match any existing card
        let orphanedTxCards = db.fetchIntIntPairs(
            """
            SELECT t.id, t.credit_card_id FROM Transactions t
            LEFT JOIN CreditCards c ON t.credit_card_id = c.id
            WHERE c.id IS NULL AND t.credit_card_id IS NOT NULL AND t.credit_card_id > 0
              AND (t.is_deleted IS NULL OR t.is_deleted = 0);
            """
        )

        if !orphanedStmts.isEmpty || !orphanedTxCards.isEmpty {
            didRepairOrphans = true
            logWarning("[CCRepair] Found \(orphanedStmts.count) orphaned statement(s), \(orphanedTxCards.count) orphaned transaction(s)")

            // Build old→new card ID map from recovery (persisted in UserDefaults)
            var cardIdMap: [Int: Int] = [:]
            if let stored = UserDefaults.standard.dictionary(forKey: "recoveryCardIdMap") as? [String: Int] {
                for (key, value) in stored {
                    if let oldId = Int(key) {
                        cardIdMap[oldId] = value
                    }
                }
                logWarning("[CCRepair] Loaded persisted cardIdMap: \(cardIdMap)")
            }

            // Fallback: if no recovery map or map doesn't cover all orphaned IDs,
            // and user has exactly one card, map all orphaned refs to that card
            let orphanedCardIds = Set(orphanedStmts.map { $0.1 } + orphanedTxCards.map { $0.1 })
            let unmappedIds = orphanedCardIds.filter { cardIdMap[$0] == nil }
            if !unmappedIds.isEmpty && cards.count == 1, let singleCard = cards.first, let cardId = singleCard.id {
                logWarning("[CCRepair] Single-card fallback: mapping \(unmappedIds) → card \(cardId) (\(singleCard.name))")
                for oldId in unmappedIds {
                    cardIdMap[oldId] = cardId
                }
            } else if !unmappedIds.isEmpty && cards.count > 1 {
                logWarning("[CCRepair] Multiple cards, \(unmappedIds.count) unmapped orphaned ID(s): \(unmappedIds) — cards: \(cards.map { "id=\($0.id ?? -1) name=\($0.name)" })")
                // Pick the card with the most existing transactions — most likely the correct one
                let cardTxCounts = cards.compactMap { card -> (CreditCard, Int)? in
                    guard let cId = card.id else { return nil }
                    let count = txRepo.fetchAllTransactions().filter { $0.creditCardId == cId }.count
                    return (card, count)
                }.sorted { $0.1 > $1.1 }

                if let (bestCard, bestCount) = cardTxCounts.first, let cardId = bestCard.id {
                    logWarning("[CCRepair] Best-match fallback: mapping \(unmappedIds) → card \(cardId) (\(bestCard.name)) with \(bestCount) existing tx(s)")
                    for oldId in unmappedIds {
                        cardIdMap[oldId] = cardId
                    }
                }
            }

            // Fix orphaned statements
            for (stmtId, oldCardId) in orphanedStmts {
                if let newCardId = cardIdMap[oldCardId] {
                    db.executeSyncUpdate(
                        "UPDATE CreditCardStatements SET credit_card_id = ?, sync_status = 'pending' WHERE id = ?;",
                        intBindings: [newCardId, stmtId]
                    )
                    logWarning("[CCRepair] Fixed statement \(stmtId): creditCardId \(oldCardId) → \(newCardId)")
                } else {
                    // Can't fix — delete the orphaned statement
                    logWarning("[CCRepair] Deleting unfixable orphaned statement \(stmtId) (creditCardId=\(oldCardId))")
                    db.executeSyncUpdate(
                        "DELETE FROM CreditCardStatements WHERE id = ?;",
                        intBindings: [stmtId]
                    )
                }
            }

            // Fix orphaned transactions
            for (txId, oldCardId) in orphanedTxCards {
                if let newCardId = cardIdMap[oldCardId] {
                    db.executeSyncUpdate(
                        "UPDATE Transactions SET credit_card_id = ?, statement_id = NULL, sync_status = 'pending' WHERE id = ?;",
                        intBindings: [newCardId, txId]
                    )
                    logWarning("[CCRepair] Fixed transaction \(txId): creditCardId \(oldCardId) → \(newCardId)")
                } else {
                    logWarning("[CCRepair] Cannot fix transaction \(txId) (orphaned creditCardId=\(oldCardId)) — no mapping available")
                }
            }

            TransactionRepository.invalidateCache()
        } else {
            logWarning("[CCRepair] No orphaned card references found")
        }

        // === Step 1a: Fix transactions whose statementId points to a non-existent statement ===
        // Runs INDEPENDENTLY of the card-reference repair above. It used to be nested inside that
        // `if`, so it was skipped exactly when card references were healthy — which is the common
        // case. One account sat on 123 credit-card transactions pointing at deleted statements while
        // the log cheerfully reported "No orphaned card references found" on every single sync.
        let orphanedTxStmts = db.fetchIntIntPairs(
            """
            SELECT t.id, t.statement_id FROM Transactions t
            LEFT JOIN CreditCardStatements s ON t.statement_id = s.id
            WHERE s.id IS NULL AND t.statement_id IS NOT NULL AND t.statement_id > 0
              AND (t.is_deleted IS NULL OR t.is_deleted = 0);
            """
        )
        if !orphanedTxStmts.isEmpty {
            logWarning("[CCRepair] Found \(orphanedTxStmts.count) transaction(s) with orphaned statementId — clearing for re-creation")
            for (txId, oldStmtId) in orphanedTxStmts {
                db.executeSyncUpdate(
                    "UPDATE Transactions SET statement_id = NULL, sync_status = 'pending' WHERE id = ?;",
                    intBindings: [txId]
                )
                logWarning("[CCRepair] Cleared statementId \(oldStmtId) on transaction \(txId)")
            }
            didRepairOrphans = true
            TransactionRepository.invalidateCache()
        }

        // === Step 1b: One-time consolidation of CC transactions to correct card ===
        consolidateCreditCardTransactions(cards: cards, txRepo: txRepo, db: db)

        // === Step 1c: REMOVED from the sync path ===
        // `mergeDuplicateStatements` ran on every single sync with no gate, chose its survivor by
        // *local row id* — which is device-specific, so two devices pick opposite winners — and
        // then deleted the loser from CloudKit and re-parented its transactions as 'pending'. Two
        // devices therefore deleted each other's statements in a loop, forever.
        //
        // Genuine duplicate statements still need merging, but it must be a deliberate, hydrated,
        // identity-keyed operation, not something that fires after every pull.

        // === Step 2: Repair orphaned CC transactions (only if orphans exist) ===
        // Only run if there are CC transactions without a statementId — these are genuinely orphaned.
        // Do NOT run reassignMisplacedTransactions every sync — it's an expensive operation
        // that can flip transactions between duplicate statements, causing endless re-uploads.
        let service = CreditCardService()
        service.repairOrphanedCreditCardTransactions(userId: userId, transactionRepo: txRepo)

        // === Step 3: Mirror mode re-reconciliation ===
        // Only run if Step 1 actually fixed orphaned records (otherwise nothing changed).
        if MirrorModeManager.shared.isEnabled && didRepairOrphans {
            logWarning("[CCRepair] Mirror mode active — running post-repair reconciliation")
            MirrorModeManager.shared.reconcileMirrorData()
        }

        // === Step 4: Summary log ===
        TransactionRepository.invalidateCache()
        let personalCount = txRepo.fetchAllTransactions().count
        let groupTaggedCount = db.fetchSingleInt(
            "SELECT COUNT(*) FROM Transactions WHERE shared_group_id IS NOT NULL AND shared_group_id != '' AND (is_deleted IS NULL OR is_deleted = 0);"
        ) ?? 0
        let untaggedForUser = db.fetchSingleInt(
            "SELECT COUNT(*) FROM Transactions WHERE user_id = ? AND (shared_group_id IS NULL OR shared_group_id = '') AND (is_deleted IS NULL OR is_deleted = 0);",
            textBinding: userId
        ) ?? 0
        logWarning("[CCRepair] Transaction summary: personal=\(personalCount), groupTagged=\(groupTaggedCount), untaggedForUser=\(untaggedForUser)")

        // Budget diagnostics
        let budgetCount = db.fetchSingleInt(
            "SELECT COUNT(*) FROM Budgets WHERE user_id = ? AND (is_deleted IS NULL OR is_deleted = 0);",
            textBinding: userId
        ) ?? -1
        let budgetDeleted = db.fetchSingleInt(
            "SELECT COUNT(*) FROM Budgets WHERE user_id = ? AND is_deleted = 1;",
            textBinding: userId
        ) ?? -1
        let budgetTotal = db.fetchSingleInt("SELECT COUNT(*) FROM Budgets;") ?? -1
        let allocCount = db.fetchSingleInt(
            "SELECT COUNT(*) FROM BudgetAllocations WHERE user_id = ? AND (is_deleted IS NULL OR is_deleted = 0);",
            textBinding: userId
        ) ?? -1
        logWarning("[CCRepair] Budgets: active=\(budgetCount), deleted=\(budgetDeleted), totalRows=\(budgetTotal), allocations=\(allocCount)")

        for card in cards {
            guard let cardId = card.id else { continue }
            let stmts = stmtRepo.fetchStatements(forCardId: cardId)
            let txCount = txRepo.fetchAllTransactions().filter { $0.creditCardId == cardId }.count
            logWarning("[CCRepair] Card '\(card.name)' (id=\(cardId)): \(stmts.count) statement(s), \(txCount) transaction(s)")
        }

        // Clean up persisted map after successful repair
        UserDefaults.standard.removeObject(forKey: "recoveryCardIdMap")

        // === Step 5: Balance diagnostics ===
        logBalanceDiagnostics(userId: userId, txRepo: txRepo, db: db)
    }

    /// One-time fix: if CC transactions got split across multiple cards due to
    /// a sync remapping bug, consolidate them all onto the card with the most
    /// transactions (the card the user was actually using).
    private static func consolidateCreditCardTransactions(cards: [CreditCard], txRepo: TransactionRepository, db: DBHelper) {
        let consolidateKey = "hasConsolidatedCCTransactions_v1"
        guard !UserDefaults.standard.bool(forKey: consolidateKey) else { return }
        guard cards.count > 1 else {
            UserDefaults.standard.set(true, forKey: consolidateKey)
            return
        }

        TransactionRepository.invalidateCache()
        let allTx = txRepo.fetchAllTransactions()

        // Count CC transactions per card
        var txCountByCard: [(card: CreditCard, count: Int)] = []
        for card in cards {
            guard let cardId = card.id else { continue }
            let count = allTx.filter { $0.creditCardId == cardId && $0.isCreditCardStatement != true }.count
            txCountByCard.append((card, count))
        }
        txCountByCard.sort { $0.count > $1.count }

        guard let primary = txCountByCard.first, let primaryId = primary.card.id else {
            UserDefaults.standard.set(true, forKey: consolidateKey)
            return
        }

        // Check if other cards have CC transactions that should be on the primary
        let otherCards = txCountByCard.dropFirst().filter { $0.count > 0 }
        guard !otherCards.isEmpty else {
            logWarning("[CCRepair] Consolidation: all CC transactions already on '\(primary.card.name)' — no action needed")
            UserDefaults.standard.set(true, forKey: consolidateKey)
            return
        }

        logWarning("[CCRepair] Consolidation: moving CC transactions to '\(primary.card.name)' (id=\(primaryId), \(primary.count) tx)")
        for other in otherCards {
            guard let otherId = other.card.id else { continue }
            logWarning("[CCRepair] Consolidation: '\(other.card.name)' (id=\(otherId)) has \(other.count) tx → moving to '\(primary.card.name)'")

            // Move transactions: update creditCardId, clear statementId for reassignment
            db.executeSyncUpdate(
                "UPDATE Transactions SET credit_card_id = ?, statement_id = NULL, sync_status = 'pending' WHERE credit_card_id = ? AND (is_deleted IS NULL OR is_deleted = 0) AND (is_credit_card_statement IS NULL OR is_credit_card_statement = 0);",
                intBindings: [primaryId, otherId]
            )

            // Move statements to primary card
            db.executeSyncUpdate(
                "UPDATE CreditCardStatements SET credit_card_id = ?, sync_status = 'pending' WHERE credit_card_id = ?;",
                intBindings: [primaryId, otherId]
            )
        }

        TransactionRepository.invalidateCache()
        logWarning("[CCRepair] Consolidation complete — all CC transactions now on '\(primary.card.name)'")
        UserDefaults.standard.set(true, forKey: consolidateKey)
    }

    /// Merges duplicate statements that share the same creditCardId + closingDate.
    /// Picks the one with a CK record name as the "winner" (or the oldest by id).
    /// Reassigns all transactions from losers to the winner and deletes the losers.
    private static func mergeDuplicateStatements(cards: [CreditCard], stmtRepo: StatementRepository, db: DBHelper) {
        var totalMerged = 0

        for card in cards {
            guard let cardId = card.id else { continue }
            let statements = stmtRepo.fetchStatements(forCardId: cardId)
            guard statements.count > 1 else { continue }

            // Group by closingDate timestamp
            var byClosingDate: [Int: [CreditCardStatement]] = [:]
            for stmt in statements {
                let key = Int(stmt.closingDate.timeIntervalSince1970)
                byClosingDate[key, default: []].append(stmt)
            }

            for (_, group) in byClosingDate where group.count > 1 {
                // Pick winner: prefer the one with a CK record name, then lowest id
                let sorted = group.sorted { a, b in
                    let aHasCK = stmtRepo.fetchCKRecordName(for: a.id ?? 0) != nil
                    let bHasCK = stmtRepo.fetchCKRecordName(for: b.id ?? 0) != nil
                    if aHasCK != bHasCK { return aHasCK }
                    return (a.id ?? 0) < (b.id ?? 0)
                }

                guard let winner = sorted.first, let winnerId = winner.id else { continue }
                let losers = sorted.dropFirst()

                for loser in losers {
                    guard let loserId = loser.id else { continue }
                    logWarning("[CCRepair] Merging duplicate statement \(loserId) into \(winnerId) (card=\(cardId))")

                    // Reassign transactions from loser to winner
                    db.executeSyncUpdate(
                        "UPDATE Transactions SET statement_id = ?, sync_status = 'pending' WHERE statement_id = ? AND (is_deleted IS NULL OR is_deleted = 0);",
                        intBindings: [winnerId, loserId]
                    )

                    // Delete the loser statement
                    let loserCKName = stmtRepo.fetchCKRecordName(for: loserId)
                    if loserCKName != nil {
                        db.executeSyncUpdate(
                            "UPDATE CreditCardStatements SET is_deleted = 1, sync_status = 'pendingDelete' WHERE id = ?;",
                            intBindings: [loserId]
                        )
                    } else {
                        db.executeSyncUpdate(
                            "DELETE FROM CreditCardStatements WHERE id = ?;",
                            intBindings: [loserId]
                        )
                    }

                    totalMerged += 1
                }

                // Recalculate the winner's total
                stmtRepo.recalculateTotal(statementId: winnerId)
            }
        }

        if totalMerged > 0 {
            TransactionRepository.invalidateCache()
            logWarning("[CCRepair] Merged \(totalMerged) duplicate statement(s)")
        }
    }

    private static func logBalanceDiagnostics(userId: String, txRepo: TransactionRepository, db: DBHelper) {
        let offset = UIDUserDefaultsManager.shared.getCurrentUserBalanceOffset()
        let allTx = txRepo.fetchAllTransactions()

        // Cash transactions only (exclude CC-linked, include CC statement payments)
        let cashTx = allTx.filter { $0.creditCardId == nil || $0.isCreditCardStatement == true }
        let totalIncome = cashTx.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let totalExpense = cashTx.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let netBalance = offset + totalIncome - totalExpense

        logWarning("[BalanceDiff] offset=\(offset), income=\(totalIncome), expense=\(totalExpense), net=\(netBalance), totalTx=\(allTx.count), cashTx=\(cashTx.count)")

        // Group balance if mirror mode
        if MirrorModeManager.shared.isEnabled,
           let groupId = MirrorModeManager.shared.linkedGroupId {
            let groupOffset = UIDUserDefaultsManager.shared.getGroupBalanceOffset(groupId: groupId)
            let groupTx = txRepo.fetchTransactionsForGroup(groupId: groupId)
            let groupCash = groupTx.filter { $0.creditCardId == nil || $0.isCreditCardStatement == true }
            let groupIncome = groupCash.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            let groupExpense = groupCash.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
            let groupNet = groupOffset + groupIncome - groupExpense
            logWarning("[BalanceDiff] GROUP: offset=\(groupOffset), income=\(groupIncome), expense=\(groupExpense), net=\(groupNet), totalTx=\(groupTx.count), cashTx=\(groupCash.count)")
            if netBalance != groupNet {
                logWarning("[BalanceDiff] MISMATCH: personal=\(netBalance) vs group=\(groupNet), diff=\(netBalance - groupNet)")
            }
        }
    }
}
