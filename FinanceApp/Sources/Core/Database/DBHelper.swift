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
    private var isInitialized = false
    
    private init() {
        initializeDatabase()
    }
    
    private func initializeDatabase() {
        do {
            try openDatabase()
            try createBudgetsTable()
            try createTransactionsTable()
            try migrateTransactionsTable()
            isInitialized = true
            print("✅ Database initialized successfully")
        } catch {
            print("⚠️ Database initialization failed: \(error)")
            // Don't crash the app, just log the error
            // This allows the app to continue running in test environments
            isInitialized = false
        }
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
        guard isInitialized else {
            print("⚠️ Database not initialized, skipping budget insert")
            return
        }
        
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
        guard isInitialized else {
            print("⚠️ Database not initialized, skipping budget update")
            return
        }
        
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
        guard isInitialized else {
            print("⚠️ Database not initialized, returning empty budget list")
            return []
        }
        
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
        guard isInitialized else {
            print("⚠️ Database not initialized, returning false for exists check")
            return false
        }
        
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
        
        let resultCount = sqlite3_column_int(statement, 0)
        return resultCount != 0
    }
    
    func deleteBudget(monthDate: Int) throws {
        guard isInitialized else {
            print("⚠️ Database not initialized, skipping budget delete")
            return
        }
        
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
          id                    INTEGER PRIMARY KEY AUTOINCREMENT,
          title                 TEXT NOT NULL,
          category              TEXT NOT NULL,
          type                  TEXT NOT NULL,
          amount                INTEGER NOT NULL,
          date                  INTEGER NOT NULL,
          budget_month_date     INTEGER,
          is_recurring          INTEGER DEFAULT 0,
          has_installments      INTEGER DEFAULT 0,
          parent_transaction_id INTEGER,
          installment_number    INTEGER,
          total_installments    INTEGER,
          original_amount       INTEGER,
          FOREIGN KEY(budget_month_date)
              REFERENCES Budgets(month_date)
              ON UPDATE CASCADE
              ON DELETE SET NULL
          FOREIGN KEY(parent_transaction_id)
              REFERENCES Transactions(id)
              ON DELETE CASCADE
      );
      
      CREATE INDEX IF NOT EXISTS idx_tx_date              ON Transactions(date);
      CREATE INDEX IF NOT EXISTS idx_tx_category          ON Transactions(category);
      CREATE INDEX IF NOT EXISTS idx_tx_budget_month_date ON Transactions(budget_month_date);
      CREATE INDEX IF NOT EXISTS idx_tx_parent_id         ON Transactions(parent_transaction_id);
      CREATE INDEX IF NOT EXISTS idx_tx_recurring         ON Transactions(is_recurring);
      """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, createTransactionsTableQuery, -1, &statement, nil) == SQLITE_OK
        else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        if sqlite3_step(statement) != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    private func migrateTransactionsTable() throws {
        let checkQuery = "PRAGMA table_info(Transactions);"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, checkQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        var existingColumns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let columnName = String(cString: sqlite3_column_text(statement, 1))
            existingColumns.insert(columnName)
        }
        
        let requiredColumns = [
            "is_recurring",
            "has_installments",
            "parent_transaction_id",
            "installment_number",
            "total_installments",
            "original_amount"
        ]
        
        let missingColumns = requiredColumns.filter { !existingColumns.contains($0) }
        
        if !missingColumns.isEmpty {
            try addNewColumns(missingColumns)
        }
    }
    
    private func addNewColumns(_ columns: [String]) throws {
        let alterQueries = [
            "is_recurring": "ALTER TABLE Transactions ADD COLUMN is_recurring INTEGER DEFAULT 0;",
            "has_installments": "ALTER TABLE Transactions ADD COLUMN has_installments INTEGER DEFAULT 0;",
            "parent_transaction_id": "ALTER TABLE Transactions ADD COLUMN parent_transaction_id INTEGER;",
            "installment_number": "ALTER TABLE Transactions ADD COLUMN installment_number INTEGER;",
            "total_installments": "ALTER TABLE Transactions ADD COLUMN total_installments INTEGER;",
            "original_amount": "ALTER TABLE Transactions ADD COLUMN original_amount INTEGER;"
        ]
        
        for column in columns {
            guard let query = alterQueries[column] else { continue }
            
            var statement: OpaquePointer?
            
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DBError.prepareFailed(message: msg)
            }
            
            defer { sqlite3_finalize(statement) }
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DBError.stepFailed(message: msg)
            }
        }
    }
    
    func insertTransaction(_ transaction: TransactionModel) throws -> Int {
        guard isInitialized else {
            print("⚠️ Database not initialized, skipping transaction insert")
            return 0
        }
        
        let insertQuery = """
          INSERT INTO Transactions (
              title,
              category,
              type,
              amount, 
              date, 
              budget_month_date,
              is_recurring,
              has_installments,
              parent_transaction_id,
              installment_number,
              total_installments,
              original_amount
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        sqlite3_bind_text(statement, 1, transaction.data.title, -1, transient)
        sqlite3_bind_text(statement, 2, transaction.data.category, -1, transient)
        sqlite3_bind_text(statement, 3, transaction.data.type, -1, transient)
        sqlite3_bind_int64(statement, 4, Int64(transaction.data.amount))
        sqlite3_bind_int64(statement, 5, Int64(transaction.data.dateTimestamp))
        sqlite3_bind_int64(statement, 6, Int64(transaction.data.budgetMonthDate))
        
        if let isRecurring = transaction.data.isRecurring {
            sqlite3_bind_int(statement, 7, isRecurring ? 1 : 0)
        } else {
            sqlite3_bind_null(statement, 7)
        }
        
        if let hasInstallments = transaction.data.hasInstallments {
            sqlite3_bind_int(statement, 8, hasInstallments ? 1 : 0)
        } else {
            sqlite3_bind_null(statement, 8)
        }
        
        if let parentId = transaction.data.parentTransactionId {
            sqlite3_bind_int64(statement, 9, Int64(parentId))
        } else {
            sqlite3_bind_null(statement, 9)
        }
        
        if let installmentNumber = transaction.data.installmentNumber {
            sqlite3_bind_int(statement, 10, Int32(installmentNumber))
        } else {
            sqlite3_bind_null(statement, 10)
        }
        
        if let totalInstallments = transaction.data.totalInstallments {
            sqlite3_bind_int(statement, 11, Int32(totalInstallments))
        } else {
            sqlite3_bind_null(statement, 11)
        }
        
        if let originalAmount = transaction.data.originalAmount {
            sqlite3_bind_int64(statement, 12, Int64(originalAmount))
        } else {
            sqlite3_bind_null(statement, 12)
        }
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
        
        return Int(sqlite3_last_insert_rowid(db))
    }
    
    func getTransactions() throws -> [Transaction] {
        guard isInitialized else {
            print("⚠️ Database not initialized, returning empty transaction list")
            return []
        }
        
        let getTransactionsQuery = """
      SELECT
        id,
        title,
        category,
        type,
        amount,
        date,
        budget_month_date,
        is_recurring,
        has_installments,
        parent_transaction_id,
        installment_number,
        total_installments,
        original_amount
      FROM Transactions;
      """
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, getTransactionsQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        var results: [Transaction] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int64(statement, 0))
            let title = String(cString: sqlite3_column_text(statement, 1))
            let catKey = String(cString: sqlite3_column_text(statement, 2))
            let typeKey = String(cString: sqlite3_column_text(statement, 3))
            let amount = Int(sqlite3_column_int64(statement, 4))
            let ts = Int(sqlite3_column_int64(statement, 5))
            let monthAnchor = Int(sqlite3_column_int64(statement, 6))
            
            let isRecurring: Bool? = {
                if sqlite3_column_type(statement, 7) == SQLITE_NULL {
                    return nil
                }
                return sqlite3_column_int(statement, 7) == 1
            }()
            
            let hasInstallments: Bool? = {
                if sqlite3_column_type(statement, 8) == SQLITE_NULL {
                    return nil
                }
                return sqlite3_column_int(statement, 8) == 1
            }()
            
            let parentTransactionId: Int? = {
                if sqlite3_column_type(statement, 9) == SQLITE_NULL {
                    return nil
                }
                return Int(sqlite3_column_int64(statement, 9))
            }()
            
            let installmentNumber: Int? = {
                if sqlite3_column_type(statement, 10) == SQLITE_NULL {
                    return nil
                }
                return Int(sqlite3_column_int64(statement, 10))
            }()
            
            let totalInstallments: Int? = {
                if sqlite3_column_type(statement, 11) == SQLITE_NULL {
                    return nil
                }
                return Int(sqlite3_column_int64(statement, 11))
            }()
            
            let originalAmount: Int? = {
                if sqlite3_column_type(statement, 12) == SQLITE_NULL {
                    return nil
                }
                return Int(sqlite3_column_int64(statement, 12))
            }()
            
            //            guard
            //                let txCategory = TransactionCategory.allCases
            //                    .first(where: { $0.key == catKey })
            //            else {
            //                print("⚠️ Unknown category key:", catKey)
            //                continue
            //            }
            //
            //            guard
            //                let txType = TransactionType.allCases
            //                    .first(where: { String(describing: $0) == typeKey })
            //            else {
            //                print("⚠️ Unknown transaction type key:", typeKey)
            //                continue
            //            }
            
            let dbData = DBTransactionData(
                id: id,
                title: title,
                amount: amount,
                dateTimestamp: ts,
                budgetMonthDate: monthAnchor,
                isRecurring: isRecurring,
                hasInstallments: hasInstallments,
                parentTransactionId: parentTransactionId,
                installmentNumber: installmentNumber,
                totalInstallments: totalInstallments,
                originalAmount: originalAmount,
                category: catKey,
                type: typeKey
            )
            
            do {
                let uiData = try UITransactionData(from: dbData)
                let tx = Transaction(data: uiData)
                results.append(tx)
            } catch {
                print("⚠️ Failed to convert transaction data:", error)
                continue
            }
        }
        return results
    }
    
    func deleteTransaction(id: Int) throws {
        guard isInitialized else {
            print("⚠️ Database not initialized, skipping transaction delete")
            return
        }
        
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
    
    func getRecurringTransactions() throws -> [Transaction] {
        let query = """
      SELECT
        id, title, category, type, amount, date, budget_month_date,
        is_recurring, has_installments, parent_transaction_id,
        installment_number, total_installments, original_amount
      FROM Transactions 
      WHERE is_recurring = 1 AND (has_installments IS NULL OR has_installments = 0);
      """
        
        return try executeTransactionQuery(query)
    }
    
    func getInstallmentTransactions(parentId: Int) throws -> [Transaction] {
        let query = """
      SELECT
        id, title, category, type, amount, date, budget_month_date,
        is_recurring, has_installments, parent_transaction_id,
        installment_number, total_installments, original_amount
      FROM Transactions 
      WHERE parent_transaction_id = ?
      ORDER BY installment_number ASC;
      """
        
        return try executeTransactionQuery(query, bindValues: [parentId])
    }
    
    func getInstallmentParentTransactions() throws -> [Transaction] {
        let query = """
      SELECT
        id, title, category, type, amount, date, budget_month_date,
        is_recurring, has_installments, parent_transaction_id,
        installment_number, total_installments, original_amount
      FROM Transactions 
      WHERE has_installments = 1;
      """
        
        return try executeTransactionQuery(query)
    }
    
    private func executeTransactionQuery(_ query: String, bindValues: [Int] = []) throws
    -> [Transaction] {
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        for (index, value) in bindValues.enumerated() {
            sqlite3_bind_int64(statement, Int32(index + 1), Int64(value))
        }
        
        var results: [Transaction] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int64(statement, 0))
            let title = String(cString: sqlite3_column_text(statement, 1))
            let catKey = String(cString: sqlite3_column_text(statement, 2))
            let typeKey = String(cString: sqlite3_column_text(statement, 3))
            let amount = Int(sqlite3_column_int64(statement, 4))
            let ts = Int(sqlite3_column_int64(statement, 5))
            let monthAnchor = Int(sqlite3_column_int64(statement, 6))
            
            let isRecurring: Bool? =
            sqlite3_column_type(statement, 7) == SQLITE_NULL
            ? nil : (sqlite3_column_int(statement, 7) == 1)
            let hasInstallments: Bool? =
            sqlite3_column_type(statement, 8) == SQLITE_NULL
            ? nil : (sqlite3_column_int(statement, 8) == 1)
            let parentTransactionId: Int? =
            sqlite3_column_type(statement, 9) == SQLITE_NULL
            ? nil : Int(sqlite3_column_int64(statement, 9))
            let installmentNumber: Int? =
            sqlite3_column_type(statement, 10) == SQLITE_NULL
            ? nil : Int(sqlite3_column_int64(statement, 10))
            let totalInstallments: Int? =
            sqlite3_column_type(statement, 11) == SQLITE_NULL
            ? nil : Int(sqlite3_column_int64(statement, 11))
            let originalAmount: Int? =
            sqlite3_column_type(statement, 12) == SQLITE_NULL
            ? nil : Int(sqlite3_column_int64(statement, 12))
            
            //            guard let txCategory = TransactionCategory.allCases.first(where: { $0.key == catKey }),
            //                  let txType = TransactionType.allCases.first(where: { String(describing: $0) == typeKey })
            //            else {
            //                continue
            //            }
            
            let dbData = DBTransactionData(
                id: id, title: title, amount: amount, dateTimestamp: ts, budgetMonthDate: monthAnchor,
                isRecurring: isRecurring, hasInstallments: hasInstallments,
                parentTransactionId: parentTransactionId,
                installmentNumber: installmentNumber, totalInstallments: totalInstallments,
                originalAmount: originalAmount,
                category: catKey, type: typeKey
            )
            
            do {
                let uiData = try UITransactionData(from: dbData)
                results.append(Transaction(data: uiData))
            } catch {
                print("⚠️ Failed to convert transaction data:", error)
            }
        }
        
        return results
    }
    
    func updateTransactionParentId(transactionId: Int, parentId: Int) throws {
        guard isInitialized else {
            print("⚠️ Database not initialized, skipping transaction parent ID update")
            return
        }
        
        let updateQuery = "UPDATE Transactions SET parent_transaction_id = ? WHERE id = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int64(statement, 1, Int64(parentId))
        sqlite3_bind_int64(statement, 2, Int64(transactionId))
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    func getTransactionWithParent(id: Int) throws -> (transaction: Transaction?, parent: Transaction?) {
        let query = """
      SELECT
        t.id, t.title, t.category, t.type, t.amount, t.date, t.budget_month_date,
        t.is_recurring, t.has_installments, t.parent_transaction_id,
        t.installment_number, t.total_installments, t.original_amount,
        p.id as parent_id, p.title as parent_title, p.category as parent_category,
        p.type as parent_type, p.amount as parent_amount, p.date as parent_date,
        p.budget_month_date as parent_budget_month_date, p.is_recurring as parent_is_recurring,
        p.has_installments as parent_has_installments, p.parent_transaction_id as parent_parent_id,
        p.installment_number as parent_installment_number, p.total_installments as parent_total_installments,
        p.original_amount as parent_original_amount
      FROM Transactions t
      LEFT JOIN Transactions p ON t.parent_transaction_id = p.id
      WHERE t.id = ?;
      """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int64(statement, 1, Int64(id))
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return (nil, nil)
        }
        
        // Parse main transaction
        let transaction = try parseTransactionFromStatement(statement, startIndex: 0)
        
        // Parse parent transaction if exists
        var parent: Transaction?
        if sqlite3_column_type(statement, 13) != SQLITE_NULL {
            parent = try parseTransactionFromStatement(statement, startIndex: 13)
        }
        
        return (transaction, parent)
    }
    
    private func parseTransactionFromStatement(_ statement: OpaquePointer?, startIndex: Int32) throws
    -> Transaction {
        let id = Int(sqlite3_column_int64(statement, startIndex + 0))
        let title = String(cString: sqlite3_column_text(statement, startIndex + 1))
        let catKey = String(cString: sqlite3_column_text(statement, startIndex + 2))
        let typeKey = String(cString: sqlite3_column_text(statement, startIndex + 3))
        let amount = Int(sqlite3_column_int64(statement, startIndex + 4))
        let ts = Int(sqlite3_column_int64(statement, startIndex + 5))
        let monthAnchor = Int(sqlite3_column_int64(statement, startIndex + 6))
        
        let isRecurring: Bool? =
        sqlite3_column_type(statement, startIndex + 7) == SQLITE_NULL
        ? nil : (sqlite3_column_int(statement, startIndex + 7) == 1)
        let hasInstallments: Bool? =
        sqlite3_column_type(statement, startIndex + 8) == SQLITE_NULL
        ? nil : (sqlite3_column_int(statement, startIndex + 8) == 1)
        let parentTransactionId: Int? =
        sqlite3_column_type(statement, startIndex + 9) == SQLITE_NULL
        ? nil : Int(sqlite3_column_int64(statement, startIndex + 9))
        let installmentNumber: Int? =
        sqlite3_column_type(statement, startIndex + 10) == SQLITE_NULL
        ? nil : Int(sqlite3_column_int64(statement, startIndex + 10))
        let totalInstallments: Int? =
        sqlite3_column_type(statement, startIndex + 11) == SQLITE_NULL
        ? nil : Int(sqlite3_column_int64(statement, startIndex + 11))
        let originalAmount: Int? =
        sqlite3_column_type(statement, startIndex + 12) == SQLITE_NULL
        ? nil : Int(sqlite3_column_int64(statement, startIndex + 12))
        
        let dbData = DBTransactionData(
            id: id,
            title: title,
            amount: amount,
            dateTimestamp: ts,
            budgetMonthDate: monthAnchor,
            isRecurring: isRecurring,
            hasInstallments: hasInstallments,
            parentTransactionId: parentTransactionId,
            installmentNumber: installmentNumber,
            totalInstallments: totalInstallments,
            originalAmount: originalAmount,
            category: catKey,
            type: typeKey
        )
        
        let uiData = try UITransactionData(from: dbData)
        return Transaction(data: uiData)
    }
}
