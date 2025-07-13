//
//  TransactionLogicTests.swift
//  FinanceAppTests
//
//  Created by Arthur Rios on 13/06/25.
//

import Foundation
import XCTest

@testable import Finova

class TransactionLogicTests: XCTestCase {
    var transactionRepo: TransactionRepository!
    var recurringManager: RecurringTransactionManager!
    var viewModel: AddTransactionModalViewModel!
    var dashboardViewModel: DashboardViewModel!
    
    override func setUp() {
        super.setUp()
        
        // Authenticate a test user for secure data access
        let testUID = "test_user_transaction_logic_\(UUID().uuidString)"
        SecureLocalDataManager.shared.authenticateUser(firebaseUID: testUID)
        print("🧪 Authenticated test user: \(testUID)")
        
        transactionRepo = TransactionRepository()
        recurringManager = RecurringTransactionManager(transactionRepo: transactionRepo)
        viewModel = AddTransactionModalViewModel(transactionRepo: transactionRepo)
        dashboardViewModel = DashboardViewModel(transactionRepo: transactionRepo)
        
        // Check initial state before cleanup
        let initialTransactions = transactionRepo.fetchAllTransactions()
        let initialParentTransactions = transactionRepo.fetchParentInstallmentTransactions()
        print(
            "🧪 setUp - Before cleanup: \(initialTransactions.count) total, \(initialParentTransactions.count) parent transactions"
        )
        
        clearTestData()
        
        // Verify cleanup worked
        let remainingTransactions = transactionRepo.fetchAllTransactions()
        let remainingParentTransactions = transactionRepo.fetchParentInstallmentTransactions()
        print(
            "🧪 setUp - After cleanup: \(remainingTransactions.count) total, \(remainingParentTransactions.count) parent transactions"
        )
        
        if remainingTransactions.count > 0 {
            print("⚠️ Warning: \(remainingTransactions.count) transactions still exist after cleanup")
            for transaction in remainingTransactions {
                print(
                    "   - Transaction: \(transaction.title) (ID: \(transaction.id ?? -1), hasInstallments: \(transaction.hasInstallments ?? false))"
                )
            }
        }
    }
    
    override func tearDown() {
        clearTestData()
        
        // Clear secure data and sign out test user
        SecureLocalDataManager.shared.signOut()
        print("🧪 Signed out test user and cleared secure data")
        
        super.tearDown()
    }
    
    // MARK: - Test Helper Methods
    
    private func authenticateUniqueTestUser(testName: String = #function) {
        let testUID = "test_\(testName)_\(UUID().uuidString.prefix(8))"
        SecureLocalDataManager.shared.authenticateUser(firebaseUID: testUID)
        print("🧪 \(testName): Authenticated unique test user: \(testUID)")
    }
    
    private func clearTestData() {
        // Clear SQLite data using the dedicated test cleanup method
        transactionRepo.clearAllTransactionsForTesting()
        
        // Clear secure user data (encrypted storage)
        SecureLocalDataManager.shared.clearUserData()
        print("🧪 Cleared both SQLite and secure user data")
        
        // Verify SQLite cleanup worked
        let remainingTransactions = transactionRepo.fetchAllTransactions()
        if !remainingTransactions.isEmpty {
            print("⚠️ Still have \(remainingTransactions.count) transactions after cleanup")
            // Try one more time with deleteTransactionAndRelated for complex transactions
            for transaction in remainingTransactions {
                if let id = transaction.id {
                    try? transactionRepo.deleteTransactionAndRelated(id: id)
                }
            }
        }
        
        // Verify secure data cleanup
        let secureTransactions = SecureLocalDataManager.shared.loadTransactions()
        if !secureTransactions.isEmpty {
            print("⚠️ Still have \(secureTransactions.count) transactions in secure storage")
        }
    }
    
    // MARK: - Recurring Transaction Creation Tests
    
    func testCreateRecurringTransaction() {
        authenticateUniqueTestUser()
        
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
        
        let allTransactions = transactionRepo.fetchAllTransactions()
        let parentTransaction = allTransactions.first { $0.isRecurring == true }
        
        XCTAssertNotNil(parentTransaction, "Parent recurring transaction should exist")
        XCTAssertEqual(parentTransaction?.title, "Monthly Rent")
        XCTAssertEqual(parentTransaction?.amount, 150000)
        XCTAssertEqual(parentTransaction?.category.key, "utilities")
    }
    
