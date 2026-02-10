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

/// SQLITE_TRANSIENT tells SQLite to make its own copy of the string
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

class DBHelper {
    static let shared = DBHelper()
    
    private var db: OpaquePointer?
    private var isInitialized = false
    
    /// Serial queue to ensure thread-safe database access
    private let dbQueue = DispatchQueue(label: "com.finova.dbhelper", qos: .userInitiated)
    
    private init() {
        initializeDatabase()
    }
    
    private func initializeDatabase() {
        do {
            try openDatabase()
            try createBudgetsTable()
            try createTransactionsTable()
            try migrateTransactionsTable()
            try createCreditCardsTable()
            try createCreditCardStatementsTable()
            try migrateCreditCardColumns()
            try migrateCreditCardsTable()
            try migrateCreditCardStatementsTable()
            isInitialized = true
            //            print("✅ Database initialized successfully")
        } catch {
            //            print("⚠️ Database initialization failed: \(error)")
            // Don't crash the app, just log the error
            // This allows the app to continue running in test environments
            isInitialized = false
        }
    }
    
    private func openDatabase() throws {
        let fileURL = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("AppFinance.sqlite")
        
        // Use sqlite3_open_v2 with SQLITE_OPEN_FULLMUTEX for thread-safe serialized mode
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(fileURL.path, &db, flags, nil) != SQLITE_OK {
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
            logWarning("Database not initialized, skipping budget insert")
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
            logWarning("Database not initialized, skipping budget update")
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
            logWarning("Database not initialized, returning empty budget list")
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
            logWarning("Database not initialized, returning false for exists check")
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
            logWarning("Database not initialized, skipping budget delete")
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
            "original_amount",
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
            "original_amount": "ALTER TABLE Transactions ADD COLUMN original_amount INTEGER;",
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
            logWarning("Database not initialized, skipping transaction insert")
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
              original_amount,
              credit_card_id,
              statement_id,
              is_credit_card_statement
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, transaction.data.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, transaction.data.category, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, transaction.data.type, -1, SQLITE_TRANSIENT)
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

        if let creditCardId = transaction.data.creditCardId {
            sqlite3_bind_int64(statement, 13, Int64(creditCardId))
        } else {
            sqlite3_bind_null(statement, 13)
        }

        if let statementId = transaction.data.statementId {
            sqlite3_bind_int64(statement, 14, Int64(statementId))
        } else {
            sqlite3_bind_null(statement, 14)
        }

        if let isCreditCardStatement = transaction.data.isCreditCardStatement {
            sqlite3_bind_int(statement, 15, isCreditCardStatement ? 1 : 0)
        } else {
            sqlite3_bind_null(statement, 15)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }

        return Int(sqlite3_last_insert_rowid(db))
    }
    
    func getTransactions() throws -> [Transaction] {
        guard isInitialized else {
            logWarning("Database not initialized, returning empty transaction list")
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
        original_amount,
        credit_card_id,
        statement_id,
        is_credit_card_statement
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

            let creditCardId: Int? = sqlite3_column_type(statement, 13) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int64(statement, 13))
            let statementId: Int? = sqlite3_column_type(statement, 14) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int64(statement, 14))
            let isCreditCardStatement: Bool? = sqlite3_column_type(statement, 15) == SQLITE_NULL
                ? nil : (sqlite3_column_int(statement, 15) == 1)

