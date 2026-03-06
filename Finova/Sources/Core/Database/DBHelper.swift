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
            try createBudgetGroupsTable()
            try createGroupMembersTable()
            try createGroupInvitationsTable()
            try createSyncMetadataTable()
            try migrateExistingTablesForSync()
            try migrateUserIdColumns()
            try migrateSyncColumnsV2()
            try createBudgetAllocationsTable()
            try migrateSyncColumnsV3()
            try migrateSyncColumnsV4()
            try migrateSyncColumnsV5()
            try migrateBudgetGroupsAddZoneOwner()
            isInitialized = true
            performSyncFixMigration()
            performParentIdFixMigration()
            performPendingModifiedAtMigration()
            performUpdatedAtBackfill()
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

        let uid = UIDUserDefaultsManager.shared.currentUserUID
        let insertQuery = "INSERT INTO Budgets (month_date, amount, user_id, ck_modified_at, updated_at) VALUES (?, ?, ?, ?, ?);"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(monthDate))
        sqlite3_bind_int64(statement, 2, Int64(amount))
        if let uid = uid {
            sqlite3_bind_text(statement, 3, uid, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        let now = Int64(Date().timeIntervalSince1970)
        sqlite3_bind_int64(statement, 4, now)
        sqlite3_bind_int64(statement, 5, now)

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

        let updateQuery: String
        if let uid = UIDUserDefaultsManager.shared.currentUserUID {
            updateQuery = "UPDATE Budgets SET amount = ?, sync_status = 'pending', ck_modified_at = ?, updated_at = ? WHERE month_date = ? AND user_id = ?;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) == SQLITE_OK else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DBError.prepareFailed(message: msg)
            }
            defer { sqlite3_finalize(statement) }
            let now = Int64(Date().timeIntervalSince1970)
            sqlite3_bind_int64(statement, 1, Int64(amount))
            sqlite3_bind_int64(statement, 2, now)
            sqlite3_bind_int64(statement, 3, now)
            sqlite3_bind_int64(statement, 4, Int64(monthDate))
            sqlite3_bind_text(statement, 5, uid, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DBError.stepFailed(message: msg)
            }
        } else {
            updateQuery = "UPDATE Budgets SET amount = ?, sync_status = 'pending', ck_modified_at = ?, updated_at = ? WHERE month_date = ?;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) == SQLITE_OK else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DBError.prepareFailed(message: msg)
            }
            defer { sqlite3_finalize(statement) }
            let now = Int64(Date().timeIntervalSince1970)
            sqlite3_bind_int64(statement, 1, Int64(amount))
            sqlite3_bind_int64(statement, 2, now)
            sqlite3_bind_int64(statement, 3, now)
            sqlite3_bind_int64(statement, 4, Int64(monthDate))
            guard sqlite3_step(statement) == SQLITE_DONE else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DBError.stepFailed(message: msg)
            }
        }
    }
    
    func getBudgets() throws -> [BudgetModel] {
        guard isInitialized else {
            logWarning("Database not initialized, returning empty budget list")
            return []
        }
        
        let getBudgetsQuery = "SELECT month_date, amount FROM Budgets WHERE (is_deleted IS NULL OR is_deleted = 0);"
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

        if let uid = UIDUserDefaultsManager.shared.currentUserUID {
            let deleteQuery = "DELETE FROM Budgets WHERE month_date = ? AND user_id = ?;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, deleteQuery, -1, &statement, nil) == SQLITE_OK else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DBError.prepareFailed(message: msg)
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, Int64(monthDate))
            sqlite3_bind_text(statement, 2, uid, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DBError.stepFailed(message: msg)
            }
        } else {
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
              is_credit_card_statement,
              user_id,
              ck_modified_at,
              updated_at
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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

        if let uid = UIDUserDefaultsManager.shared.currentUserUID {
            sqlite3_bind_text(statement, 16, uid, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 16)
        }

        let now = Int64(Date().timeIntervalSince1970)
        sqlite3_bind_int64(statement, 17, now)
        sqlite3_bind_int64(statement, 18, now)

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
      FROM Transactions
      WHERE (is_deleted IS NULL OR is_deleted = 0);
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
        
        let updateQuery = "UPDATE Transactions SET parent_transaction_id = ?, sync_status = 'pending', ck_modified_at = ?, updated_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        let now = Int64(Date().timeIntervalSince1970)
        sqlite3_bind_int64(statement, 1, Int64(parentId))
        sqlite3_bind_int64(statement, 2, now)
        sqlite3_bind_int64(statement, 3, now)
        sqlite3_bind_int64(statement, 4, Int64(transactionId))
        
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
            credit_card_id = ?, statement_id = ?, is_credit_card_statement = ?,
            sync_status = 'pending', ck_modified_at = ?, updated_at = ?
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

        let now = Int64(Date().timeIntervalSince1970)
        sqlite3_bind_int64(statement, 14, now)
        sqlite3_bind_int64(statement, 15, now)
        sqlite3_bind_int64(statement, 16, Int64(transaction.data.id!))
        
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
            budget_month_date = ?, original_amount = ?,
            sync_status = 'pending', ck_modified_at = ?, updated_at = ?
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
        let now = Int64(Date().timeIntervalSince1970)
        sqlite3_bind_int64(statement, 8, now)
        sqlite3_bind_int64(statement, 9, now)
        sqlite3_bind_int64(statement, 10, Int64(transaction.data.id!))
        
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
        
        let updateQuery = "UPDATE Transactions SET is_recurring = ?, sync_status = 'pending', ck_modified_at = ?, updated_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        
        defer { sqlite3_finalize(statement) }
        
        let now = Int64(Date().timeIntervalSince1970)
        sqlite3_bind_int(statement, 1, isRecurring ? 1 : 0)
        sqlite3_bind_int64(statement, 2, now)
        sqlite3_bind_int64(statement, 3, now)
        sqlite3_bind_int64(statement, 4, Int64(transactionId))
        
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
    
    func fetchBudgetsForGroup(groupId: String) throws -> [BudgetModel] {
        guard isInitialized else { return [] }
        let query = "SELECT month_date, amount FROM Budgets WHERE shared_group_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (groupId as NSString).utf8String, -1, nil)
        var results: [BudgetModel] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let monthDate = Int(sqlite3_column_int64(statement, 0))
            let amount = Int(sqlite3_column_int64(statement, 1))
            results.append(BudgetModel(monthDate: monthDate, amount: amount))
        }
        return results
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
          credit_limit, card_color, user_id, is_deleted, is_default, created_at, updated_at, ck_modified_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?);
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
        sqlite3_bind_int64(statement, 12, now)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }

        return Int(sqlite3_last_insert_rowid(db))
    }
    
    func getCreditCards(userId: String) throws -> [(id: Int, name: String, lastFourDigits: String, cardBrand: String, closingDay: Int, dueDay: Int, creditLimit: Int?, cardColor: String, isDeleted: Bool, isDefault: Bool, createdAt: Int, updatedAt: Int, sharedGroupId: String?)] {
        guard isInitialized else { return [] }

        let query = """
        SELECT id, name, last_four_digits, card_brand, closing_day, due_day,
               credit_limit, card_color, is_deleted, is_default, created_at, updated_at, shared_group_id
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

        var results: [(id: Int, name: String, lastFourDigits: String, cardBrand: String, closingDay: Int, dueDay: Int, creditLimit: Int?, cardColor: String, isDeleted: Bool, isDefault: Bool, createdAt: Int, updatedAt: Int, sharedGroupId: String?)] = []

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
            let sharedGroupId: String? = sqlite3_column_type(statement, 12) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 12))

            results.append((id, name, lastFour, brand, closing, due, limit, color, deleted, isDefault, createdAt, updatedAt, sharedGroupId))
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
        closing_day = ?, due_day = ?, credit_limit = ?, card_color = ?, is_default = ?, updated_at = ?,
        sync_status = 'pending', ck_modified_at = ?
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
        sqlite3_bind_int64(statement, 10, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(statement, 11, Int64(id))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    func softDeleteCreditCard(id: Int) throws {
        guard isInitialized else { return }
        let query = "UPDATE CreditCards SET is_deleted = 1, updated_at = ?, sync_status = 'pendingDelete', ck_modified_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(statement, 2, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(statement, 3, Int64(id))
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

    func getCreditCardsForGroup(groupId: String) throws -> [(id: Int, name: String, lastFourDigits: String, cardBrand: String, closingDay: Int, dueDay: Int, creditLimit: Int?, cardColor: String, userId: String, isDeleted: Bool, isDefault: Bool, createdAt: Int, updatedAt: Int)] {
        guard isInitialized else { return [] }

        let query = """
        SELECT id, name, last_four_digits, card_brand, closing_day, due_day,
               credit_limit, card_color, user_id, is_deleted, is_default, created_at, updated_at
        FROM CreditCards WHERE shared_group_id = ? AND is_deleted = 0
        ORDER BY created_at DESC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, groupId, -1, SQLITE_TRANSIENT)

        var results: [(id: Int, name: String, lastFourDigits: String, cardBrand: String, closingDay: Int, dueDay: Int, creditLimit: Int?, cardColor: String, userId: String, isDeleted: Bool, isDefault: Bool, createdAt: Int, updatedAt: Int)] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int64(statement, 0))
            let name = String(cString: sqlite3_column_text(statement, 1))
            let lastFour = String(cString: sqlite3_column_text(statement, 2))
            let brand = String(cString: sqlite3_column_text(statement, 3))
            let closing = Int(sqlite3_column_int(statement, 4))
            let due = Int(sqlite3_column_int(statement, 5))
            let limit: Int? = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 6))
            let color = String(cString: sqlite3_column_text(statement, 7))
            let userId = String(cString: sqlite3_column_text(statement, 8))
            let deleted = sqlite3_column_int(statement, 9) == 1
            let isDefault = sqlite3_column_int(statement, 10) == 1
            let createdAt = Int(sqlite3_column_int64(statement, 11))
            let updatedAt = Int(sqlite3_column_int64(statement, 12))

            results.append((id: id, name: name, lastFourDigits: lastFour, cardBrand: brand, closingDay: closing, dueDay: due, creditLimit: limit, cardColor: color, userId: userId, isDeleted: deleted, isDefault: isDefault, createdAt: createdAt, updatedAt: updatedAt))
        }

        return results
    }

    // MARK: - Statement CRUD
    
    func insertStatement(creditCardId: Int, closingDate: Int, dueDate: Int, totalAmount: Int, userId: String) throws -> Int {
        guard isInitialized else { return 0 }
        let query = """
        INSERT INTO CreditCardStatements (
          credit_card_id, closing_date, due_date, total_amount, is_paid, user_id, created_at, updated_at, ck_modified_at
        ) VALUES (?, ?, ?, ?, 0, ?, ?, ?, ?);
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
        sqlite3_bind_int64(statement, 8, now)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
        return Int(sqlite3_last_insert_rowid(db))
    }
    
    func getStatements(creditCardId: Int) throws -> [(id: Int, creditCardId: Int, closingDate: Int, dueDate: Int, totalAmount: Int, isPaid: Bool, paidDate: Int?, paidAmount: Int?, userId: String, isDatesOverridden: Bool, createdAt: Int, updatedAt: Int)] {
        guard isInitialized else { return [] }
        let query = "SELECT id, credit_card_id, closing_date, due_date, total_amount, is_paid, paid_date, paid_amount, user_id, is_dates_overridden, created_at, updated_at FROM CreditCardStatements WHERE credit_card_id = ? AND (is_deleted IS NULL OR is_deleted = 0) ORDER BY due_date DESC;"
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
    
    func getStatement(byId id: Int) throws -> (id: Int, creditCardId: Int, closingDate: Int, dueDate: Int, totalAmount: Int, isPaid: Bool, paidDate: Int?, paidAmount: Int?, userId: String, isDatesOverridden: Bool, createdAt: Int, updatedAt: Int)? {
        guard isInitialized else { return nil }
        let query = "SELECT id, credit_card_id, closing_date, due_date, total_amount, is_paid, paid_date, paid_amount, user_id, is_dates_overridden, created_at, updated_at FROM CreditCardStatements WHERE id = ?;"
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
        )
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
        let query = "UPDATE CreditCardStatements SET total_amount = ?, updated_at = ?, sync_status = 'pending', ck_modified_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(totalAmount))
        sqlite3_bind_int64(statement, 2, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(statement, 3, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(statement, 4, Int64(statementId))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    func markStatementAsPaid(statementId: Int, paidAmount: Int?, paidDate: Int) throws {
        guard isInitialized else { return }
        let query = "UPDATE CreditCardStatements SET is_paid = 1, paid_amount = ?, paid_date = ?, updated_at = ?, sync_status = 'pending', ck_modified_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        if let amount = paidAmount { sqlite3_bind_int64(statement, 1, Int64(amount)) } else { sqlite3_bind_null(statement, 1) }
        sqlite3_bind_int64(statement, 2, Int64(paidDate))
        sqlite3_bind_int64(statement, 3, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(statement, 4, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(statement, 5, Int64(statementId))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }
    
    func updateStatementDates(statementId: Int, closingDate: Int, dueDate: Int, isDatesOverridden: Bool = false) throws {
        guard isInitialized else { return }
        let query = "UPDATE CreditCardStatements SET closing_date = ?, due_date = ?, is_dates_overridden = ?, updated_at = ?, sync_status = 'pending', ck_modified_at = ? WHERE id = ?;"
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
        sqlite3_bind_int64(statement, 5, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(statement, 6, Int64(statementId))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }

    func updateTransactionCreditCardFields(transactionId: Int, creditCardId: Int, statementId: Int, isCreditCardStatement: Bool) throws {
        guard isInitialized else { return }
        let query = "UPDATE Transactions SET credit_card_id = ?, statement_id = ?, is_credit_card_statement = ?, sync_status = 'pending', ck_modified_at = ?, updated_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        let now = Int64(Date().timeIntervalSince1970)
        sqlite3_bind_int64(statement, 1, Int64(creditCardId))
        sqlite3_bind_int64(statement, 2, Int64(statementId))
        sqlite3_bind_int(statement, 3, isCreditCardStatement ? 1 : 0)
        sqlite3_bind_int64(statement, 4, now)
        sqlite3_bind_int64(statement, 5, now)
        sqlite3_bind_int64(statement, 6, Int64(transactionId))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }

    func clearTransactionCreditCardFields(transactionId: Int) throws {
        guard isInitialized else { return }
        let query = "UPDATE Transactions SET credit_card_id = NULL, statement_id = NULL, is_credit_card_statement = 0, sync_status = 'pending', ck_modified_at = ?, updated_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        let now = Int64(Date().timeIntervalSince1970)
        sqlite3_bind_int64(statement, 1, now)
        sqlite3_bind_int64(statement, 2, now)
        sqlite3_bind_int64(statement, 3, Int64(transactionId))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.stepFailed(message: msg)
        }
    }

    func getSharedGroupId(transactionId: Int) -> String? {
        guard isInitialized else { return nil }
        let query = "SELECT shared_group_id FROM Transactions WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(transactionId))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
        return String(cString: sqlite3_column_text(statement, 0))
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
        let query = "SELECT COALESCE(SUM(amount), 0) FROM Transactions WHERE statement_id = ? AND is_credit_card_statement = 0 AND (is_deleted IS NULL OR is_deleted = 0);"
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

    // MARK: - Budget Groups Tables

    private func createBudgetGroupsTable() throws {
        let query = """
            CREATE TABLE IF NOT EXISTS BudgetGroups (
                id                TEXT PRIMARY KEY,
                name              TEXT NOT NULL,
                owner_id          TEXT NOT NULL,
                owner_name        TEXT NOT NULL,
                owner_email       TEXT NOT NULL,
                currency          TEXT NOT NULL DEFAULT 'BRL',
                ck_record_id      TEXT,
                ck_share_url      TEXT,
                created_at        INTEGER NOT NULL,
                updated_at        INTEGER NOT NULL,
                is_deleted        INTEGER NOT NULL DEFAULT 0
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

    private func createGroupMembersTable() throws {
        let query = """
            CREATE TABLE IF NOT EXISTS GroupMembers (
                id                TEXT PRIMARY KEY,
                group_id          TEXT NOT NULL,
                user_id           TEXT NOT NULL,
                name              TEXT NOT NULL,
                email             TEXT NOT NULL,
                role              TEXT NOT NULL DEFAULT 'member',
                permissions       TEXT NOT NULL DEFAULT '{}',
                last_active       INTEGER,
                joined_at         INTEGER NOT NULL,
                is_removed        INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (group_id) REFERENCES BudgetGroups(id)
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

    private func createGroupInvitationsTable() throws {
        let query = """
            CREATE TABLE IF NOT EXISTS GroupInvitations (
                id                TEXT PRIMARY KEY,
                group_id          TEXT NOT NULL,
                group_name        TEXT NOT NULL,
                inviter_name      TEXT NOT NULL,
                inviter_email     TEXT NOT NULL,
                invitee_email     TEXT NOT NULL,
                status            TEXT NOT NULL DEFAULT 'pending',
                ck_share_url      TEXT,
                created_at        INTEGER NOT NULL,
                responded_at      INTEGER,
                FOREIGN KEY (group_id) REFERENCES BudgetGroups(id)
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

    private func createSyncMetadataTable() throws {
        let query = """
            CREATE TABLE IF NOT EXISTS SyncMetadata (
                record_type       TEXT PRIMARY KEY,
                change_token      BLOB,
                last_sync_date    INTEGER NOT NULL,
                sync_status       TEXT NOT NULL DEFAULT 'idle'
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

    // MARK: - Sync Column Migrations

    private func migrateExistingTablesForSync() throws {
        // Add sync + sharing columns to Transactions
        try addColumnIfNotExists(table: "Transactions", column: "ck_record_id", definition: "TEXT")
        try addColumnIfNotExists(table: "Transactions", column: "ck_modified_at", definition: "INTEGER")
        try addColumnIfNotExists(table: "Transactions", column: "sync_status", definition: "TEXT DEFAULT 'pending'")
        try addColumnIfNotExists(table: "Transactions", column: "shared_group_id", definition: "TEXT")

        // Add sync + sharing columns to Budgets
        try addColumnIfNotExists(table: "Budgets", column: "ck_record_id", definition: "TEXT")
        try addColumnIfNotExists(table: "Budgets", column: "sync_status", definition: "TEXT DEFAULT 'pending'")
        try addColumnIfNotExists(table: "Budgets", column: "shared_group_id", definition: "TEXT")

        // Add sync + sharing columns to CreditCards
        try addColumnIfNotExists(table: "CreditCards", column: "ck_record_id", definition: "TEXT")
        try addColumnIfNotExists(table: "CreditCards", column: "sync_status", definition: "TEXT DEFAULT 'pending'")
        try addColumnIfNotExists(table: "CreditCards", column: "shared_group_id", definition: "TEXT")

        // Add sync columns to CreditCardStatements
        try addColumnIfNotExists(table: "CreditCardStatements", column: "ck_record_id", definition: "TEXT")
        try addColumnIfNotExists(table: "CreditCardStatements", column: "sync_status", definition: "TEXT DEFAULT 'pending'")
    }

    // MARK: - User ID Migration

    private func migrateUserIdColumns() throws {
        try addColumnIfNotExists(table: "Transactions", column: "user_id", definition: "TEXT")
        try addColumnIfNotExists(table: "Budgets", column: "user_id", definition: "TEXT")
    }

    private func migrateSyncColumnsV2() throws {
        try addColumnIfNotExists(table: "Budgets", column: "ck_modified_at", definition: "INTEGER")
        try addColumnIfNotExists(table: "CreditCards", column: "ck_modified_at", definition: "INTEGER")
        try addColumnIfNotExists(table: "CreditCardStatements", column: "ck_modified_at", definition: "INTEGER")
    }

    private func migrateSyncColumnsV4() throws {
        let tables = ["Transactions", "Budgets", "CreditCards", "CreditCardStatements", "BudgetAllocations"]
        for table in tables {
            try addColumnIfNotExists(table: table, column: "ck_system_fields", definition: "BLOB")
        }
    }

    private func migrateSyncColumnsV5() throws {
        // Add updated_at to tables that don't have it yet (CreditCards and CreditCardStatements already have it)
        try addColumnIfNotExists(table: "Transactions", column: "updated_at", definition: "INTEGER")
        try addColumnIfNotExists(table: "Budgets", column: "updated_at", definition: "INTEGER")
        try addColumnIfNotExists(table: "BudgetAllocations", column: "updated_at", definition: "INTEGER")
    }

    private func migrateBudgetGroupsAddZoneOwner() throws {
        try addColumnIfNotExists(table: "BudgetGroups", column: "ck_zone_owner", definition: "TEXT")
    }

    private func migrateSyncColumnsV3() throws {
        // Phase 0A: Add is_deleted column to tables that don't have it yet
        try addColumnIfNotExists(table: "Transactions", column: "is_deleted", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNotExists(table: "Budgets", column: "is_deleted", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNotExists(table: "BudgetAllocations", column: "is_deleted", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNotExists(table: "CreditCardStatements", column: "is_deleted", definition: "INTEGER NOT NULL DEFAULT 0")

        // Phase 4B: Add ck_parent_record_name for cross-device parent ID resolution
        try addColumnIfNotExists(table: "Transactions", column: "ck_parent_record_name", definition: "TEXT")

        // Phase 3D: Add UNIQUE indexes on ck_record_id (with deduplication first)
        let tables = ["Transactions", "Budgets", "CreditCards", "CreditCardStatements", "BudgetAllocations"]
        let idColumn: [String: String] = [
            "Transactions": "id",
            "Budgets": "rowid",
            "CreditCards": "id",
            "CreditCardStatements": "id",
            "BudgetAllocations": "id"
        ]

        for table in tables {
            let col = idColumn[table] ?? "rowid"
            // Deduplicate: keep row with lowest id per ck_record_id
            let dedup = """
                DELETE FROM \(table) WHERE \(col) NOT IN (
                    SELECT MIN(\(col)) FROM \(table) GROUP BY ck_record_id
                ) AND ck_record_id IS NOT NULL;
                """
            var dedupStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, dedup, -1, &dedupStmt, nil) == SQLITE_OK {
                if sqlite3_step(dedupStmt) == SQLITE_DONE {
                    let removed = sqlite3_changes(db)
                    if removed > 0 {
                        logWarning("[MigrateV3] Removed \(removed) duplicate rows from \(table)")
                    }
                }
                sqlite3_finalize(dedupStmt)
            }

            // Create unique index
            let indexName = "idx_\(table.lowercased())_ck_record_id"
            let createIndex = "CREATE UNIQUE INDEX IF NOT EXISTS \(indexName) ON \(table)(ck_record_id) WHERE ck_record_id IS NOT NULL;"
            var indexStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, createIndex, -1, &indexStmt, nil) == SQLITE_OK {
                sqlite3_step(indexStmt)
                sqlite3_finalize(indexStmt)
            }
        }
    }

    private func createBudgetAllocationsTable() throws {
        let query = """
            CREATE TABLE IF NOT EXISTS BudgetAllocations (
                id                    INTEGER PRIMARY KEY AUTOINCREMENT,
                month_date            INTEGER NOT NULL,
                category_key          TEXT NOT NULL,
                allocated_amount      INTEGER NOT NULL,
                is_recurring          INTEGER NOT NULL DEFAULT 0,
                parent_allocation_id  INTEGER,
                user_id               TEXT,
                shared_group_id       TEXT,
                ck_record_id          TEXT,
                ck_modified_at        INTEGER,
                sync_status           TEXT DEFAULT 'pending'
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

    func backfillUserIds(uid: String) {
        guard isInitialized else {
            logWarning("[Backfill] DBHelper not initialized, skipping backfill")
            return
        }
        // Count rows that need backfill before updating
        var txCount: Int = 0
        var budgetCount: Int = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM Transactions WHERE user_id IS NULL;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW { txCount = Int(sqlite3_column_int64(stmt, 0)) }
            sqlite3_finalize(stmt)
        }
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM Budgets WHERE user_id IS NULL;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW { budgetCount = Int(sqlite3_column_int64(stmt, 0)) }
            sqlite3_finalize(stmt)
        }
        if txCount > 0 || budgetCount > 0 {
            logInfo("[Backfill] Setting user_id=\(uid) for \(txCount) transactions and \(budgetCount) budgets")
        }
        executeSyncUpdate("UPDATE Transactions SET user_id = ? WHERE user_id IS NULL;", textBindings: [uid])
        executeSyncUpdate("UPDATE Budgets SET user_id = ? WHERE user_id IS NULL;", textBindings: [uid])

        // Remove duplicate cloud records (keep only the row with the lowest id for each ck_record_id)
        let dedup = """
          DELETE FROM Transactions WHERE id NOT IN (
            SELECT MIN(id) FROM Transactions GROUP BY ck_record_id
          ) AND ck_record_id IS NOT NULL;
          """
        var dedupStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, dedup, -1, &dedupStmt, nil) == SQLITE_OK {
            if sqlite3_step(dedupStmt) == SQLITE_DONE {
                let removed = sqlite3_changes(db)
                if removed > 0 {
                    logWarning("[Backfill] Removed \(removed) duplicate cloud-synced transactions")
                }
            }
            sqlite3_finalize(dedupStmt)
        }
    }

    // MARK: - User-Filtered Queries

    func getTransactions(forUser uid: String) throws -> [Transaction] {
        guard isInitialized else { return [] }

        let query = """
          SELECT id, title, category, type, amount, date, budget_month_date,
                 is_recurring, has_installments, parent_transaction_id,
                 installment_number, total_installments, original_amount,
                 credit_card_id, statement_id, is_credit_card_statement
          FROM Transactions WHERE user_id = ? AND (is_deleted IS NULL OR is_deleted = 0);
          """

        return try executeTransactionQueryPublicText(query, textBindings: [uid])
    }

    func getBudgets(forUser uid: String) throws -> [BudgetModel] {
        guard isInitialized else { return [] }

        let query = "SELECT month_date, amount FROM Budgets WHERE user_id = ? AND (is_deleted IS NULL OR is_deleted = 0);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, uid, -1, SQLITE_TRANSIENT)

        var results: [BudgetModel] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let monthDate = Int(sqlite3_column_int64(statement, 0))
            let amount = Int(sqlite3_column_int64(statement, 1))
            results.append(BudgetModel(monthDate: monthDate, amount: amount))
        }
        return results
    }

    func deleteAllTransactions(forUser uid: String) {
        guard isInitialized else { return }
        executeSyncUpdate("DELETE FROM Transactions WHERE user_id = ?;", textBindings: [uid])
    }

    func deleteAllBudgets(forUser uid: String) {
        guard isInitialized else { return }
        executeSyncUpdate("DELETE FROM Budgets WHERE user_id = ?;", textBindings: [uid])
    }

    // MARK: - CloudKit Sync Helpers

    func executeTransactionQueryPublic(_ query: String, bindValues: [Int] = []) throws -> [Transaction] {
        return try executeTransactionQuery(query, bindValues: bindValues)
    }

    func executeTransactionQueryPublicText(_ query: String, textBindings: [String] = []) throws -> [Transaction] {
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }

        defer { sqlite3_finalize(statement) }

        for (index, value) in textBindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
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

    func executeTransactionQueryMixed(
        _ query: String,
        textBindings: [String] = [],
        intBindings: [Int] = []
    ) throws -> [Transaction] {
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DBError.prepareFailed(message: msg)
        }

        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        for value in textBindings {
            sqlite3_bind_text(statement, bindIndex, value, -1, SQLITE_TRANSIENT)
            bindIndex += 1
        }
        for value in intBindings {
            sqlite3_bind_int64(statement, bindIndex, Int64(value))
            bindIndex += 1
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

    func executeSyncUpdate(_ query: String, textBindings: [String] = [], intBindings: [Int] = []) {
        guard isInitialized else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        for value in textBindings {
            sqlite3_bind_text(statement, bindIndex, value, -1, SQLITE_TRANSIENT)
            bindIndex += 1
        }
        for value in intBindings {
            sqlite3_bind_int64(statement, bindIndex, Int64(value))
            bindIndex += 1
        }

        sqlite3_step(statement)
    }

    func executeCloudInsert(
        _ query: String,
        transaction: Transaction,
        category: String,
        type: String,
        ckRecordName: String,
        parentCKRecordName: String? = nil,
        sharedGroupId: String? = nil,
        updatedAt: Date? = nil
    ) {
        guard isInitialized else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, transaction.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, category, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, type, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 4, Int64(transaction.amount))
        sqlite3_bind_int64(statement, 5, Int64(transaction.dateTimestamp))
        sqlite3_bind_int64(statement, 6, Int64(transaction.budgetMonthDate))

        if let v = transaction.isRecurring { sqlite3_bind_int(statement, 7, v ? 1 : 0) }
        else { sqlite3_bind_null(statement, 7) }
        if let v = transaction.hasInstallments { sqlite3_bind_int(statement, 8, v ? 1 : 0) }
        else { sqlite3_bind_null(statement, 8) }
        if let v = transaction.parentTransactionId { sqlite3_bind_int64(statement, 9, Int64(v)) }
        else { sqlite3_bind_null(statement, 9) }
        if let v = transaction.installmentNumber { sqlite3_bind_int64(statement, 10, Int64(v)) }
        else { sqlite3_bind_null(statement, 10) }
        if let v = transaction.totalInstallments { sqlite3_bind_int64(statement, 11, Int64(v)) }
        else { sqlite3_bind_null(statement, 11) }
        if let v = transaction.originalAmount { sqlite3_bind_int64(statement, 12, Int64(v)) }
        else { sqlite3_bind_null(statement, 12) }
        if let v = transaction.creditCardId { sqlite3_bind_int64(statement, 13, Int64(v)) }
        else { sqlite3_bind_null(statement, 13) }
        if let v = transaction.statementId { sqlite3_bind_int64(statement, 14, Int64(v)) }
        else { sqlite3_bind_null(statement, 14) }
        if let v = transaction.isCreditCardStatement { sqlite3_bind_int(statement, 15, v ? 1 : 0) }
        else { sqlite3_bind_null(statement, 15) }

        sqlite3_bind_text(statement, 16, ckRecordName, -1, SQLITE_TRANSIENT)

        // Bind user_id
        if let uid = UIDUserDefaultsManager.shared.currentUserUID {
            sqlite3_bind_text(statement, 17, uid, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 17)
        }

        // Bind ck_modified_at
        sqlite3_bind_int64(statement, 18, Int64(Date().timeIntervalSince1970))

        // Bind ck_parent_record_name
        if let parentName = parentCKRecordName {
            sqlite3_bind_text(statement, 19, parentName, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 19)
        }

        // Bind shared_group_id
        if let groupId = sharedGroupId {
            sqlite3_bind_text(statement, 20, groupId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 20)
        }

        // Bind updated_at
        sqlite3_bind_int64(statement, 21, Int64((updatedAt ?? Date()).timeIntervalSince1970))

        sqlite3_step(statement)
    }

    func executeCloudUpdate(
        _ query: String,
        transaction: Transaction,
        category: String,
        type: String,
        ckRecordName: String,
        sharedGroupId: String? = nil,
        updatedAt: Date? = nil
    ) {
        guard isInitialized else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, transaction.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, category, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, type, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 4, Int64(transaction.amount))
        sqlite3_bind_int64(statement, 5, Int64(transaction.dateTimestamp))
        sqlite3_bind_int64(statement, 6, Int64(transaction.budgetMonthDate))

        if let v = transaction.isRecurring { sqlite3_bind_int(statement, 7, v ? 1 : 0) }
        else { sqlite3_bind_null(statement, 7) }
        if let v = transaction.hasInstallments { sqlite3_bind_int(statement, 8, v ? 1 : 0) }
        else { sqlite3_bind_null(statement, 8) }
        if let v = transaction.parentTransactionId { sqlite3_bind_int64(statement, 9, Int64(v)) }
        else { sqlite3_bind_null(statement, 9) }
        if let v = transaction.installmentNumber { sqlite3_bind_int64(statement, 10, Int64(v)) }
        else { sqlite3_bind_null(statement, 10) }
        if let v = transaction.totalInstallments { sqlite3_bind_int64(statement, 11, Int64(v)) }
        else { sqlite3_bind_null(statement, 11) }
        if let v = transaction.originalAmount { sqlite3_bind_int64(statement, 12, Int64(v)) }
        else { sqlite3_bind_null(statement, 12) }
        if let v = transaction.creditCardId { sqlite3_bind_int64(statement, 13, Int64(v)) }
        else { sqlite3_bind_null(statement, 13) }
        if let v = transaction.statementId { sqlite3_bind_int64(statement, 14, Int64(v)) }
        else { sqlite3_bind_null(statement, 14) }
        if let v = transaction.isCreditCardStatement { sqlite3_bind_int(statement, 15, v ? 1 : 0) }
        else { sqlite3_bind_null(statement, 15) }

        // ck_modified_at (position 16 in the UPDATE query)
        sqlite3_bind_int64(statement, 16, Int64(Date().timeIntervalSince1970))
        // shared_group_id (position 17)
        if let groupId = sharedGroupId {
            sqlite3_bind_text(statement, 17, groupId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 17)
        }
        // updated_at (position 18)
        sqlite3_bind_int64(statement, 18, Int64((updatedAt ?? Date()).timeIntervalSince1970))
        // ck_record_id (position 19 in the WHERE clause)
        sqlite3_bind_text(statement, 19, ckRecordName, -1, SQLITE_TRANSIENT)

        sqlite3_step(statement)
    }

    func fetchSingleInt(_ query: String, intBindings: [Int]) -> Int? {
        guard isInitialized else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        for (i, value) in intBindings.enumerated() {
            sqlite3_bind_int64(statement, Int32(i + 1), Int64(value))
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func fetchSingleInt(_ query: String, textBinding: String? = nil, intBinding: Int? = nil) -> Int? {
        guard isInitialized else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        if let text = textBinding {
            sqlite3_bind_text(statement, 1, text, -1, SQLITE_TRANSIENT)
        } else if let intVal = intBinding {
            sqlite3_bind_int64(statement, 1, Int64(intVal))
        }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(statement, 0) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func fetchIdAndCKRecordName(_ query: String) -> [(ckRecordName: String, localId: Int)]? {
        guard isInitialized else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        var results: [(ckRecordName: String, localId: Int)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let localId = Int(sqlite3_column_int64(statement, 0))
            guard let cString = sqlite3_column_text(statement, 1) else { continue }
            let ckName = String(cString: cString)
            results.append((ckRecordName: ckName, localId: localId))
        }
        return results
    }

    func fetchCKRecordNames(_ query: String, textBinding: String? = nil) -> [(ckRecordName: String, localId: Int)] {
        guard isInitialized else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        if let text = textBinding {
            sqlite3_bind_text(statement, 1, text, -1, SQLITE_TRANSIENT)
        }

        var results: [(ckRecordName: String, localId: Int)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let localId = Int(sqlite3_column_int64(statement, 0))
            guard let cString = sqlite3_column_text(statement, 1) else { continue }
            let ckName = String(cString: cString)
            results.append((ckRecordName: ckName, localId: localId))
        }
        return results
    }

    /// Returns rows as (Int, Int) pairs from a query that selects two integer columns.
    /// Used by lazy generation to collect (parentId, budgetMonthDate) for soft-deleted instances.
    func fetchIntIntPairs(_ query: String) -> [(Int, Int)] {
        guard isInitialized else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var results: [(Int, Int)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let a = Int(sqlite3_column_int64(statement, 0))
            let b = Int(sqlite3_column_int64(statement, 1))
            results.append((a, b))
        }
        return results
    }

    func fetchSingleString(_ query: String, textBinding: String? = nil, intBinding: Int? = nil) -> String? {
        guard isInitialized else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        if let text = textBinding {
            sqlite3_bind_text(statement, 1, text, -1, SQLITE_TRANSIENT)
        } else if let intVal = intBinding {
            sqlite3_bind_int64(statement, 1, Int64(intVal))
        }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(statement, 0) == SQLITE_NULL { return nil }
        guard let cString = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: cString)
    }

    // MARK: - BudgetAllocation CRUD Helpers

    func insertBudgetAllocation(_ model: BudgetAllocationModel) -> Int {
        guard isInitialized else { return 0 }
        let query = """
            INSERT INTO BudgetAllocations
                (month_date, category_key, allocated_amount, is_recurring, parent_allocation_id, user_id, shared_group_id, sync_status, ck_modified_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(model.monthDate))
        sqlite3_bind_text(statement, 2, model.categoryKey, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 3, Int64(model.allocatedAmount))
        sqlite3_bind_int(statement, 4, model.isRecurring ? 1 : 0)
        if let parentId = model.parentAllocationId {
            sqlite3_bind_int64(statement, 5, Int64(parentId))
        } else {
            sqlite3_bind_null(statement, 5)
        }
        if let uid = UIDUserDefaultsManager.shared.currentUserUID {
            sqlite3_bind_text(statement, 6, uid, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 6)
        }
        if let groupId = model.sharedGroupId {
            sqlite3_bind_text(statement, 7, groupId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 7)
        }
        let now = Int64(Date().timeIntervalSince1970)
        sqlite3_bind_int64(statement, 8, now)
        sqlite3_bind_int64(statement, 9, now)

        guard sqlite3_step(statement) == SQLITE_DONE else { return 0 }
        return Int(sqlite3_last_insert_rowid(db))
    }

    func fetchAllBudgetAllocations(userId: String?) -> [BudgetAllocationModel] {
        guard isInitialized else { return [] }
        let query: String
        if userId != nil {
            query = """
                SELECT id, month_date, category_key, allocated_amount, is_recurring,
                       parent_allocation_id, shared_group_id
                FROM BudgetAllocations WHERE user_id = ? AND (is_deleted IS NULL OR is_deleted = 0);
                """
        } else {
            query = """
                SELECT id, month_date, category_key, allocated_amount, is_recurring,
                       parent_allocation_id, shared_group_id
                FROM BudgetAllocations WHERE (is_deleted IS NULL OR is_deleted = 0);
                """
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        if let uid = userId {
            sqlite3_bind_text(statement, 1, uid, -1, SQLITE_TRANSIENT)
        }

        var results: [BudgetAllocationModel] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int64(statement, 0))
            let monthDate = Int(sqlite3_column_int64(statement, 1))
            let categoryKey = String(cString: sqlite3_column_text(statement, 2))
            let allocatedAmount = Int(sqlite3_column_int64(statement, 3))
            let isRecurring = sqlite3_column_int(statement, 4) == 1
            let parentAllocationId: Int? = sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int64(statement, 5))
            let sharedGroupId: String? = sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil : String(cString: sqlite3_column_text(statement, 6))

            results.append(BudgetAllocationModel(
                id: id,
                monthDate: monthDate,
                categoryKey: categoryKey,
                allocatedAmount: allocatedAmount,
                isRecurring: isRecurring,
                parentAllocationId: parentAllocationId,
                sharedGroupId: sharedGroupId
            ))
        }
        return results
    }

    func fetchBudgetAllocation(byId id: Int) -> BudgetAllocationModel? {
        guard isInitialized else { return nil }
        let query = """
            SELECT id, month_date, category_key, allocated_amount, is_recurring,
                   parent_allocation_id, shared_group_id
            FROM BudgetAllocations WHERE id = ?;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(id))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        let monthDate = Int(sqlite3_column_int64(statement, 1))
        let categoryKey = String(cString: sqlite3_column_text(statement, 2))
        let allocatedAmount = Int(sqlite3_column_int64(statement, 3))
        let isRecurring = sqlite3_column_int(statement, 4) == 1
        let parentAllocationId: Int? = sqlite3_column_type(statement, 5) == SQLITE_NULL
            ? nil : Int(sqlite3_column_int64(statement, 5))
        let sharedGroupId: String? = sqlite3_column_type(statement, 6) == SQLITE_NULL
            ? nil : String(cString: sqlite3_column_text(statement, 6))

        return BudgetAllocationModel(
            id: id,
            monthDate: monthDate,
            categoryKey: categoryKey,
            allocatedAmount: allocatedAmount,
            isRecurring: isRecurring,
            parentAllocationId: parentAllocationId,
            sharedGroupId: sharedGroupId
        )
    }

    func fetchPendingSyncBudgets(userId: String?) -> [BudgetModel] {
        guard isInitialized else { return [] }
        let query: String
        if userId != nil {
            query = "SELECT month_date, amount, shared_group_id FROM Budgets WHERE sync_status = 'pending' AND user_id = ? AND (is_deleted IS NULL OR is_deleted = 0);"
        } else {
            query = "SELECT month_date, amount, shared_group_id FROM Budgets WHERE sync_status = 'pending' AND (is_deleted IS NULL OR is_deleted = 0);"
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        if let uid = userId {
            sqlite3_bind_text(statement, 1, uid, -1, SQLITE_TRANSIENT)
        }
        var results: [BudgetModel] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let monthDate = Int(sqlite3_column_int64(statement, 0))
            let amount = Int(sqlite3_column_int64(statement, 1))
            let sharedGroupId: String? = {
                if sqlite3_column_type(statement, 2) == SQLITE_NULL { return nil }
                guard let ptr = sqlite3_column_text(statement, 2) else { return nil }
                return String(cString: ptr)
            }()
            results.append(BudgetModel(monthDate: monthDate, amount: amount, sharedGroupId: sharedGroupId))
        }
        return results
    }

    func fetchPendingSyncAllocations(userId: String?) -> [BudgetAllocationModel] {
        guard isInitialized else { return [] }
        let query: String
        if userId != nil {
            query = """
                SELECT id, month_date, category_key, allocated_amount, is_recurring,
                       parent_allocation_id, shared_group_id
                FROM BudgetAllocations WHERE sync_status = 'pending' AND user_id = ? AND (is_deleted IS NULL OR is_deleted = 0);
                """
        } else {
            query = """
                SELECT id, month_date, category_key, allocated_amount, is_recurring,
                       parent_allocation_id, shared_group_id
                FROM BudgetAllocations WHERE sync_status = 'pending' AND (is_deleted IS NULL OR is_deleted = 0);
                """
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        if let uid = userId {
            sqlite3_bind_text(statement, 1, uid, -1, SQLITE_TRANSIENT)
        }

        var results: [BudgetAllocationModel] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int64(statement, 0))
            let monthDate = Int(sqlite3_column_int64(statement, 1))
            let categoryKey = String(cString: sqlite3_column_text(statement, 2))
            let allocatedAmount = Int(sqlite3_column_int64(statement, 3))
            let isRecurring = sqlite3_column_int(statement, 4) == 1
            let parentAllocationId: Int? = sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int64(statement, 5))
            let sharedGroupId: String? = sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil : String(cString: sqlite3_column_text(statement, 6))

            results.append(BudgetAllocationModel(
                id: id,
                monthDate: monthDate,
                categoryKey: categoryKey,
                allocatedAmount: allocatedAmount,
                isRecurring: isRecurring,
                parentAllocationId: parentAllocationId,
                sharedGroupId: sharedGroupId
            ))
        }
        return results
    }

    // MARK: - BudgetGroup CRUD Helpers

    func executeGroupWrite(_ query: String, orderedBindings: [Any?]) {
        guard isInitialized else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        for (index, binding) in orderedBindings.enumerated() {
            let col = Int32(index + 1)
            switch binding {
            case let text as String:
                sqlite3_bind_text(statement, col, text, -1, SQLITE_TRANSIENT)
            case let intVal as Int:
                sqlite3_bind_int64(statement, col, Int64(intVal))
            case nil:
                sqlite3_bind_null(statement, col)
            default:
                sqlite3_bind_null(statement, col)
            }
        }

        sqlite3_step(statement)
    }

    func fetchBudgetGroupRows(_ query: String, textBindings: [String] = []) -> [BudgetGroup] {
        guard isInitialized else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        for (index, value) in textBindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }

        var results: [BudgetGroup] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let name = String(cString: sqlite3_column_text(statement, 1))
            let ownerId = String(cString: sqlite3_column_text(statement, 2))
            let ownerName = String(cString: sqlite3_column_text(statement, 3))
            let ownerEmail = String(cString: sqlite3_column_text(statement, 4))
            let currency = String(cString: sqlite3_column_text(statement, 5))

            let ckRecordId: String? = sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil : String(cString: sqlite3_column_text(statement, 6))
            let ckShareUrl: String? = sqlite3_column_type(statement, 7) == SQLITE_NULL
                ? nil : String(cString: sqlite3_column_text(statement, 7))
            let ckZoneOwner: String? = sqlite3_column_type(statement, 8) == SQLITE_NULL
                ? nil : String(cString: sqlite3_column_text(statement, 8))

            let createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 9)))
            let updatedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 10)))
            let isDeleted = sqlite3_column_int(statement, 11) == 1

            var group = BudgetGroup(
                id: id, name: name, ownerId: ownerId,
                ownerName: ownerName, ownerEmail: ownerEmail,
                currency: currency,
                createdAt: createdAt, updatedAt: updatedAt,
                isDeleted: isDeleted
            )
            group.ckRecordId = ckRecordId
            group.ckShareUrl = ckShareUrl
            group.ckZoneOwner = ckZoneOwner
            results.append(group)
        }
        return results
    }

    func fetchGroupMemberRows(_ query: String, textBindings: [String] = []) -> [GroupMember] {
        guard isInitialized else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        for (index, value) in textBindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }

        var results: [GroupMember] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let groupId = String(cString: sqlite3_column_text(statement, 1))
            let userId = String(cString: sqlite3_column_text(statement, 2))
            let name = String(cString: sqlite3_column_text(statement, 3))
            let email = String(cString: sqlite3_column_text(statement, 4))
            let roleStr = String(cString: sqlite3_column_text(statement, 5))
            let permissionsJson = String(cString: sqlite3_column_text(statement, 6))

            let lastActive: Date? = sqlite3_column_type(statement, 7) == SQLITE_NULL
                ? nil : Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 7)))
            let joinedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 8)))
            let isRemoved = sqlite3_column_int(statement, 9) == 1

            let member = GroupMember(
                id: id, groupId: groupId, userId: userId,
                name: name, email: email,
                role: GroupRole(rawValue: roleStr) ?? .member,
                permissions: GroupPermissions.fromJSON(permissionsJson),
                lastActive: lastActive,
                joinedAt: joinedAt,
                isRemoved: isRemoved
            )
            results.append(member)
        }
        return results
    }

    func fetchGroupInvitationRows(_ query: String, textBindings: [String] = []) -> [GroupInvitation] {
        guard isInitialized else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        for (index, value) in textBindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }

        var results: [GroupInvitation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let groupId = String(cString: sqlite3_column_text(statement, 1))
            let groupName = String(cString: sqlite3_column_text(statement, 2))
            let inviterName = String(cString: sqlite3_column_text(statement, 3))
            let inviterEmail = String(cString: sqlite3_column_text(statement, 4))
            let inviteeEmail = String(cString: sqlite3_column_text(statement, 5))
            let status = String(cString: sqlite3_column_text(statement, 6))

            let ckShareUrl: String? = sqlite3_column_type(statement, 7) == SQLITE_NULL
                ? nil : String(cString: sqlite3_column_text(statement, 7))
            let createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 8)))
            let respondedAt: Date? = sqlite3_column_type(statement, 9) == SQLITE_NULL
                ? nil : Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 9)))

            var invitation = GroupInvitation(
                id: id, groupId: groupId, groupName: groupName,
                inviterName: inviterName, inviterEmail: inviterEmail,
                inviteeEmail: inviteeEmail, status: status,
                createdAt: createdAt
            )
            invitation.ckShareUrl = ckShareUrl
            invitation.respondedAt = respondedAt
            results.append(invitation)
        }
        return results
    }

    // MARK: - Phase 6: One-time sync fix migration

    private func performSyncFixMigration() {
        let key = "syncFix_v3_done"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard isInitialized else { return }

        // 1. Deduplicate all tables by ck_record_id (already done in migrateSyncColumnsV3 for fresh installs,
        //    but needed here for existing installs that already ran v3 without dedup)
        let tables = ["Transactions", "Budgets", "CreditCards", "CreditCardStatements", "BudgetAllocations"]
        let idColumn: [String: String] = [
            "Transactions": "id", "Budgets": "rowid", "CreditCards": "id",
            "CreditCardStatements": "id", "BudgetAllocations": "id"
        ]
        for table in tables {
            let col = idColumn[table] ?? "rowid"
            let dedup = """
                DELETE FROM \(table) WHERE \(col) NOT IN (
                    SELECT MIN(\(col)) FROM \(table) GROUP BY ck_record_id
                ) AND ck_record_id IS NOT NULL;
                """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, dedup, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_DONE {
                    let removed = sqlite3_changes(db)
                    if removed > 0 {
                        logWarning("[SyncFix] Removed \(removed) duplicate rows from \(table)")
                    }
                }
                sqlite3_finalize(stmt)
            }
        }

        // 2. Backfill ck_modified_at on existing rows that have a ck_record_id but no timestamp
        let now = Int(Date().timeIntervalSince1970)
        for table in tables {
            executeSyncUpdate(
                "UPDATE \(table) SET ck_modified_at = ? WHERE ck_modified_at IS NULL AND ck_record_id IS NOT NULL;",
                intBindings: [now]
            )
        }

        // 3. Reset sync tokens to force full re-fetch
        SyncStateManager.shared.resetAllTokens()

        UserDefaults.standard.set(true, forKey: key)
        logInfo("[SyncFix] One-time sync fix migration completed")
    }

    /// One-time migration to fix orphaned parent IDs and deduplicate recurring instances.
    /// This handles data that was synced before the parent ID fixup was in place.
    private func performParentIdFixMigration() {
        let key = "syncFix_parentId_v3_done"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard isInitialized else { return }

        fixOrphanedParentTransactionIds()
        deduplicateRecurringTransactions()

        // Reset sync tokens so the next sync pushes the corrected data
        SyncStateManager.shared.resetAllTokens()

        UserDefaults.standard.set(true, forKey: key)
        logInfo("[SyncFix] Parent ID fix migration v3 completed")
    }

    /// One-time migration: backfill ck_modified_at for pending records that were created
    /// before Fix 1 (ck_modified_at at INSERT time). Without this, ConflictResolver would
    /// see localModDate = distantPast and always let the remote win, destroying local data.
    private func performPendingModifiedAtMigration() {
        let key = "syncFix_pendingModifiedAt_v1_done"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard isInitialized else { return }

        let now = Int(Date().timeIntervalSince1970)
        let tables = ["Transactions", "Budgets", "CreditCards", "CreditCardStatements", "BudgetAllocations"]
        for table in tables {
            executeSyncUpdate(
                "UPDATE \(table) SET ck_modified_at = ? WHERE ck_modified_at IS NULL AND ck_record_id IS NULL AND sync_status = 'pending';",
                intBindings: [now]
            )
        }

        UserDefaults.standard.set(true, forKey: key)
        logInfo("[SyncFix] Backfilled ck_modified_at for pending records without CK record ID")
    }

    /// One-time migration: backfill updated_at for existing records that predate the
    /// updated_at column. Copies from ck_modified_at where available, otherwise uses current time.
    private func performUpdatedAtBackfill() {
        let key = "syncFix_updatedAt_backfill_v1_done"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard isInitialized else { return }

        let tables = ["Transactions", "Budgets", "BudgetAllocations"]
        for table in tables {
            // Copy ck_modified_at into updated_at for rows that have it
            executeSyncUpdate(
                "UPDATE \(table) SET updated_at = ck_modified_at WHERE updated_at IS NULL AND ck_modified_at IS NOT NULL;",
                textBindings: []
            )
            // Set current time for any remaining NULL rows
            let now = Int(Date().timeIntervalSince1970)
            executeSyncUpdate(
                "UPDATE \(table) SET updated_at = \(now) WHERE updated_at IS NULL;",
                textBindings: []
            )
        }

        UserDefaults.standard.set(true, forKey: key)
        logInfo("[SyncFix] Backfilled updated_at for existing records")
    }

    /// Fixes orphaned parent_transaction_id references after sync.
    /// When records come from CloudKit, parent_transaction_id uses the source device's local ID.
    /// This method finds instances where parent_transaction_id doesn't point to a valid local record
    /// and remaps them to the correct local parent (matched by title + is_recurring).
    func fixOrphanedParentTransactionIds() {
        guard isInitialized else { return }
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return }

        // Case 1: parent_transaction_id points to a non-existent row (scoped to current user)
        let findOrphansQuery = """
            SELECT DISTINCT t.parent_transaction_id, t.title
            FROM Transactions t
            WHERE t.parent_transaction_id IS NOT NULL
              AND t.user_id = ?
              AND (t.is_deleted IS NULL OR t.is_deleted = 0)
              AND t.parent_transaction_id NOT IN (
                SELECT id FROM Transactions WHERE (is_deleted IS NULL OR is_deleted = 0) AND user_id = ?
              );
            """

        // Case 2: parent_transaction_id points to an existing row but with a different title
        // (cross-device ID collision: same auto-increment ID, different transaction)
        let findMismatchQuery = """
            SELECT DISTINCT t.parent_transaction_id, t.title
            FROM Transactions t
            JOIN Transactions p ON p.id = t.parent_transaction_id
            WHERE t.parent_transaction_id IS NOT NULL
              AND t.user_id = ?
              AND (t.is_deleted IS NULL OR t.is_deleted = 0)
              AND (p.is_deleted IS NULL OR p.is_deleted = 0)
              AND p.title != t.title;
            """

        var orphanGroups: [(oldParentId: Int, title: String)] = []
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, findOrphansQuery, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (uid as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (uid as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let oldParentId = Int(sqlite3_column_int64(stmt, 0))
                let title = String(cString: sqlite3_column_text(stmt, 1))
                orphanGroups.append((oldParentId, title))
            }
        }
        sqlite3_finalize(stmt)

        if sqlite3_prepare_v2(db, findMismatchQuery, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (uid as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let oldParentId = Int(sqlite3_column_int64(stmt, 0))
                let title = String(cString: sqlite3_column_text(stmt, 1))
                // Avoid duplicate entries
                if !orphanGroups.contains(where: { $0.oldParentId == oldParentId && $0.title == title }) {
                    orphanGroups.append((oldParentId, title))
                }
            }
        }
        sqlite3_finalize(stmt)

        guard !orphanGroups.isEmpty else { return }

        for group in orphanGroups {
            // Find the correct local parent by title + is_recurring (scoped to current user)
            let findParentQuery = """
                SELECT id FROM Transactions
                WHERE title = ? AND is_recurring = 1
                  AND user_id = ?
                  AND (is_deleted IS NULL OR is_deleted = 0)
                  AND (parent_transaction_id IS NULL OR parent_transaction_id = id)
                LIMIT 1;
                """
            var findStmt: OpaquePointer?
            var newParentId: Int?
            if sqlite3_prepare_v2(db, findParentQuery, -1, &findStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(findStmt, 1, (group.title as NSString).utf8String, -1, nil)
                sqlite3_bind_text(findStmt, 2, (uid as NSString).utf8String, -1, nil)
                if sqlite3_step(findStmt) == SQLITE_ROW {
                    newParentId = Int(sqlite3_column_int64(findStmt, 0))
                }
            }
            sqlite3_finalize(findStmt)

            guard let correctParentId = newParentId else { continue }
            // Don't remap if it's already pointing to the correct parent
            guard correctParentId != group.oldParentId else { continue }

            // Remap orphaned instances to the correct parent (mixed int+text bindings, scoped to user)
            let updateQuery = "UPDATE Transactions SET parent_transaction_id = ? WHERE parent_transaction_id = ? AND title = ? AND user_id = ? AND (is_deleted IS NULL OR is_deleted = 0);"
            var updateStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, updateQuery, -1, &updateStmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(updateStmt, 1, Int64(correctParentId))
                sqlite3_bind_int64(updateStmt, 2, Int64(group.oldParentId))
                sqlite3_bind_text(updateStmt, 3, (group.title as NSString).utf8String, -1, nil)
                sqlite3_bind_text(updateStmt, 4, (uid as NSString).utf8String, -1, nil)
                sqlite3_step(updateStmt)
            }
            sqlite3_finalize(updateStmt)
            logInfo("[ParentFix] Remapped parent \(group.oldParentId) → \(correctParentId) for recurring instances of '\(group.title)'")
        }
    }

    /// Deduplicates ALL transactions: keeps the row with the lowest id
    /// per (title, amount, budget_month_date), soft-deletes the rest as pendingDelete.
    /// This handles duplicate recurring parents, instances, and normal transactions.
    func deduplicateRecurringTransactions() {
        guard isInitialized else { return }
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return }

        // Log what will be deduplicated for debugging
        logDuplicatesBeforeDedup(uid: uid)

        // Dedup recurring/installment instances by (user_id, title, budget_month_date).
        // Scoped to current user to prevent cross-user deletion in group context.
        // Only targets SYNCED transactions (ck_record_id IS NOT NULL) to preserve
        // newly created local transactions that haven't been pushed yet.
        let instanceQuery = """
            UPDATE Transactions SET is_deleted = 1, sync_status = 'pendingDelete'
            WHERE (is_deleted IS NULL OR is_deleted = 0)
              AND parent_transaction_id IS NOT NULL
              AND user_id = ?
              AND ck_record_id IS NOT NULL
              AND id NOT IN (
                SELECT MIN(id) FROM Transactions
                WHERE (is_deleted IS NULL OR is_deleted = 0)
                  AND parent_transaction_id IS NOT NULL
                  AND user_id = ?
                GROUP BY user_id, title, budget_month_date
              );
            """

        // Dedup recurring parents by (user_id, title, budget_month_date) — prevents duplicate parents.
        // Only targets SYNCED parents to preserve newly created local ones.
        let parentQuery = """
            UPDATE Transactions SET is_deleted = 1, sync_status = 'pendingDelete'
            WHERE (is_deleted IS NULL OR is_deleted = 0)
              AND is_recurring = 1
              AND user_id = ?
              AND ck_record_id IS NOT NULL
              AND (parent_transaction_id IS NULL OR parent_transaction_id = id)
              AND id NOT IN (
                SELECT MIN(id) FROM Transactions
                WHERE (is_deleted IS NULL OR is_deleted = 0)
                  AND is_recurring = 1
                  AND user_id = ?
                  AND (parent_transaction_id IS NULL OR parent_transaction_id = id)
                GROUP BY user_id, title, budget_month_date
              );
            """

        for (label, query) in [("instances", instanceQuery), ("parents", parentQuery)] {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (uid as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (uid as NSString).utf8String, -1, nil)
                if sqlite3_step(stmt) == SQLITE_DONE {
                    let removed = sqlite3_changes(db)
                    if removed > 0 {
                        logWarning("[Dedup] Soft-deleted \(removed) duplicate \(label) for user \(uid)")
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
    }

    private func logDuplicatesBeforeDedup(uid: String) {
        let query = """
            SELECT title, budget_month_date, COUNT(*) as cnt
            FROM Transactions
            WHERE (is_deleted IS NULL OR is_deleted = 0)
              AND parent_transaction_id IS NOT NULL
              AND user_id = ?
            GROUP BY title, budget_month_date
            HAVING cnt > 1;
            """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (uid as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let title = String(cString: sqlite3_column_text(stmt, 0))
                let monthDate = sqlite3_column_int64(stmt, 1)
                let count = sqlite3_column_int(stmt, 2)
                logWarning("[Dedup] Found \(count) instances of '\(title)' for month \(monthDate) — will keep 1, delete \(count - 1)")
            }
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - CloudKit System Fields (recordChangeTag for ifServerRecordUnchanged)

    private let syncableTables: Set<String> = [
        "Transactions", "Budgets", "CreditCards", "CreditCardStatements", "BudgetAllocations"
    ]

    /// Returns the encoded system-fields blob for the record identified by its CK record name.
    /// Returns nil if no blob has been stored yet (new record) or if the table is unknown.
    func fetchSystemFields(ckRecordName: String, table: String) -> Data? {
        guard isInitialized, syncableTables.contains(table) else { return nil }
        let query = "SELECT ck_system_fields FROM \(table) WHERE ck_record_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, ckRecordName, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW,
              sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
        let length = Int(sqlite3_column_bytes(statement, 0))
        guard let bytes = sqlite3_column_blob(statement, 0), length > 0 else { return nil }
        return Data(bytes: bytes, count: length)
    }

    /// Persists the encoded system-fields blob for the record identified by its CK record name.
    /// Returns all non-null ck_record_id values for the given table.
    func fetchAllCKRecordNames(table: String) -> [String] {
        guard isInitialized, syncableTables.contains(table) else { return [] }
        let query = "SELECT ck_record_id FROM \(table) WHERE ck_record_id IS NOT NULL AND (is_deleted IS NULL OR is_deleted = 0);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(statement, 0))
            names.append(name)
        }
        return names
    }

    /// Re-queues soft-deleted Transactions whose sync_status was corrupted (set to something
    /// other than 'pendingDelete' while is_deleted=1). Returns the number of rows repaired.
    /// Safe to call on every push: it only touches rows that are already is_deleted=1 AND
    /// have a ck_record_id (i.e. were synced and need a CloudKit delete to be sent).
    @discardableResult
    func repairCorruptedPendingDeletes() -> Int {
        guard isInitialized else { return 0 }
        let query = """
            UPDATE Transactions SET sync_status = 'pendingDelete'
            WHERE is_deleted = 1
              AND ck_record_id IS NOT NULL
              AND sync_status != 'pendingDelete';
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        sqlite3_step(statement)
        return Int(sqlite3_changes(db))
    }

    /// Deletes rows from the given table whose ck_record_id matches any of the provided names.
    func deleteOrphanedRecords(table: String, ckRecordNames: [String]) {
        guard isInitialized, syncableTables.contains(table), !ckRecordNames.isEmpty else { return }
        for name in ckRecordNames {
            executeSyncUpdate(
                "DELETE FROM \(table) WHERE ck_record_id = ?;",
                textBindings: [name]
            )
        }
    }

    func clearSystemFields(ckRecordName: String, table: String) {
        guard isInitialized, syncableTables.contains(table) else { return }
        let query = "UPDATE \(table) SET ck_system_fields = NULL, ck_record_id = NULL WHERE ck_record_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, ckRecordName, -1, SQLITE_TRANSIENT)
        sqlite3_step(statement)
    }

    func saveSystemFields(_ data: Data, ckRecordName: String, table: String) {
        guard isInitialized, syncableTables.contains(table) else { return }
        let query = "UPDATE \(table) SET ck_system_fields = ? WHERE ck_record_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        data.withUnsafeBytes { ptr in
            sqlite3_bind_blob(statement, 1, ptr.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
        }
        sqlite3_bind_text(statement, 2, ckRecordName, -1, SQLITE_TRANSIENT)
        sqlite3_step(statement)
    }

    private func addColumnIfNotExists(table: String, column: String, definition: String) throws {
        let checkQuery = "PRAGMA table_info(\(table));"
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

        if !existingColumns.contains(column) {
            let alterQuery = "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);"
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