    func testRecurringTransactionSelfReference() {
        authenticateUniqueTestUser()
        
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
        
        let allTransactions = transactionRepo.fetchAllTransactions()
        let parentTransaction = allTransactions.first { $0.isRecurring == true }
        
        XCTAssertNotNil(parentTransaction, "Parent transaction should exist")
        XCTAssertNotNil(
            parentTransaction?.parentTransactionId, "Parent should have parentTransactionId")
        XCTAssertEqual(
            parentTransaction?.parentTransactionId, parentTransaction?.id,
            "Parent should reference itself")
    }
    
    func testRecurringInstanceGeneration() {
        authenticateUniqueTestUser()
        
        let result = viewModel.addTransaction(
            title: "Netflix Subscription",
            amount: 1999,  // $19.99
            dateString: "05/01/2025",
            categoryKey: "subscriptions",
            typeRaw: "expense",
            isRecurring: true
        )
        
        switch result {
        case .success():
            break
        case .failure(let error):
            XCTFail("Should successfully create recurring transaction, but failed with error: \(error)")
        }
        
        let allTransactions = transactionRepo.fetchAllTransactions()
        let parentTransaction = allTransactions.first { $0.isRecurring == true }
        let instances = allTransactions.filter { $0.parentTransactionId == parentTransaction?.id }
        
        XCTAssertNotNil(parentTransaction, "Parent transaction should exist")
        XCTAssertTrue(instances.count > 0, "Should generate recurring instances")
        
        for instance in instances {
            XCTAssertEqual(instance.title, "Netflix Subscription")
            XCTAssertEqual(instance.amount, 1999)
            XCTAssertEqual(instance.category.key, "subscriptions")
            XCTAssertEqual(instance.parentTransactionId, parentTransaction?.id)
        }
    }
    
    // MARK: - Recurring Transaction Deletion Tests
    
    func testRecurringDeleteAll() {
        authenticateUniqueTestUser()
        
        let result = viewModel.addTransaction(
            title: "Monthly Gym",
            amount: 5000,  // $50.00
            dateString: "10/01/2025",
            categoryKey: "fitness",
            typeRaw: "expense",
            isRecurring: true
        )
        
        switch result {
        case .success():
            break
        case .failure(let error):
            XCTFail("Should create transaction, but failed: \(error)")
        }
        
        let allTransactions = transactionRepo.fetchAllTransactions()
        guard let parentTransaction = allTransactions.first(where: { $0.isRecurring == true }) else {
            XCTFail("Parent recurring transaction should exist")
            return
        }
        let initialInstanceCount = allTransactions.filter {
            $0.parentTransactionId == parentTransaction.id
        }.count
        
        XCTAssertTrue(initialInstanceCount > 0, "Should have created instances")
        
        let expectation = XCTestExpectation(description: "Delete all recurring")
        dashboardViewModel.deleteComplexTransaction(
            transactionId: parentTransaction.id!,
            cleanupOption: .all,
            completion: { result in
                switch result {
                case .success():
                    expectation.fulfill()
                case .failure(let error):
                    XCTFail("Should successfully delete all, but failed: \(error)")
                }
            }
        )
        
        wait(for: [expectation], timeout: 2.0)
        
        let remainingTransactions = transactionRepo.fetchTransactions()
        let remainingParent = remainingTransactions.first { $0.id == parentTransaction.id }
        let remainingInstances = remainingTransactions.filter {
            $0.parentTransactionId == parentTransaction.id
        }
        
        XCTAssertNil(remainingParent, "Parent transaction should be deleted")
        XCTAssertEqual(remainingInstances.count, 0, "All instances should be deleted")
    }
    
