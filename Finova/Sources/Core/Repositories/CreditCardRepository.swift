//
//  CreditCardRepository.swift
//  Finova
//

import Foundation

class CreditCardRepository {

    private let db = DBHelper.shared

    func insertCard(_ card: CreditCard) -> Int? {
        do {
            let id = try db.insertCreditCard(
                name: card.name,
                lastFourDigits: card.lastFourDigits,
                cardBrand: card.cardBrand.rawValue,
                closingDay: card.closingDay,
                dueDay: card.dueDay,
                creditLimit: card.creditLimit,
                cardColor: card.cardColor.rawValue,
                userId: card.userId,
                isDefault: card.isDefault
            )
            if id > 0 {
                db.executeSyncUpdate(
                    "UPDATE CreditCards SET sync_status = 'pending' WHERE id = ?;",
                    intBindings: [id]
                )
                NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
            }
            return id > 0 ? id : nil
        } catch {
            logError("Failed to insert credit card: \(error)")
            return nil
        }
    }

    func fetchAllCards(userId: String) -> [CreditCard] {
        do {
            let rows = try db.getCreditCards(userId: userId)
            return rows.map { row in
                CreditCard(
                    id: row.id,
                    name: row.name,
                    lastFourDigits: row.lastFourDigits,
                    cardBrand: CardBrand(rawValue: row.cardBrand) ?? .other,
                    closingDay: row.closingDay,
                    dueDay: row.dueDay,
                    creditLimit: row.creditLimit,
                    cardColor: CardColor(rawValue: row.cardColor) ?? .blue,
                    userId: userId,
                    isDeleted: row.isDeleted,
                    isDefault: row.isDefault,
                    createdAt: Date(timeIntervalSince1970: TimeInterval(row.createdAt)),
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt))
                )
            }
        } catch {
            logError("Failed to fetch credit cards: \(error)")
            return []
        }
    }

    func fetchCard(byId id: Int) -> CreditCard? {
        do {
            guard let row = try db.getCreditCard(id: id) else { return nil }
            return CreditCard(
                id: row.id,
                name: row.name,
                lastFourDigits: row.lastFourDigits,
                cardBrand: CardBrand(rawValue: row.cardBrand) ?? .other,
                closingDay: row.closingDay,
                dueDay: row.dueDay,
                creditLimit: row.creditLimit,
                cardColor: CardColor(rawValue: row.cardColor) ?? .blue,
                userId: row.userId,
                isDeleted: row.isDeleted,
                isDefault: row.isDefault,
                createdAt: Date(timeIntervalSince1970: TimeInterval(row.createdAt)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt))
            )
        } catch {
            logError("Failed to fetch credit card: \(error)")
            return nil
        }
    }

    func updateCard(_ card: CreditCard) -> Bool {
        guard let id = card.id else { return false }
        do {
            try db.updateCreditCard(
                id: id, name: card.name, lastFourDigits: card.lastFourDigits,
                cardBrand: card.cardBrand.rawValue, closingDay: card.closingDay,
                dueDay: card.dueDay, creditLimit: card.creditLimit,
                cardColor: card.cardColor.rawValue, isDefault: card.isDefault
            )
            db.executeSyncUpdate(
                "UPDATE CreditCards SET sync_status = 'pending' WHERE id = ?;",
                intBindings: [id]
            )
            NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
            return true
        } catch {
            logError("Failed to update credit card: \(error)")
            return false
        }
    }

    func clearDefault(userId: String) -> Bool {
        do {
            try db.clearDefaultCard(userId: userId)
            return true
        } catch {
            logError("Failed to clear default card: \(error)")
            return false
        }
    }

    func deleteCard(id: Int) -> Bool {
        do {
            try db.softDeleteCreditCard(id: id)
            // Check if synced — use pendingDelete to trigger CK deletion
            let ckName = fetchCKRecordName(for: id)
            let syncStatus = ckName != nil ? "pendingDelete" : "pending"
            db.executeSyncUpdate(
                "UPDATE CreditCards SET sync_status = '\(syncStatus)' WHERE id = ?;",
                intBindings: [id]
            )
            NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
            return true
        } catch {
            logError("Failed to delete credit card: \(error)")
            return false
        }
    }

    // MARK: - Group Sharing

    func shareCard(cardId: Int, withGroupId groupId: String) {
        db.executeSyncUpdate(
            "UPDATE CreditCards SET shared_group_id = ?, sync_status = 'pending' WHERE id = ?;",
            textBindings: [groupId],
            intBindings: [cardId]
        )
        NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
    }

    func unshareCard(cardId: Int) {
        db.executeSyncUpdate(
            "UPDATE CreditCards SET shared_group_id = NULL, sync_status = 'pending' WHERE id = ?;",
            intBindings: [cardId]
        )
        NotificationCenter.default.post(name: .creditCardDataChanged, object: nil)
    }

    func fetchCardsForGroup(groupId: String) -> [CreditCard] {
        do {
            let rows = try db.getCreditCardsForGroup(groupId: groupId)
            return rows.map { row in
                CreditCard(
                    id: row.id,
                    name: row.name,
                    lastFourDigits: row.lastFourDigits,
                    cardBrand: CardBrand(rawValue: row.cardBrand) ?? .other,
                    closingDay: row.closingDay,
                    dueDay: row.dueDay,
                    creditLimit: row.creditLimit,
                    cardColor: CardColor(rawValue: row.cardColor) ?? .blue,
                    userId: row.userId,
                    isDeleted: row.isDeleted,
                    isDefault: row.isDefault,
                    createdAt: Date(timeIntervalSince1970: TimeInterval(row.createdAt)),
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt))
                )
            }
        } catch {
            logError("Failed to fetch credit cards for group: \(error)")
            return []
        }
    }

    // MARK: - CloudKit Sync Methods

    func fetchPendingSync() -> [CreditCard] {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return [] }
        let allCards = fetchAllCards(userId: uid)
        // Filter to pending sync status via DB query
        let pendingIds = pendingSyncCardIds(userId: uid)
        return allCards.filter { card in
            guard let id = card.id else { return false }
            return pendingIds.contains(id)
        }
    }

    func markAsSynced(ckRecordName: String) {
        // Phase 3C: CK record name is pre-stored before push, so matching by ck_record_id is sufficient
        db.executeSyncUpdate(
            "UPDATE CreditCards SET sync_status = 'synced' WHERE ck_record_id = ?;",
            textBindings: [ckRecordName]
        )
    }

    func insertFromCloud(_ card: CreditCard, ckRecordName: String) {
        db.executeSyncUpdate(
            "DELETE FROM CreditCards WHERE ck_record_id = ?;",
            textBindings: [ckRecordName]
        )

        db.executeGroupWrite(
            """
            INSERT INTO CreditCards
                (name, last_four_digits, card_brand, closing_day, due_day,
                 credit_limit, card_color, user_id, is_deleted, is_default,
                 created_at, updated_at, shared_group_id, ck_record_id, sync_status, ck_modified_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?);
            """,
            orderedBindings: [
                card.name,
                card.lastFourDigits,
                card.cardBrand.rawValue,
                card.closingDay,
                card.dueDay,
                card.creditLimit,
                card.cardColor.rawValue,
                card.userId,
                card.isDeleted ? 1 : 0,
                card.isDefault ? 1 : 0,
                Int(card.createdAt.timeIntervalSince1970),
                Int(card.updatedAt.timeIntervalSince1970),
                card.sharedGroupId,
                ckRecordName,
                Int(Date().timeIntervalSince1970)
            ]
        )
    }

    func updateFromCloud(_ card: CreditCard, ckRecordName: String) {
        db.executeGroupWrite(
            """
            UPDATE CreditCards SET
                name = ?, last_four_digits = ?, card_brand = ?,
                closing_day = ?, due_day = ?, credit_limit = ?,
                card_color = ?, is_deleted = ?, is_default = ?,
                shared_group_id = ?,
                updated_at = ?, sync_status = 'synced', ck_modified_at = ?
            WHERE ck_record_id = ?;
            """,
            orderedBindings: [
                card.name,
                card.lastFourDigits,
                card.cardBrand.rawValue,
                card.closingDay,
                card.dueDay,
                card.creditLimit,
                card.cardColor.rawValue,
                card.isDeleted ? 1 : 0,
                card.isDefault ? 1 : 0,
                card.sharedGroupId,
                Int(card.updatedAt.timeIntervalSince1970),
                Int(Date().timeIntervalSince1970),
                ckRecordName
            ]
        )
    }

    func deleteFromCloud(ckRecordName recordName: String) {
        db.executeSyncUpdate(
            "DELETE FROM CreditCards WHERE ck_record_id = ?;",
            textBindings: [recordName]
        )
    }

    func fetchPendingDeletes() -> [(ckRecordName: String, localId: Int)] {
        let query = "SELECT id, ck_record_id FROM CreditCards WHERE sync_status = 'pendingDelete' AND ck_record_id IS NOT NULL;"
        return db.fetchIdAndCKRecordName(query) ?? []
    }

    func hardDeleteByCKRecordName(_ recordName: String) {
        db.executeSyncUpdate(
            "DELETE FROM CreditCards WHERE ck_record_id = ?;",
            textBindings: [recordName]
        )
    }

    func fetchCKRecordName(for id: Int) -> String? {
        return db.fetchSingleString(
            "SELECT ck_record_id FROM CreditCards WHERE id = ?;",
            intBinding: id
        )
    }

    func fetchCard(byCKRecordName recordName: String) -> CreditCard? {
        guard let id = db.fetchSingleInt(
            "SELECT id FROM CreditCards WHERE ck_record_id = ?;",
            textBinding: recordName
        ) else { return nil }
        return fetchCard(byId: id)
    }

    func lastModifiedDate(for id: Int) -> Date? {
        let query = "SELECT updated_at FROM CreditCards WHERE id = ?;"
        guard let timestamp = db.fetchSingleInt(query, intBinding: id), timestamp > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    func markSyncPending(for id: Int) {
        let now = Int(Date().timeIntervalSince1970)
        db.executeSyncUpdate(
            "UPDATE CreditCards SET sync_status = 'pending', ck_modified_at = ? WHERE id = ?;",
            intBindings: [now, id]
        )
    }

    func setCKRecordId(for id: Int, ckRecordName: String) {
        db.executeSyncUpdate(
            "UPDATE CreditCards SET ck_record_id = ? WHERE id = ? AND ck_record_id IS NULL;",
            textBindings: [ckRecordName],
            intBindings: [id]
        )
    }

    func fetchSharedGroupId(for cardId: Int) -> String? {
        return db.fetchSingleString(
            "SELECT shared_group_id FROM CreditCards WHERE id = ?;",
            intBinding: cardId
        )
    }

    // MARK: - Private Helpers

    private func pendingSyncCardIds(userId: String) -> Set<Int> {
        // Use a simple approach: query IDs with pending sync status
        var ids = Set<Int>()
        if let id = db.fetchSingleInt(
            "SELECT id FROM CreditCards WHERE sync_status = 'pending' AND user_id = ? LIMIT 1;",
            textBinding: userId
        ) {
            ids.insert(id)
        }
        // For multiple results, we need a different approach - fetch all pending cards
        let allPending = fetchAllPendingCardIds(userId: userId)
        return allPending
    }

    private func fetchAllPendingCardIds(userId: String) -> Set<Int> {
        let allCards = fetchAllCards(userId: userId)
        var pendingIds = Set<Int>()
        for card in allCards {
            guard let id = card.id else { continue }
            if let syncStatus = db.fetchSingleInt(
                "SELECT CASE WHEN sync_status = 'pending' THEN 1 ELSE 0 END FROM CreditCards WHERE id = ?;",
                intBinding: id
            ), syncStatus == 1 {
                pendingIds.insert(id)
            }
        }
        return pendingIds
    }
}
