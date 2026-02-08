//
//  StatementRepository.swift
//  Finova
//

import Foundation

class StatementRepository {

    func insertStatement(_ stmt: CreditCardStatement) -> Int? {
        do {
            let id = try DBHelper.shared.insertStatement(
                creditCardId: stmt.creditCardId,
                closingDate: Int(stmt.closingDate.timeIntervalSince1970),
                dueDate: Int(stmt.dueDate.timeIntervalSince1970),
                totalAmount: stmt.totalAmount,
                userId: stmt.userId
            )
            return id > 0 ? id : nil
        } catch {
            logError("Failed to insert statement: \(error)")
            return nil
        }
    }

    func fetchStatements(forCardId cardId: Int) -> [CreditCardStatement] {
        do {
            let rows = try DBHelper.shared.getStatements(creditCardId: cardId)
            return rows.map { row in
                CreditCardStatement(
                    id: row.id,
                    creditCardId: row.creditCardId,
                    closingDate: Date(timeIntervalSince1970: TimeInterval(row.closingDate)),
                    dueDate: Date(timeIntervalSince1970: TimeInterval(row.dueDate)),
                    totalAmount: row.totalAmount,
                    isPaid: row.isPaid,
                    paidDate: row.paidDate.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    paidAmount: row.paidAmount,
                    userId: row.userId,
                    createdAt: Date(timeIntervalSince1970: TimeInterval(row.createdAt)),
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt))
                )
            }
        } catch {
            logError("Failed to fetch statements: \(error)")
            return []
        }
    }

    func findStatement(creditCardId: Int, closingDate: Date) -> Int? {
        do {
            return try DBHelper.shared.findStatement(
                creditCardId: creditCardId,
                closingDate: Int(closingDate.timeIntervalSince1970)
            )
        } catch {
            logError("Failed to find statement: \(error)")
            return nil
        }
    }

    func deleteStatement(statementId: Int) -> Bool {
        do {
            try DBHelper.shared.deleteStatement(statementId: statementId)
            return true
        } catch {
            logError("Failed to delete statement: \(error)")
            return false
        }
    }

    func recalculateTotal(statementId: Int) {
        do {
            let total = try DBHelper.shared.getTransactionSumForStatement(statementId: statementId)
            try DBHelper.shared.updateStatementTotal(statementId: statementId, totalAmount: total)
        } catch {
            logError("Failed to recalculate statement total: \(error)")
        }
    }

    func updateDates(statementId: Int, closingDate: Date, dueDate: Date) -> Bool {
        do {
            try DBHelper.shared.updateStatementDates(
                statementId: statementId,
                closingDate: Int(closingDate.timeIntervalSince1970),
                dueDate: Int(dueDate.timeIntervalSince1970)
            )
            return true
        } catch {
            logError("Failed to update statement dates: \(error)")
            return false
        }
    }

    func markAsPaid(statementId: Int, paidAmount: Int?, paidDate: Date) -> Bool {
        do {
            try DBHelper.shared.markStatementAsPaid(
                statementId: statementId,
                paidAmount: paidAmount,
                paidDate: Int(paidDate.timeIntervalSince1970)
            )
            return true
        } catch {
            logError("Failed to mark statement as paid: \(error)")
            return false
        }
    }
}