    func testRecurringDeleteFutureOnly() {
        authenticateUniqueTestUser()
        
        let result = viewModel.addTransaction(
            title: "Phone Bill",
            amount: 8000,  // $80.00
            dateString: "15/01/2025",
            categoryKey: "communication",
            typeRaw: "expense",
            isRecurring: true
        )
        
        switch result {
        case .success():
            break
        case .failure(let error):
            XCTFail("Should create transaction, but failed: \(error)")
        }
        
        let allTransactions = transactionRepo.fetchAllTransactions()
        guard let parentTransaction = allTransactions.first(where: { $0.isRecurring == true }) else {
            XCTFail("Parent recurring transaction should exist")
            return
        }
        let instances = allTransactions.filter { $0.parentTransactionId == parentTransaction.id }
        
        let marchDate = DateFormatter.fullDateFormatter.date(from: "15/03/2025")!
        let marchInstance = instances.first {
            Calendar.current.isDate($0.date, equalTo: marchDate, toGranularity: .month)
        }
        
        XCTAssertNotNil(marchInstance, "Should have March instance")
        
        let expectation = XCTestExpectation(description: "Delete future only")
        dashboardViewModel.deleteComplexTransaction(
            transactionId: marchInstance!.id!,
            cleanupOption: .futureOnly,
            completion: { result in
                switch result {
                case .success():
                    expectation.fulfill()
                case .failure(let error):
                    XCTFail("Should successfully delete future, but failed: \(error)")
                }
            }
        )
        
        wait(for: [expectation], timeout: 2.0)
        
        // Check all transactions (including parents) to verify parent still exists
        let allRemainingTransactions = transactionRepo.fetchAllTransactions()
        let remainingParent = allRemainingTransactions.first { $0.id == parentTransaction.id }
        
        // Check UI transactions for remaining instances
        let uiTransactions = transactionRepo.fetchTransactions()
        let remainingInstances = uiTransactions.filter {
            $0.parentTransactionId == parentTransaction.id
        }
        
        XCTAssertNotNil(remainingParent, "Parent should still exist")
        
        for instance in remainingInstances {
            let instanceDate = instance.date
            XCTAssertTrue(instanceDate < marchDate, "Only instances before March should remain")
        }
    }
    
    // MARK: - Installment Transaction Tests
    
    func testInstallmentCreation() {
        authenticateUniqueTestUser()
        
        let installmentData = InstallmentTransactionData(
            title: "MacBook Pro",
            totalAmount: 299999,  // $2999.99
            date: "01/02/2025",
            category: "miscellaneous",
            transactionType: "expense",
            installments: 6
        )
        let result = viewModel.addTransactionWithInstallments(installmentData)
        
        switch result {
        case .success():
            break
        case .failure(let error):
            XCTFail("Should create installment transaction, but failed: \(error)")
        }
        
        let allTransactions = transactionRepo.fetchTransactions()
        let allParentTransactions = transactionRepo.fetchParentInstallmentTransactions()
        
        // Find the specific parent transaction for "MacBook Pro"
        let parentTransaction = allParentTransactions.first {
            $0.title.contains("MacBook Pro")
        }
        
        // Find installments for this specific parent
        let installments = allTransactions.filter {
            $0.parentTransactionId == parentTransaction?.id && $0.installmentNumber != nil
        }
        
        XCTAssertNotNil(parentTransaction, "Parent transaction should exist")
        XCTAssertEqual(installments.count, 6, "Should create 6 installments")
        XCTAssertEqual(parentTransaction?.totalInstallments, 6)
        XCTAssertEqual(parentTransaction?.originalAmount, 299999)
        
        // Verify installment amounts sum to total
        let totalInstallmentAmount = installments.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(totalInstallmentAmount, 299999, "Installment amounts should sum to total")
        
        // Verify parent transaction is NOT in the main transaction list (UI-visible transactions)
        let parentInMainList = allTransactions.first { $0.hasInstallments == true }
        XCTAssertNil(parentInMainList, "Parent transaction should NOT be in main transaction list")
    }
    
