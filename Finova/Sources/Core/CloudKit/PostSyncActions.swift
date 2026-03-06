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
            Self.repairCreditCardDataIntegrity()
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

        // === Step 1: Fix orphaned creditCardId references ===
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
                // Try to match by finding the card whose CK record's localId matches
                // For each existing card, check its ck_record_id in CK (not available locally).
                // As a last resort, pick the first card for all unmapped refs.
                if let firstCard = cards.first, let cardId = firstCard.id {
                    logWarning("[CCRepair] Last-resort fallback: mapping \(unmappedIds) → first card \(cardId) (\(firstCard.name))")
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

            // Also fix transactions whose statementId points to a non-existent statement
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
            }

            TransactionRepository.invalidateCache()
        } else {
            logWarning("[CCRepair] No orphaned card references found")
        }

        // === Step 2: Recreate missing statements ===
        // Reassign transactions to correct statements based on card billing cycle
        let service = CreditCardService()
        service.reassignMisplacedTransactions(userId: userId, transactionRepo: txRepo)
        service.repairOrphanedCreditCardTransactions(userId: userId, transactionRepo: txRepo)

        // === Step 3: Mirror mode re-reconciliation ===
        // CCRepair may have modified transactions after the main reconciliation ran.
        // Re-tag any un-tagged personal transactions so the group view stays in sync.
        if MirrorModeManager.shared.isEnabled {
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

        for card in cards {
            guard let cardId = card.id else { continue }
            let stmts = stmtRepo.fetchStatements(forCardId: cardId)
            let txCount = txRepo.fetchAllTransactions().filter { $0.creditCardId == cardId }.count
            logWarning("[CCRepair] Card '\(card.name)' (id=\(cardId)): \(stmts.count) statement(s), \(txCount) transaction(s)")
        }

        // Clean up persisted map after successful repair
        UserDefaults.standard.removeObject(forKey: "recoveryCardIdMap")
    }
}
