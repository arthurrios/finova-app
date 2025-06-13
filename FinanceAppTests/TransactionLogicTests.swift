//
//  TransactionLogicTests.swift
//  FinanceAppTests
//
//  Created by Arthur Rios on 13/06/25.
//

import XCTest

@testable import FinanceApp

class TransactionLogicTests: XCTestCase {
    var transactionRepo: TransactionRepository!
    var recurringManager: RecurringTransactionManager!
    var viewModel: AddTransactionModalViewModel!
    var dashboardViewModel: DashboardViewModel!
    
    override func setUp() {
        super.setUp()
        
        transactionRepo = TransactionRepository()
        recurringManager = RecurringTransactionManager(transactionRepo: transactionRepo)
        viewModel = AddTransactionModalViewModel(transactionRepo: transactionRepo)
        dashboardViewModel = DashboardViewModel(transactionRepo: transactionRepo)
        
        clearTestData()
    }
    
    override func tearDown() {
        clearTestData()
        super.tearDown()
    }
    
    private func clearTestData() {
        let allTransactions = transactionRepo.fetchTransactions()
        for transaction in allTransactions {
            if let id = transaction.id {
                try? transactionRepo.delete(id: id)
            }
        }
    }
    
    // MARK: - Recurring Transaction Creation Tests
    
    func testCreateRecurringTransaction() {
        let result = viewModel.addTransaction(
            title: "Monthly Rent",
            amount: 150000,  // $1500.00
            dateString: "15/03/2025",
            categoryKey: "utilities",
            typeRaw: "expense",
            isRecurring: true
        )
        
        switch result {
        case .success():
            // Test passed - transaction was created successfully
            break
        case .failure(let error):
            XCTFail("Should successfully create recurring transaction, but failed with error: \(error)")
        }
        
        let transactions = transactionRepo.fetchTransactions()
        let parentTransaction = transactions.first { $0.isRecurring == true }
        
        XCTAssertNotNil(parentTransaction, "Parent recurring transaction should exist")
        XCTAssertEqual(parentTransaction?.title, "Monthly Rent")
        XCTAssertEqual(parentTransaction?.amount, 150000)
        XCTAssertEqual(parentTransaction?.category.key, "utilities")
    }
    
    func testRecurringTransactionSelfReference() {
        let result = viewModel.addTransaction(
            title: "Monthly Salary",
            amount: 500000,  // $5000.00
            dateString: "01/03/2025",
            categoryKey: "salary",
            typeRaw: "income",
            isRecurring: true
        )
        
        switch result {
        case .success():
            break
        case .failure(let error):
            XCTFail("Should successfully create recurring transaction, but failed with error: \(error)")
        }
        
        let transactions = transactionRepo.fetchTransactions()
        let parentTransaction = transactions.first { $0.isRecurring == true }
        
        XCTAssertNotNil(parentTransaction, "Parent transaction should exist")
        XCTAssertNotNil(
            parentTransaction?.parentTransactionId, "Parent should have parentTransactionId")
        XCTAssertEqual(
            parentTransaction?.parentTransactionId, parentTransaction?.id,
            "Parent should reference itself")
    }
    
    func testInvalidDateFormat() {
        let result = viewModel.addTransaction(
            title: "Test",
            amount: 10000,
            dateString: "invalid-date",
            categoryKey: "miscellaneous",
            typeRaw: "expense"
        )
        
        switch result {
        case .success():
            XCTFail("Should fail with invalid date format")
        case .failure(let error):
            if let transactionError = error as? TransactionError {
                XCTAssertEqual(transactionError, TransactionError.invalidDateFormat)
            } else {
                XCTFail("Expected TransactionError.invalidDateFormat, got \(error)")
            }
        }
    }
    
    func testInvalidCategory() {
        let result = viewModel.addTransaction(
            title: "Test",
            amount: 10000,
            dateString: "01/01/2025",
            categoryKey: "nonexistent-category",
            typeRaw: "expense"
        )
        
        switch result {
        case .success():
            XCTFail("Should fail with invalid category")
        case .failure(let error):
            if let transactionError = error as? TransactionError {
                XCTAssertEqual(transactionError, TransactionError.invalidCategory)
            } else {
                XCTFail("Expected TransactionError.invalidCategory, got \(error)")
            }
        }
    }
    
    func testInvalidTransactionType() {
        let result = viewModel.addTransaction(
            title: "Test",
            amount: 10000,
            dateString: "01/01/2025",
            categoryKey: "miscellaneous",
            typeRaw: "invalid-type"
        )
        
        switch result {
        case .success():
            XCTFail("Should fail with invalid type")
        case .failure(let error):
            if let transactionError = error as? TransactionError {
                XCTAssertEqual(transactionError, TransactionError.invalidType)
            } else {
                XCTFail("Expected TransactionError.invalidType, got \(error)")
            }
        }
    }
}