    func testParentInstallmentTransactionsNotDisplayedInUI() {
        authenticateUniqueTestUser()
        
        // Verify we start with a clean state
        let initialParentTransactions = transactionRepo.fetchParentInstallmentTransactions()
        let initialDisplayedTransactions = transactionRepo.fetchTransactions()
        print(
            "🧪 Test start: \(initialParentTransactions.count) parent transactions, \(initialDisplayedTransactions.count) displayed transactions"
        )
        
        // Create multiple installment transactions
        let installmentData1 = InstallmentTransactionData(
            title: "iPhone Test UI",
            totalAmount: 120000,
            date: "01/01/2025",
            category: "miscellaneous",
            transactionType: "expense",
            installments: 3
        )
        
        let installmentData2 = InstallmentTransactionData(
            title: "Laptop Test UI",
            totalAmount: 250000,
            date: "15/01/2025",
            category: "miscellaneous",
            transactionType: "expense",
            installments: 5
        )
        
        let result1 = viewModel.addTransactionWithInstallments(installmentData1)
        let result2 = viewModel.addTransactionWithInstallments(installmentData2)
        
        // Verify both transactions were created successfully
        switch result1 {
        case .success(): break
        case .failure(let error): XCTFail("Failed to create first installment: \(error)")
        }
        
        switch result2 {
        case .success(): break
        case .failure(let error): XCTFail("Failed to create second installment: \(error)")
        }
        
        let displayedTransactions = transactionRepo.fetchTransactions()
        let allParentTransactions = transactionRepo.fetchParentInstallmentTransactions()
        
        // Filter to only the parent transactions we just created by checking for our specific titles
        let ourParentTransactions = allParentTransactions.filter {
            $0.title.contains("iPhone Test UI") || $0.title.contains("Laptop Test UI")
        }
        
        print(
            "🧪 After creation: \(allParentTransactions.count) total parent transactions, \(ourParentTransactions.count) our parent transactions"
        )
        
        // Should have created exactly 2 parent transactions for our test
        XCTAssertEqual(ourParentTransactions.count, 2, "Should have 2 parent transactions")
        
        // Should have 8 installment transactions displayed (3 + 5) for our specific transactions
        let ourInstallmentTransactions = displayedTransactions.filter { transaction in
            ourParentTransactions.contains { parent in
                transaction.parentTransactionId == parent.id
            }
        }
        XCTAssertEqual(ourInstallmentTransactions.count, 8, "Should display 8 installment transactions")
        
        // NO parent transactions should be in the displayed list
        let parentInDisplayed = displayedTransactions.filter { $0.hasInstallments == true }
        XCTAssertEqual(parentInDisplayed.count, 0, "No parent transactions should be displayed in UI")
        
        // All displayed transactions should have actual amounts (not zero)
        for transaction in displayedTransactions {
            XCTAssertGreaterThan(
                transaction.amount, 0, "All displayed transactions should have positive amounts")
        }
    }
    
    func testInstallmentAmountDistribution() {
        authenticateUniqueTestUser()
        
        let installmentData = InstallmentTransactionData(
            title: "iPhone",
            totalAmount: 100001,  // $1000.01 (intentionally not evenly divisible)
            date: "01/01/2025",
            category: "miscellaneous",
            transactionType: "expense",
            installments: 3
        )
        let result = viewModel.addTransactionWithInstallments(installmentData)
        
        switch result {
        case .success():
            break
        case .failure(let error):
            XCTFail("Should create installment transaction, but failed: \(error)")
        }
        
        let allTransactions = transactionRepo.fetchTransactions()
        let installments =
        allTransactions
            .filter { $0.parentTransactionId != nil && $0.installmentNumber != nil }
            .sorted { ($0.installmentNumber ?? 0) < ($1.installmentNumber ?? 0) }
        
        XCTAssertEqual(installments.count, 3, "Should have 3 installments")
        
        XCTAssertEqual(installments[0].amount, 33335, "First installment: 33333 + 2 remainder")
        XCTAssertEqual(installments[1].amount, 33333, "Second installment: base amount")
        XCTAssertEqual(installments[2].amount, 33333, "Third installment: base amount")
        
        let total = installments.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(total, 100001, "Total should equal original amount")
        
        XCTAssertEqual(installments[0].installmentNumber, 1)
        XCTAssertEqual(installments[1].installmentNumber, 2)
        XCTAssertEqual(installments[2].installmentNumber, 3)
        
        let calendar = Calendar.current
        let firstDate = installments[0].date
        let secondDate = installments[1].date
        let monthDiff = calendar.dateComponents([.month], from: firstDate, to: secondDate).month
        XCTAssertEqual(monthDiff, 1, "Installments should be 1 month apart")
    }
    
