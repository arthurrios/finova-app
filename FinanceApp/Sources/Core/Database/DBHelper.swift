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
      try? createTable()
    }

    
    private func openDatabase() throws {
        let fileURL = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("AppFinance.sqlite")
        
        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            throw DBError.openDatabaseFailed
        }
    }
    
    private func createTable() throws {
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
}
