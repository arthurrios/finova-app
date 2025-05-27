//
//  DBHelper.swift
//  FinanceApp
//
//  Created by Arthur Rios on 21/05/25.
//

import Foundation
import SQLite3

enum DBError: Error {
    case openDatabaseFailed
    case prepareFailed(message: String)
    case stepFailed(message: String)
}

class DBHelper {
    static let shared = DBHelper()
    
    private var db: OpaquePointer?
    
    private init() {
        try? openDatabase()
        try? createBudgetsTable()
        try? createTransactionsTable()
    }
    
    
    private func openDatabase() throws {
        let fileURL = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("AppFinance.sqlite")
        
        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            throw DBError.openDatabaseFailed
        }
    }
    
    private func createBudgetsTable() throws {
        let createTableQuery = """
            CREATE TABLE IF NOT EXISTS Budgets (
                month_date INTEGER PRIMARY KEY,
                amount     INTEGER NOT NULL
            );
            """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, createTableQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    func insertBudget(monthDate: Int, amount: Int) throws {
        let insertQuery = "INSERT INTO Budgets (month_date, amount) VALUES (?, ?);"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int64(statement, 1, Int64(monthDate))
        sqlite3_bind_int64(statement, 2, Int64(amount))
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    func updateBudget(monthDate: Int, amount: Int) throws {
        let updateQuery = "UPDATE Budgets SET amount = ? WHERE month_date = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int64(statement, 1, Int64(amount))
        sqlite3_bind_int64(statement, 2, Int64(monthDate))
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    func getBudgets() throws -> [BudgetModel] {
        let getBudgetsQuery = "SELECT month_date, amount FROM Budgets;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, getBudgetsQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        var results: [BudgetModel] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let monthDate = Int(sqlite3_column_int64(statement, 0))
            let budget = Int(sqlite3_column_int64(statement, 1))
            results.append(BudgetModel(monthDate: monthDate, amount: budget))
        }
        
        return results
    }
    
    func exists(monthDate: Int) throws -> Bool {
        let existsQuery = "SELECT COUNT(*) FROM Budgets WHERE month_date = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, existsQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int64(statement, 1, Int64(monthDate))
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
        
        let count = sqlite3_column_int(statement, 0)
        return count > 0
    }
    
    func deleteBudget(monthDate: Int) throws {
        let deleteQuery = "DELETE FROM Budgets WHERE month_date = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, deleteQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int64(statement, 1, Int64(monthDate))
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    private func createTransactionsTable() throws {
        let createTransactionsTableQuery = """
            CREATE TABLE IF NOT EXISTS Transactions (
                id                INTEGER PRIMARY KEY AUTOINCREMENT,
                title             TEXT NOT NULL,
                category          TEXT NOT NULL,
                type              TEXT NOT NULL,
                amount            INTEGER NOT NULL,
                date              INTEGER NOT NULL,
                budget_month_date INTEGER,
                FOREIGN KEY(budget_month_date)
                    REFERENCES Budgets(month_date)
                    ON UPDATE CASCADE
                    ON DELETE SET NULL
            );
            
            CREATE INDEX IF NOT EXISTS idx_tx_date              ON Transactions(date);
            CREATE INDEX IF NOT EXISTS idx_tx_category          ON Transactions(category);
            CREATE INDEX IF NOT EXISTS idx_tx_budget_month_date ON Transactions(budget_month_date);
            """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, createTransactionsTableQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        if sqlite3_step(statement) != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    func insertTransaction(_ transaction: TransactionModel) throws {
        let insertQuery = "INSERT INTO Transactions (title, category, type, amount, date, budget_month_date) VALUES (?, ?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        sqlite3_bind_text(statement, 1, transaction.title, -1, transient)
        sqlite3_bind_text(statement, 2, transaction.category, -1, transient)
        sqlite3_bind_text(statement, 3, transaction.type, -1, transient)
        sqlite3_bind_int64(statement, 4, Int64(transaction.amount))
        sqlite3_bind_int64(statement, 5, Int64(transaction.dateTimestamp))
        sqlite3_bind_int64(statement, 6, Int64(transaction.budgetMonthDate))
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    func getTransactions() throws -> [Transaction] {
        let getTransactionsQuery = "SELECT title, category, type, amount, date, budget_month_date FROM Transactions;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, getTransactionsQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        var results: [Transaction] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let title      = String(cString: sqlite3_column_text(statement, 0))
            let catKey    = String(cString: sqlite3_column_text(statement, 1))
            let typeKey   = String(cString: sqlite3_column_text(statement, 2))
            let amount     = Int(sqlite3_column_int64(statement, 3))
            let ts         = Int(sqlite3_column_int64(statement, 4))
            let monthAnchor = Int(sqlite3_column_int64(statement, 5))
            
            guard let txCategory = TransactionCategory.allCases
                .first(where: { $0.key == catKey })
            else {
                print("⚠️ Unknown category key:", catKey)
                continue
            }
            
            guard let txType = TransactionType.allCases
                .first(where: { String(describing: $0) == typeKey })
            else {
                print("⚠️ Unknown transaction type key:", typeKey)
                continue
            }
            
            let tx = Transaction(
                title:            title,
                category:         txCategory,
                amount:           amount,
                type:             txType,
                dateTimestamp:    ts,
                budgetMonthDate:  monthAnchor
            )
            results.append(tx)
        }
        return results
    }
    
    func deleteTransaction(id: Int) throws {
        let deleteTransactionQuery = "DELETE FROM Transactions WHERE id = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, deleteTransactionQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int64(statement, 1, Int64(id))
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
}