    func testInstallmentValidation() {
        authenticateUniqueTestUser()
        
        let installmentData = InstallmentTransactionData(
            title: "Invalid",
            totalAmount: 10000,
            date: "01/01/2025",
            category: "miscellaneous",
            transactionType: "expense",
            installments: 1
        )
        let result = viewModel.addTransactionWithInstallments(installmentData)
        
        switch result {
        case .success():
            XCTFail("Should fail with invalid installment count")
        case .failure(let error):
            if let transactionError = error as? TransactionError {
                XCTAssertEqual(transactionError, TransactionError.invalidInstallmentCount)
            } else {
                XCTFail("Expected TransactionError.invalidInstallmentCount, got \(error)")
            }
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testDateEdgeCases() {
        authenticateUniqueTestUser()
        
        let result = viewModel.addTransaction(
            title: "Month End Salary",
            amount: 500000,
            dateString: "15/01/2025",
            categoryKey: "salary",
            typeRaw: "income",
            isRecurring: true
        )
        
        switch result {
        case .success():
            break
        case .failure(let error):
            XCTFail("Should create transaction, but failed: \(error)")
        }
        
        let allTransactions = transactionRepo.fetchAllTransactions()
        let parentTransaction = allTransactions.first { $0.isRecurring == true }
        let instances = allTransactions.filter { $0.parentTransactionId != nil }
        
        // Check if parent exists and has self-reference
        XCTAssertNotNil(parentTransaction, "Parent transaction should exist")
        XCTAssertEqual(
            parentTransaction?.parentTransactionId, parentTransaction?.id,
            "Parent should reference itself")
        
        // Find February instance
        let febInstance = instances.first {
            Calendar.current.component(.month, from: $0.date) == 2
        }
        
        XCTAssertNotNil(febInstance, "Should create February instance")
        
        if let febInstance = febInstance {
            let febDay = Calendar.current.component(.day, from: febInstance.date)
            XCTAssertEqual(febDay, 15, "February instance should be on the 15th")
        }
    }
    
    func testIsRecurringTransactionLogic() {
        authenticateUniqueTestUser()
        
        let regularResult = viewModel.addTransaction(
            title: "Regular Transaction",
            amount: 5000,
            dateString: "01/01/2025",
            categoryKey: "miscellaneous",
            typeRaw: "expense"
        )
        
        let recurringResult = viewModel.addTransaction(
            title: "Recurring Transaction",
            amount: 10000,
            dateString: "01/01/2025",
            categoryKey: "utilities",
            typeRaw: "expense",
            isRecurring: true
        )
        
        switch regularResult {
        case .success(): break
        case .failure(let error): XCTFail("Regular transaction failed: \(error)")
        }
        
        switch recurringResult {
        case .success(): break
        case .failure(let error): XCTFail("Recurring transaction failed: \(error)")
        }
        
        let allTransactions = transactionRepo.fetchAllTransactions()
        let uiTransactions = transactionRepo.fetchTransactions()
        
        guard
            let regularTransaction = allTransactions.first(where: { $0.title == "Regular Transaction" })
        else {
            XCTFail("Regular transaction should exist")
            return
        }
        
        // Parent recurring transactions should NOT be visible in UI transactions but should be in fetchAllTransactions
        let parentTransaction = allTransactions.first { $0.isRecurring == true }
        XCTAssertNotNil(
            parentTransaction, "Parent recurring transaction should exist in fetchAllTransactions")
        
        guard let parentTransactionUnwrapped = parentTransaction else {
            XCTFail("Parent transaction should not be nil")
            return
        }
        
        guard
            let instanceTransaction = allTransactions.first(where: {
                $0.parentTransactionId == parentTransactionUnwrapped.id
            })
        else {
            XCTFail("Instance transaction should exist")
            return
        }
        
        XCTAssertFalse(
            dashboardViewModel.isRecurringTransaction(id: regularTransaction.id!),
            "Regular transaction should not be recurring")
        XCTAssertTrue(
            dashboardViewModel.isRecurringTransaction(id: parentTransactionUnwrapped.id!),
            "Parent transaction should be recurring")
        XCTAssertTrue(
            dashboardViewModel.isRecurringTransaction(id: instanceTransaction.id!),
            "Instance transaction should be recurring")
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidDateFormat() {
        authenticateUniqueTestUser()
        
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
        authenticateUniqueTestUser()
        
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
        authenticateUniqueTestUser()
        
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
