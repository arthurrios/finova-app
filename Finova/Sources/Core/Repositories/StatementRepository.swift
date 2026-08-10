//
//  StatementRepository.swift
//  Finova
//

import Foundation

class StatementRepository {

    /// Injectable for two-device tests; production always uses `.shared`.
    private let db: DBHelper

    init(db: DBHelper = .shared) { self.db = db }

    func insertStatement(_ stmt: CreditCardStatement) -> Int? {
        do {
            let id = try db.insertStatement(
                creditCardId: stmt.creditCardId,
                closingDate: Int(stmt.closingDate.timeIntervalSince1970),
                dueDate: Int(stmt.dueDate.timeIntervalSince1970),
                totalAmount: stmt.totalAmount,
                userId: stmt.userId
            )
            if id > 0 {
                db.executeSyncUpdate(
                    "UPDATE CreditCardStatements SET sync_status = 'pending' WHERE id = ?;",
                    intBindings: [id]
                )
                NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
            }
            return id > 0 ? id : nil
        } catch {
            logError("Failed to insert statement: \(error)")
            return nil
        }
    }

    func fetchStatements(forCardId cardId: Int) -> [CreditCardStatement] {
        do {
            let rows = try db.getStatements(creditCardId: cardId)
            return rows.map { row in
                var stmt = CreditCardStatement(
                    id: row.id,
                    creditCardId: row.creditCardId,
                    closingDate: Date(timeIntervalSince1970: TimeInterval(row.closingDate)),
                    dueDate: Date(timeIntervalSince1970: TimeInterval(row.dueDate)),
                    totalAmount: row.totalAmount,
                    isPaid: row.isPaid,
                    paidDate: row.paidDate.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    paidAmount: row.paidAmount,
                    isDatesOverridden: row.isDatesOverridden,
                    userId: row.userId,
                    createdAt: Date(timeIntervalSince1970: TimeInterval(row.createdAt)),
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt))
                )
                // Carry record ownership through to the push path — see getStatements.
                stmt.createdByUid = row.createdByUid
                return stmt
            }
        } catch {
            logError("Failed to fetch statements: \(error)")
            return []
        }
    }

    func findStatement(creditCardId: Int, closingDate: Date) -> Int? {
        do {
            return try db.findStatement(
                creditCardId: creditCardId,
                closingDate: Int(closingDate.timeIntervalSince1970)
            )
        } catch {
            logError("Failed to find statement: \(error)")
            return nil
        }
    }

    func deleteStatement(statementId: Int) -> Bool {
        let ckName = fetchCKRecordName(for: statementId)
        if ckName != nil {
            db.executeSyncUpdate(
                "UPDATE CreditCardStatements SET is_deleted = 1, sync_status = 'pendingDelete' WHERE id = ?;",
                intBindings: [statementId]
            )
        } else {
            do {
                try db.deleteStatement(statementId: statementId)
            } catch {
                logError("Failed to delete statement: \(error)")
                return false
            }
        }
        // Cancel the statement's due/pay reminders — otherwise they keep firing for a
        // statement that no longer exists.
        StatementNotificationManager.shared.cancelNotifications(for: statementId)
        NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
        return true
    }

    func recalculateTotal(statementId: Int) {
        do {
            let total = try db.getTransactionSumForStatement(statementId: statementId)
            try db.updateStatementTotal(statementId: statementId, totalAmount: total)
            db.executeSyncUpdate(
                "UPDATE CreditCardStatements SET sync_status = 'pending' WHERE id = ?;",
                intBindings: [statementId]
            )
            // Also update the corresponding statement Transaction row so the Dashboard
            // reflects the new total (its amount comes from Transaction.amount).
            db.executeSyncUpdate(
                """
                UPDATE Transactions SET amount = ?, original_amount = ?, sync_status = 'pending',
                       ck_modified_at = ? WHERE statement_id = ? AND is_credit_card_statement = 1
                       AND (is_deleted IS NULL OR is_deleted = 0);
                """,
                intBindings: [total, total, Int(Date().timeIntervalSince1970), statementId]
            )
            TransactionRepository.invalidateCache()
            NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
        } catch {
            logError("Failed to recalculate statement total: \(error)")
        }
    }

    func updateDates(statementId: Int, closingDate: Date, dueDate: Date, isDatesOverridden: Bool = false) -> Bool {
        do {
            try db.updateStatementDates(
                statementId: statementId,
                closingDate: Int(closingDate.timeIntervalSince1970),
                dueDate: Int(dueDate.timeIntervalSince1970),
                isDatesOverridden: isDatesOverridden
            )
            db.executeSyncUpdate(
                "UPDATE CreditCardStatements SET sync_status = 'pending' WHERE id = ?;",
                intBindings: [statementId]
            )
            NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
            return true
        } catch {
            logError("Failed to update statement dates: \(error)")
            return false
        }
    }

    func markAsPaid(statementId: Int, paidAmount: Int?, paidDate: Date) -> Bool {
        do {
            try db.markStatementAsPaid(
                statementId: statementId,
                paidAmount: paidAmount,
                paidDate: Int(paidDate.timeIntervalSince1970)
            )
            db.executeSyncUpdate(
                "UPDATE CreditCardStatements SET sync_status = 'pending' WHERE id = ?;",
                intBindings: [statementId]
            )
            NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
            return true
        } catch {
            logError("Failed to mark statement as paid: \(error)")
            return false
        }
    }

    /// Reopens a paid statement. The undo half of `markAsPaid`.
    func markAsUnpaid(statementId: Int) -> Bool {
        do {
            try db.markStatementAsUnpaid(statementId: statementId)
            db.executeSyncUpdate(
                "UPDATE CreditCardStatements SET sync_status = 'pending' WHERE id = ?;",
                intBindings: [statementId]
            )
            // The due reminders were cancelled when it was marked paid, so they have to come back.
            StatementNotificationManager.shared.rescheduleAllNotifications()
            NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
            return true
        } catch {
            logError("Failed to mark statement as unpaid: \(error)")
            return false
        }
    }

    // MARK: - CloudKit Sync Methods

    func fetchPendingSync() -> [CreditCardStatement] {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return [] }
        // Fetch all statements for all cards owned by this user, filter by pending sync
        let allCards = CreditCardRepository().fetchAllCards(userId: uid)
        var pendingStatements: [CreditCardStatement] = []
        for card in allCards {
            guard let cardId = card.id else { continue }
            let statements = fetchStatements(forCardId: cardId)
            for stmt in statements {
                guard let stmtId = stmt.id else { continue }
                if let isPending = db.fetchSingleInt(
                    "SELECT CASE WHEN sync_status = 'pending' THEN 1 ELSE 0 END FROM CreditCardStatements WHERE id = ?;",
                    intBinding: stmtId
                ), isPending == 1 {
                    pendingStatements.append(stmt)
                }
            }
        }
        return pendingStatements
    }

    /// See `TransactionRepository.markAsSynced` for why `pushedUpdatedAt` matters: without it, an
    /// edit made while the push was in flight is marked synced and never pushed.
    func markAsSynced(ckRecordName: String, pushedUpdatedAt: Date? = nil) {
        if let pushedUpdatedAt = pushedUpdatedAt {
            db.executeSyncUpdate(
                "UPDATE CreditCardStatements SET sync_status = 'synced' WHERE ck_record_id = ? AND COALESCE(updated_at, 0) <= ?;",
                textBindings: [ckRecordName],
                intBindings: [Int(pushedUpdatedAt.timeIntervalSince1970)]
            )
            return
        }
        // Phase 3C: CK record name is pre-stored before push, so matching by ck_record_id is sufficient
        db.executeSyncUpdate(
            "UPDATE CreditCardStatements SET sync_status = 'synced' WHERE ck_record_id = ?;",
            textBindings: [ckRecordName]
        )
    }

    func insertFromCloud(_ stmt: CreditCardStatement, ckRecordName: String) {
        db.executeSyncUpdate(
            "DELETE FROM CreditCardStatements WHERE ck_record_id = ?;",
            textBindings: [ckRecordName]
        )

        db.executeGroupWrite(
            """
            INSERT INTO CreditCardStatements
                (credit_card_id, closing_date, due_date, total_amount,
                 is_paid, paid_date, paid_amount, is_dates_overridden, user_id,
                 created_at, updated_at, ck_record_id, sync_status, ck_modified_at, created_by_uid)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?, ?);
            """,
            orderedBindings: [
                stmt.creditCardId,
                Int(stmt.closingDate.timeIntervalSince1970),
                Int(stmt.dueDate.timeIntervalSince1970),
                stmt.totalAmount,
                stmt.isPaid ? 1 : 0,
                stmt.paidDate.map { Int($0.timeIntervalSince1970) },
                stmt.paidAmount,
                stmt.isDatesOverridden ? 1 : 0,
                stmt.userId,
                Int(stmt.createdAt.timeIntervalSince1970),
                Int(stmt.updatedAt.timeIntervalSince1970),
                ckRecordName,
                Int(Date().timeIntervalSince1970),
                stmt.createdByUid
            ]
        )
    }

    func updateFromCloud(_ stmt: CreditCardStatement, ckRecordName: String) {
        db.executeGroupWrite(
            """
            UPDATE CreditCardStatements SET
                credit_card_id = ?, closing_date = ?, due_date = ?,
                total_amount = ?, is_paid = ?, paid_date = ?,
                paid_amount = ?, is_dates_overridden = ?,
                updated_at = ?, sync_status = 'synced', ck_modified_at = ?,
                created_by_uid = COALESCE(?, created_by_uid), is_deleted = 0
            WHERE ck_record_id = ?;
            """,
            orderedBindings: [
                stmt.creditCardId,
                Int(stmt.closingDate.timeIntervalSince1970),
                Int(stmt.dueDate.timeIntervalSince1970),
                stmt.totalAmount,
                stmt.isPaid ? 1 : 0,
                stmt.paidDate.map { Int($0.timeIntervalSince1970) },
                stmt.paidAmount,
                stmt.isDatesOverridden ? 1 : 0,
                Int(stmt.updatedAt.timeIntervalSince1970),
                Int(Date().timeIntervalSince1970),
                stmt.createdByUid,
                ckRecordName
            ]
        )
    }

    func deleteFromCloud(ckRecordName recordName: String) {
        // RECREATION-WINS guard: keep a statement with unpushed local edits rather than applying
        // a remote delete (it re-pushes, preserving the newer local change).
        if db.fetchSingleString("SELECT sync_status FROM CreditCardStatements WHERE ck_record_id = ?;", textBinding: recordName) == "pending" {
            return
        }
        // Cancel reminders for a statement deleted on another device before removing the row.
        if let localId = db.fetchSingleInt(
            "SELECT id FROM CreditCardStatements WHERE ck_record_id = ?;", textBinding: recordName) {
            StatementNotificationManager.shared.cancelNotifications(for: localId)
        }
        db.executeSyncUpdate(
            "DELETE FROM CreditCardStatements WHERE ck_record_id = ?;",
            textBindings: [recordName]
        )
    }

    func fetchPendingDeletes() -> [(ckRecordName: String, localId: Int)] {
        let query = "SELECT id, ck_record_id FROM CreditCardStatements WHERE sync_status = 'pendingDelete' AND ck_record_id IS NOT NULL;"
        return db.fetchIdAndCKRecordName(query) ?? []
    }

    func hardDeleteByCKRecordName(_ recordName: String) {
        if let localId = db.fetchSingleInt(
            "SELECT id FROM CreditCardStatements WHERE ck_record_id = ?;", textBinding: recordName) {
            StatementNotificationManager.shared.cancelNotifications(for: localId)
        }
        db.executeSyncUpdate(
            "DELETE FROM CreditCardStatements WHERE ck_record_id = ?;",
            textBindings: [recordName]
        )
    }

    func fetchCKRecordName(for id: Int) -> String? {
        return db.fetchSingleString(
            "SELECT ck_record_id FROM CreditCardStatements WHERE id = ?;",
            intBinding: id
        )
    }

    /// Re-marks all synced, already-pushed statements for a card as pending.
    /// Called after a credit card gets its ck_record_id assigned (first push), so that
    /// statements pushed in the same batch are re-pushed on the next sync cycle with
    /// creditCardCKRecordName now correctly populated for cross-device ID remapping.
    func markStatementsPending(forCardId cardId: Int) {
        let now = Int(Date().timeIntervalSince1970)
        db.executeSyncUpdate(
            """
            UPDATE CreditCardStatements
            SET sync_status = 'pending', ck_modified_at = ?
            WHERE credit_card_id = ? AND sync_status = 'synced' AND ck_record_id IS NOT NULL
              AND (is_deleted IS NULL OR is_deleted = 0) AND ck_system_fields IS NULL;
            """,
            intBindings: [now, cardId]
        )
    }

    func fetchStatement(byCKRecordName recordName: String) -> CreditCardStatement? {
        // No is_deleted filter: soft-deleted rows are still returned so that
        // updateFromCloud (cloud wins) can resurrect them via is_deleted = 0.
        // Wrong-creditCardId rows are handled correctly because we bypass the
        // fetchStatements(forCardId:) chain and query by id directly.
        guard let id = db.fetchSingleInt(
            "SELECT id FROM CreditCardStatements WHERE ck_record_id = ?;",
            textBinding: recordName
        ) else { return nil }
        guard let row = try? db.getStatement(byId: id) else { return nil }
        return CreditCardStatement(
            id: row.id,
            creditCardId: row.creditCardId,
            closingDate: Date(timeIntervalSince1970: TimeInterval(row.closingDate)),
            dueDate: Date(timeIntervalSince1970: TimeInterval(row.dueDate)),
            totalAmount: row.totalAmount,
            isPaid: row.isPaid,
            paidDate: row.paidDate.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            paidAmount: row.paidAmount,
            isDatesOverridden: row.isDatesOverridden,
            userId: row.userId,
            createdAt: Date(timeIntervalSince1970: TimeInterval(row.createdAt)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt))
        )
    }

    func lastModifiedDate(for id: Int) -> Date? {
        let query = "SELECT updated_at FROM CreditCardStatements WHERE id = ?;"
        guard let timestamp = db.fetchSingleInt(query, intBinding: id), timestamp > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    func markSyncPending(for id: Int) {
        let now = Int(Date().timeIntervalSince1970)
        db.executeSyncUpdate(
            "UPDATE CreditCardStatements SET sync_status = 'pending', ck_modified_at = ? WHERE id = ?;",
            intBindings: [now, id]
        )
    }

    func setCKRecordId(for id: Int, ckRecordName: String) {
        db.executeSyncUpdate(
            "UPDATE CreditCardStatements SET ck_record_id = ? WHERE id = ? AND ck_record_id IS NULL;",
            textBindings: [ckRecordName],
            intBindings: [id]
        )
    }

    /// If a soft-deleted statement with this CK record name exists (is_deleted=1),
    /// restores its sync_status to 'pendingDelete' so the next push will remove it from
    /// CloudKit. Returns true if such a record was found (caller should skip re-insertion).
    func restorePendingDeleteIfNeeded(ckRecordName: String) -> Bool {
        let check = "SELECT id FROM CreditCardStatements WHERE ck_record_id = ? AND is_deleted = 1;"
        guard db.fetchSingleInt(check, textBinding: ckRecordName) != nil else { return false }
        db.executeSyncUpdate(
            "UPDATE CreditCardStatements SET sync_status = 'pendingDelete' WHERE ck_record_id = ? AND is_deleted = 1;",
            textBindings: [ckRecordName]
        )
        return true
    }
}
