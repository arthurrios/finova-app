//
//  CreditCardRepository.swift
//  Finova
//

import Foundation

class CreditCardRepository {

    func insertCard(_ card: CreditCard) -> Int? {
        do {
            let id = try DBHelper.shared.insertCreditCard(
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
            return id > 0 ? id : nil
        } catch {
            logError("Failed to insert credit card: \(error)")
            return nil
        }
    }

    func fetchAllCards(userId: String) -> [CreditCard] {
        do {
            let rows = try DBHelper.shared.getCreditCards(userId: userId)
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
            guard let row = try DBHelper.shared.getCreditCard(id: id) else { return nil }
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
            try DBHelper.shared.updateCreditCard(
                id: id, name: card.name, lastFourDigits: card.lastFourDigits,
                cardBrand: card.cardBrand.rawValue, closingDay: card.closingDay,
                dueDay: card.dueDay, creditLimit: card.creditLimit,
                cardColor: card.cardColor.rawValue, isDefault: card.isDefault
            )
            return true
        } catch {
            logError("Failed to update credit card: \(error)")
            return false
        }
    }

    func clearDefault(userId: String) -> Bool {
        do {
            try DBHelper.shared.clearDefaultCard(userId: userId)
            return true
        } catch {
            logError("Failed to clear default card: \(error)")
            return false
        }
    }

    func deleteCard(id: Int) -> Bool {
        do {
            try DBHelper.shared.softDeleteCreditCard(id: id)
            return true
        } catch {
            logError("Failed to delete credit card: \(error)")
            return false
        }
    }

    // MARK: - Group Sharing

    func shareCard(cardId: Int, withGroupId groupId: String) {
        DBHelper.shared.executeSyncUpdate(
            "UPDATE CreditCards SET shared_group_id = ?, sync_status = 'pending' WHERE id = ?;",
            textBindings: [groupId],
            intBindings: [cardId]
        )
    }

    func unshareCard(cardId: Int) {
        DBHelper.shared.executeSyncUpdate(
            "UPDATE CreditCards SET shared_group_id = NULL, sync_status = 'pending' WHERE id = ?;",
            intBindings: [cardId]
        )
    }

    func fetchCardsForGroup(groupId: String) -> [CreditCard] {
        do {
            let rows = try DBHelper.shared.getCreditCardsForGroup(groupId: groupId)
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
}