            // Default empty type to "expense" to handle corrupt data
            let sanitizedTypeKey = typeKey.isEmpty ? "expense" : typeKey

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
                creditCardId: creditCardId,
                statementId: statementId,
                isCreditCardStatement: isCreditCardStatement,
                category: catKey,
                type: sanitizedTypeKey
            )
            
            do {
                let uiData = try UITransactionData(from: dbData)
                let tx = Transaction(data: uiData)
                results.append(tx)
            } catch {
                logWarning("Failed to convert transaction data: \(error)")
                continue
            }
        }
        return results
    }
    
    func deleteTransaction(id: Int) throws {
        guard isInitialized else {
            logWarning("Database not initialized, skipping transaction delete")
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
        installment_number, total_installments, original_amount,
        credit_card_id, statement_id, is_credit_card_statement
      FROM Transactions
      WHERE has_installments = 1;
      """

        return try executeTransactionQuery(query)
    }
    
    private func executeTransactionQuery(_ query: String, bindValues: [Int] = []) throws
    -> [Transaction]
    {
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
            let creditCardId: Int? =
            sqlite3_column_type(statement, 13) == SQLITE_NULL
            ? nil : Int(sqlite3_column_int64(statement, 13))
            let statementId: Int? =
            sqlite3_column_type(statement, 14) == SQLITE_NULL
            ? nil : Int(sqlite3_column_int64(statement, 14))
            let isCreditCardStatement: Bool? =
            sqlite3_column_type(statement, 15) == SQLITE_NULL
            ? nil : (sqlite3_column_int(statement, 15) == 1)

            let dbData = DBTransactionData(
                id: id, title: title, amount: amount, dateTimestamp: ts, budgetMonthDate: monthAnchor,
                isRecurring: isRecurring, hasInstallments: hasInstallments,
                parentTransactionId: parentTransactionId,
                installmentNumber: installmentNumber, totalInstallments: totalInstallments,
                originalAmount: originalAmount,
                creditCardId: creditCardId, statementId: statementId,
                isCreditCardStatement: isCreditCardStatement,
                category: catKey, type: typeKey
            )
            
            do {
                let uiData = try UITransactionData(from: dbData)
                results.append(Transaction(data: uiData))
            } catch {
                logWarning("Failed to convert transaction data: \(error)")
            }
        }
        
        return results
    }
    
    func updateTransactionParentId(transactionId: Int, parentId: Int) throws {
        guard isInitialized else {
            logWarning("Database not initialized, skipping transaction parent ID update")
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
    
    func getTransactionWithParent(id: Int) throws -> (transaction: Transaction?, parent: Transaction?)
    {
        let query = """
      SELECT
        t.id, t.title, t.category, t.type, t.amount, t.date, t.budget_month_date,
        t.is_recurring, t.has_installments, t.parent_transaction_id,
        t.installment_number, t.total_installments, t.original_amount,
        t.credit_card_id, t.statement_id, t.is_credit_card_statement,
        p.id as parent_id, p.title as parent_title, p.category as parent_category,
        p.type as parent_type, p.amount as parent_amount, p.date as parent_date,
        p.budget_month_date as parent_budget_month_date, p.is_recurring as parent_is_recurring,
        p.has_installments as parent_has_installments, p.parent_transaction_id as parent_parent_id,
        p.installment_number as parent_installment_number, p.total_installments as parent_total_installments,
        p.original_amount as parent_original_amount,
        p.credit_card_id as parent_credit_card_id, p.statement_id as parent_statement_id,
        p.is_credit_card_statement as parent_is_credit_card_statement
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

        // Parse parent transaction if exists (offset 16 because child has 16 columns: 13 base + 3 CC)
        var parent: Transaction?
        if sqlite3_column_type(statement, 16) != SQLITE_NULL {
            parent = try parseTransactionFromStatement(statement, startIndex: 16)
        }
        
        return (transaction, parent)
    }
    
    private func parseTransactionFromStatement(_ statement: OpaquePointer?, startIndex: Int32) throws
    -> Transaction
    {
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
        let creditCardId: Int? =
        sqlite3_column_type(statement, startIndex + 13) == SQLITE_NULL
        ? nil : Int(sqlite3_column_int64(statement, startIndex + 13))
        let statementId: Int? =
        sqlite3_column_type(statement, startIndex + 14) == SQLITE_NULL
        ? nil : Int(sqlite3_column_int64(statement, startIndex + 14))
        let isCreditCardStatement: Bool? =
        sqlite3_column_type(statement, startIndex + 15) == SQLITE_NULL
        ? nil : (sqlite3_column_int(statement, startIndex + 15) == 1)

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
            creditCardId: creditCardId,
            statementId: statementId,
            isCreditCardStatement: isCreditCardStatement,
            category: catKey,
            type: typeKey
        )
        
        let uiData = try UITransactionData(from: dbData)
        return Transaction(data: uiData)
    }
    
    func updateTransaction(_ transaction: TransactionModel) throws {
        guard isInitialized else {
            logWarning("Database not initialized, skipping transaction update")
            return
        }
        
        let updateQuery = """
          UPDATE Transactions SET
            title = ?, category = ?, type = ?, amount = ?, date = ?,
            budget_month_date = ?, is_recurring = ?, has_installments = ?,
            total_installments = ?, original_amount = ?,
            credit_card_id = ?, statement_id = ?, is_credit_card_statement = ?
          WHERE id = ?;
      """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, transaction.data.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, transaction.data.category, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, transaction.data.type, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 4, Int64(transaction.data.amount))
        sqlite3_bind_int64(statement, 5, Int64(transaction.data.dateTimestamp))
        sqlite3_bind_int64(statement, 6, Int64(transaction.data.budgetMonthDate))
        sqlite3_bind_int(statement, 7, transaction.data.isRecurring == true ? 1 : 0)
        sqlite3_bind_int(statement, 8, transaction.data.hasInstallments == true ? 1 : 0)

        if let totalInstallments = transaction.data.totalInstallments {
            sqlite3_bind_int64(statement, 9, Int64(totalInstallments))
        } else {
            sqlite3_bind_null(statement, 9)
        }

        if let originalAmount = transaction.data.originalAmount {
            sqlite3_bind_int64(statement, 10, Int64(originalAmount))
        } else {
            sqlite3_bind_null(statement, 10)
        }

        if let creditCardId = transaction.data.creditCardId {
            sqlite3_bind_int64(statement, 11, Int64(creditCardId))
        } else {
            sqlite3_bind_null(statement, 11)
        }

        if let statementId = transaction.data.statementId {
            sqlite3_bind_int64(statement, 12, Int64(statementId))
        } else {
            sqlite3_bind_null(statement, 12)
        }

        if let isCreditCardStatement = transaction.data.isCreditCardStatement {
            sqlite3_bind_int(statement, 13, isCreditCardStatement ? 1 : 0)
        } else {
            sqlite3_bind_null(statement, 13)
        }

        sqlite3_bind_int64(statement, 14, Int64(transaction.data.id!))
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    func updateSingleTransaction(_ transaction: TransactionModel) throws {
        guard isInitialized else {
            logWarning("Database not initialized, skipping single transaction update")
            return
        }
        
        // Only update the basic fields, preserving mode-related fields
        let updateQuery = """
          UPDATE Transactions SET 
            title = ?, category = ?, type = ?, amount = ?, date = ?, 
            budget_month_date = ?, original_amount = ?
          WHERE id = ?;
      """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, transaction.data.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, transaction.data.category, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, transaction.data.type, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 4, Int64(transaction.data.amount))
        sqlite3_bind_int64(statement, 5, Int64(transaction.data.dateTimestamp))
        sqlite3_bind_int64(statement, 6, Int64(transaction.data.budgetMonthDate))
        sqlite3_bind_int64(
            statement, 7, Int64(transaction.data.originalAmount ?? transaction.data.amount))
        sqlite3_bind_int64(statement, 8, Int64(transaction.data.id!))
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    // MARK: - Recurring Transaction Updates
    
    /// Updates the is_recurring flag for a transaction
    func updateIsRecurring(transactionId: Int, isRecurring: Bool) throws {
        guard isInitialized else {
            logWarning("Database not initialized, skipping is_recurring update")
            return
        }
        
        let updateQuery = "UPDATE Transactions SET is_recurring = ? WHERE id = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, isRecurring ? 1 : 0)
        sqlite3_bind_int64(statement, 2, Int64(transactionId))
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    // MARK: - Batch Operations for Performance
    
    /// Deletes all transactions from the database (for cleanup operations)
    func deleteAllTransactions() throws {
        guard isInitialized else {
            logWarning("Database not initialized, skipping batch transaction delete")
            return
        }
        
        let deleteQuery = "DELETE FROM Transactions;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, deleteQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    /// Deletes all budgets from the database (for cleanup operations)
    func deleteAllBudgets() throws {
        guard isInitialized else {
            logWarning("Database not initialized, skipping batch budget delete")
            return
        }
        
        let deleteQuery = "DELETE FROM Budgets;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, deleteQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    // MARK: - Credit Card Tables
    
    private func createCreditCardsTable() throws {
        let query = """
            CREATE TABLE IF NOT EXISTS CreditCards (
                id                  INTEGER PRIMARY KEY AUTOINCREMENT,
                name                TEXT NOT NULL,
                last_four_digits    TEXT NOT NULL,
                card_brand          TEXT NOT NULL,
                closing_day         INTEGER NOT NULL CHECK (closing_day BETWEEN 1 AND 28),
                due_day             INTEGER NOT NULL CHECK (due_day BETWEEN 1 AND 28),
                credit_limit        INTEGER,
                card_color          TEXT NOT NULL DEFAULT 'blue',
                user_id             TEXT NOT NULL,
                is_deleted          INTEGER NOT NULL DEFAULT 0,
                created_at          INTEGER NOT NULL,
                updated_at          INTEGER NOT NULL
            );
            """
        
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
    
    private func createCreditCardStatementsTable() throws {
        let query = """
          CREATE TABLE IF NOT EXISTS CreditCardStatements (
              id              INTEGER PRIMARY KEY AUTOINCREMENT,
              credit_card_id  INTEGER NOT NULL,
              closing_date    INTEGER NOT NULL,
              due_date        INTEGER NOT NULL,
              total_amount    INTEGER NOT NULL DEFAULT 0,
              is_paid         INTEGER NOT NULL DEFAULT 0,
              paid_date       INTEGER,
              paid_amount     INTEGER,
              user_id         TEXT NOT NULL,
              created_at      INTEGER NOT NULL,
              updated_at      INTEGER NOT NULL,
              FOREIGN KEY (credit_card_id) REFERENCES CreditCards(id) ON DELETE CASCADE
          );
          
          CREATE INDEX IF NOT EXISTS idx_stmt_card_id ON CreditCardStatements(credit_card_id);
          CREATE INDEX IF NOT EXISTS idx_stmt_due_date ON CreditCardStatements(due_date);
          """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db)!)
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    private func migrateCreditCardColumns() throws {
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
        
        let ccColumns: [String: String] = [
            "credit_card_id": "ALTER TABLE Transactions ADD COLUMN credit_card_id INTEGER;",
            "statement_id": "ALTER TABLE Transactions ADD COLUMN statement_id INTEGER;",
            "is_credit_card_statement": "ALTER TABLE Transactions ADD COLUMN is_credit_card_statement INTEGER DEFAULT 0;",
        ]
        
        for (column, alterQuery) in ccColumns {
            if !existingColumns.contains(column) {
                var alterStatement: OpaquePointer?
                guard sqlite3_prepare_v2(db, alterQuery, -1, &alterStatement, nil) == SQLITE_OK else {
                    let msg = String(cString: sqlite3_errmsg(db))
                    throw DBError.prepareFailed(message: msg)
                }
                defer { sqlite3_finalize(alterStatement) }
                guard sqlite3_step(alterStatement) == SQLITE_DONE else {
                    let msg = String(cString: sqlite3_errmsg(db))
                    throw DBError.stepFailed(message: msg)
                }
            }
        }
    }
    
    private func migrateCreditCardsTable() throws {
        let checkQuery = "PRAGMA table_info(CreditCards);"
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

        if !existingColumns.contains("is_default") {
            let alterQuery = "ALTER TABLE CreditCards ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0;"
            var alterStatement: OpaquePointer?
            guard sqlite3_prepare_v2(db, alterQuery, -1, &alterStatement, nil) == SQLITE_OK else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DBError.prepareFailed(message: msg)
            }
            defer { sqlite3_finalize(alterStatement) }
            guard sqlite3_step(alterStatement) == SQLITE_DONE else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DBError.stepFailed(message: msg)
            }
        }
    }

    private func migrateCreditCardStatementsTable() throws {
        let checkQuery = "PRAGMA table_info(CreditCardStatements);"
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

        if !existingColumns.contains("is_dates_overridden") {
            let alterQuery = "ALTER TABLE CreditCardStatements ADD COLUMN is_dates_overridden INTEGER NOT NULL DEFAULT 0;"
            var alterStatement: OpaquePointer?
            guard sqlite3_prepare_v2(db, alterQuery, -1, &alterStatement, nil) == SQLITE_OK else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DBError.prepareFailed(message: msg)
            }
            defer { sqlite3_finalize(alterStatement) }
            guard sqlite3_step(alterStatement) == SQLITE_DONE else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DBError.stepFailed(message: msg)
            }
        }
    }

    // MARK: - Credit Card CRUD
    
    func insertCreditCard(
        name: String, lastFourDigits: String, cardBrand: String,
        closingDay: Int, dueDay: Int, creditLimit: Int?,
        cardColor: String, userId: String, isDefault: Bool = false
    ) throws -> Int {
        guard isInitialized else { return 0 }

        let query = """
        INSERT INTO CreditCards (
          name, last_four_digits, card_brand, closing_day, due_day,
          credit_limit, card_color, user_id, is_deleted, is_default, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }

        let now = Int64(Date().timeIntervalSince1970)

        sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, lastFourDigits, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, cardBrand, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 4, Int32(closingDay))
        sqlite3_bind_int(statement, 5, Int32(dueDay))
        if let limit = creditLimit {
            sqlite3_bind_int64(statement, 6, Int64(limit))
        } else {
            sqlite3_bind_null(statement, 6)
        }
        sqlite3_bind_text(statement, 7, cardColor, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 8, userId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 9, isDefault ? 1 : 0)
        sqlite3_bind_int64(statement, 10, now)
        sqlite3_bind_int64(statement, 11, now)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }

        return Int(sqlite3_last_insert_rowid(db))
    }
    
    func getCreditCards(userId: String) throws -> [(id: Int, name: String, lastFourDigits: String, cardBrand: String, closingDay: Int, dueDay: Int, creditLimit: Int?, cardColor: String, isDeleted: Bool, isDefault: Bool, createdAt: Int, updatedAt: Int)] {
        guard isInitialized else { return [] }

        let query = """
        SELECT id, name, last_four_digits, card_brand, closing_day, due_day,
               credit_limit, card_color, is_deleted, is_default, created_at, updated_at
        FROM CreditCards WHERE user_id = ? AND is_deleted = 0
        ORDER BY created_at DESC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, userId, -1, SQLITE_TRANSIENT)

        var results: [(id: Int, name: String, lastFourDigits: String, cardBrand: String, closingDay: Int, dueDay: Int, creditLimit: Int?, cardColor: String, isDeleted: Bool, isDefault: Bool, createdAt: Int, updatedAt: Int)] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int64(statement, 0))
            let name = String(cString: sqlite3_column_text(statement, 1))
            let lastFour = String(cString: sqlite3_column_text(statement, 2))
            let brand = String(cString: sqlite3_column_text(statement, 3))
            let closing = Int(sqlite3_column_int(statement, 4))
            let due = Int(sqlite3_column_int(statement, 5))
            let limit: Int? = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 6))
            let color = String(cString: sqlite3_column_text(statement, 7))
            let deleted = sqlite3_column_int(statement, 8) == 1
            let isDefault = sqlite3_column_int(statement, 9) == 1
            let createdAt = Int(sqlite3_column_int64(statement, 10))
            let updatedAt = Int(sqlite3_column_int64(statement, 11))

            results.append((id, name, lastFour, brand, closing, due, limit, color, deleted, isDefault, createdAt, updatedAt))
        }

        return results
    }
    
    func getCreditCard(id: Int) throws -> (id: Int, name: String, lastFourDigits: String, cardBrand: String, closingDay: Int, dueDay: Int, creditLimit: Int?, cardColor: String, userId: String, isDeleted: Bool, isDefault: Bool, createdAt: Int, updatedAt: Int)? {
        guard isInitialized else { return nil }

        let query = "SELECT id, name, last_four_digits, card_brand, closing_day, due_day, credit_limit, card_color, user_id, is_deleted, is_default, created_at, updated_at FROM CreditCards WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(id))

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        return (
            Int(sqlite3_column_int64(statement, 0)),
            String(cString: sqlite3_column_text(statement, 1)),
            String(cString: sqlite3_column_text(statement, 2)),
            String(cString: sqlite3_column_text(statement, 3)),
            Int(sqlite3_column_int(statement, 4)),
            Int(sqlite3_column_int(statement, 5)),
            sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 6)),
            String(cString: sqlite3_column_text(statement, 7)),
            String(cString: sqlite3_column_text(statement, 8)),
            sqlite3_column_int(statement, 9) == 1,
            sqlite3_column_int(statement, 10) == 1,
            Int(sqlite3_column_int64(statement, 11)),
            Int(sqlite3_column_int64(statement, 12))
        )
    }
    
    func updateCreditCard(id: Int, name: String, lastFourDigits: String, cardBrand: String, closingDay: Int, dueDay: Int, creditLimit: Int?, cardColor: String, isDefault: Bool = false) throws {
        guard isInitialized else { return }

        let query = """
        UPDATE CreditCards SET name = ?, last_four_digits = ?, card_brand = ?,
        closing_day = ?, due_day = ?, credit_limit = ?, card_color = ?, is_default = ?, updated_at = ?
        WHERE id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, lastFourDigits, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, cardBrand, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 4, Int32(closingDay))
        sqlite3_bind_int(statement, 5, Int32(dueDay))
        if let limit = creditLimit { sqlite3_bind_int64(statement, 6, Int64(limit)) } else { sqlite3_bind_null(statement, 6) }
        sqlite3_bind_text(statement, 7, cardColor, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 8, isDefault ? 1 : 0)
        sqlite3_bind_int64(statement, 9, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(statement, 10, Int64(id))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    func softDeleteCreditCard(id: Int) throws {
        guard isInitialized else { return }
        let query = "UPDATE CreditCards SET is_deleted = 1, updated_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(statement, 2, Int64(id))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    func clearDefaultCard(userId: String) throws {
        guard isInitialized else { return }
        let query = "UPDATE CreditCards SET is_default = 0, updated_at = ? WHERE user_id = ? AND is_default = 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_text(statement, 2, userId, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }

    // MARK: - Statement CRUD
    
    func insertStatement(creditCardId: Int, closingDate: Int, dueDate: Int, totalAmount: Int, userId: String) throws -> Int {
        guard isInitialized else { return 0 }
        let query = """
        INSERT INTO CreditCardStatements (
          credit_card_id, closing_date, due_date, total_amount, is_paid, user_id, created_at, updated_at
        ) VALUES (?, ?, ?, ?, 0, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        
        let now = Int64(Date().timeIntervalSince1970)
        sqlite3_bind_int64(statement, 1, Int64(creditCardId))
        sqlite3_bind_int64(statement, 2, Int64(closingDate))
        sqlite3_bind_int64(statement, 3, Int64(dueDate))
        sqlite3_bind_int64(statement, 4, Int64(totalAmount))
        sqlite3_bind_text(statement, 5, userId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 6, now)
        sqlite3_bind_int64(statement, 7, now)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
        return Int(sqlite3_last_insert_rowid(db))
    }
    
    func getStatements(creditCardId: Int) throws -> [(id: Int, creditCardId: Int, closingDate: Int, dueDate: Int, totalAmount: Int, isPaid: Bool, paidDate: Int?, paidAmount: Int?, userId: String, isDatesOverridden: Bool, createdAt: Int, updatedAt: Int)] {
        guard isInitialized else { return [] }
        let query = "SELECT id, credit_card_id, closing_date, due_date, total_amount, is_paid, paid_date, paid_amount, user_id, is_dates_overridden, created_at, updated_at FROM CreditCardStatements WHERE credit_card_id = ? ORDER BY due_date DESC;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(creditCardId))

        var results: [(id: Int, creditCardId: Int, closingDate: Int, dueDate: Int, totalAmount: Int, isPaid: Bool, paidDate: Int?, paidAmount: Int?, userId: String, isDatesOverridden: Bool, createdAt: Int, updatedAt: Int)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append((
                Int(sqlite3_column_int64(statement, 0)),
                Int(sqlite3_column_int64(statement, 1)),
                Int(sqlite3_column_int64(statement, 2)),
                Int(sqlite3_column_int64(statement, 3)),
                Int(sqlite3_column_int64(statement, 4)),
                sqlite3_column_int(statement, 5) == 1,
                sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 6)),
                sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 7)),
                String(cString: sqlite3_column_text(statement, 8)),
                sqlite3_column_int(statement, 9) == 1,
                Int(sqlite3_column_int64(statement, 10)),
                Int(sqlite3_column_int64(statement, 11))
            ))
        }
        return results
    }
    
    func findStatement(creditCardId: Int, closingDate: Int) throws -> Int? {
        guard isInitialized else { return nil }
        let query = "SELECT id FROM CreditCardStatements WHERE credit_card_id = ? AND closing_date = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(creditCardId))
        sqlite3_bind_int64(statement, 2, Int64(closingDate))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }
    
    func deleteStatement(statementId: Int) throws {
        guard isInitialized else { return }
        let query = "DELETE FROM CreditCardStatements WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(statementId))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }

    func updateStatementTotal(statementId: Int, totalAmount: Int) throws {
        guard isInitialized else { return }
        let query = "UPDATE CreditCardStatements SET total_amount = ?, updated_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(totalAmount))
        sqlite3_bind_int64(statement, 2, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(statement, 3, Int64(statementId))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    func markStatementAsPaid(statementId: Int, paidAmount: Int?, paidDate: Int) throws {
        guard isInitialized else { return }
        let query = "UPDATE CreditCardStatements SET is_paid = 1, paid_amount = ?, paid_date = ?, updated_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        if let amount = paidAmount { sqlite3_bind_int64(statement, 1, Int64(amount)) } else { sqlite3_bind_null(statement, 1) }
        sqlite3_bind_int64(statement, 2, Int64(paidDate))
        sqlite3_bind_int64(statement, 3, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(statement, 4, Int64(statementId))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    func updateStatementDates(statementId: Int, closingDate: Int, dueDate: Int, isDatesOverridden: Bool = false) throws {
        guard isInitialized else { return }
        let query = "UPDATE CreditCardStatements SET closing_date = ?, due_date = ?, is_dates_overridden = ?, updated_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(closingDate))
        sqlite3_bind_int64(statement, 2, Int64(dueDate))
        sqlite3_bind_int(statement, 3, isDatesOverridden ? 1 : 0)
        sqlite3_bind_int64(statement, 4, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(statement, 5, Int64(statementId))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }

    func updateTransactionCreditCardFields(transactionId: Int, creditCardId: Int, statementId: Int, isCreditCardStatement: Bool) throws {
        guard isInitialized else { return }
        let query = "UPDATE Transactions SET credit_card_id = ?, statement_id = ?, is_credit_card_statement = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(creditCardId))
        sqlite3_bind_int64(statement, 2, Int64(statementId))
        sqlite3_bind_int(statement, 3, isCreditCardStatement ? 1 : 0)
        sqlite3_bind_int64(statement, 4, Int64(transactionId))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }

    func clearTransactionCreditCardFields(transactionId: Int) throws {
        guard isInitialized else { return }
        let query = "UPDATE Transactions SET credit_card_id = NULL, statement_id = NULL, is_credit_card_statement = 0 WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(transactionId))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }

    func getTransactionCountForStatement(statementId: Int) throws -> Int {
        guard isInitialized else { return 0 }
        let query = "SELECT COUNT(*) FROM Transactions WHERE statement_id = ? AND is_credit_card_statement = 0;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(statementId))
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func getTransactionSumForStatement(statementId: Int) throws -> Int {
        guard isInitialized else { return 0 }
        let query = "SELECT COALESCE(SUM(amount), 0) FROM Transactions WHERE statement_id = ? AND is_credit_card_statement = 0;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(statementId))
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }
}
