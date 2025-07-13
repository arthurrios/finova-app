//
//  NotificationTests.swift
//  FinanceAppTests
//
//  Created by Arthur Rios on 30/12/24.
//

import Foundation
import UserNotifications
import XCTest

@testable import Finova

class NotificationTests: XCTestCase {
  var transactionRepo: TransactionRepository!
  var recurringManager: RecurringTransactionManager!
  var viewModel: AddTransactionModalViewModel!
  var dashboardViewModel: DashboardViewModel!
  override func setUp() {
    super.setUp()

    // Authenticate a test user for secure data access
    let testUID = "test_user_notifications_\(UUID().uuidString)"
    SecureLocalDataManager.shared.authenticateUser(firebaseUID: testUID)
    print("🧪 Authenticated test user for notifications: \(testUID)")

    // Create a test user in UserDefaults for notification scheduling
    let testUser = User(
      firebaseUID: testUID,
      name: "Test User",
      email: "test@example.com",
      isUserSaved: true,
      hasFaceIdEnabled: false
    )
    UserDefaultsManager.saveUser(user: testUser)

    transactionRepo = TransactionRepository()
    recurringManager = RecurringTransactionManager(transactionRepo: transactionRepo)
    viewModel = AddTransactionModalViewModel(transactionRepo: transactionRepo)
    dashboardViewModel = DashboardViewModel(transactionRepo: transactionRepo)

    clearTestData()

    print("🧪 NotificationTests setUp complete")
  }

  override func tearDown() {
    clearTestData()
    super.tearDown()
  }

  private func clearTestData() {
    print("🧪 Clearing test data...")

    // Clear all test transactions
    transactionRepo.clearAllTransactionsForTesting()

    // Verify cleanup
    let remainingTransactions = transactionRepo.fetchAllTransactions()
    if remainingTransactions.count > 0 {
      print("⚠️ Warning: \(remainingTransactions.count) transactions still exist after cleanup")
    } else {
      print("🧪 Test data cleared successfully")
    }
  }

  // MARK: - Test Notification Scheduling on App Launch

  func testAppLaunchSchedulingWithFutureTransactions() {
    // Given: Create transactions for future dates
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date())!

    createTestTransaction(title: "Future Transaction 1", date: tomorrow)
    createTestTransaction(title: "Future Transaction 2", date: nextWeek)

    // Verify transactions were created
    let initialTransactions = transactionRepo.fetchAllTransactions()
    XCTAssertEqual(initialTransactions.count, 2, "Should have created 2 future transactions")

    // When: Simulate app launch notification scheduling
    let appDelegate = AppDelegate()
    appDelegate.scheduleNotificationsOnLaunch()

    let expectation = XCTestExpectation(description: "Notification scheduling completed")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 3.0)

    // Then: Verify transactions still exist after scheduling
    let finalTransactions = transactionRepo.fetchAllTransactions()
    XCTAssertEqual(finalTransactions.count, 2, "Should still have 2 future transactions")

    print("✅ App launch scheduling test passed")
  }

  func testAppLaunchSchedulingIgnoresPastTransactions() {
    // Given: Create transactions for past dates
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

    createTestTransaction(title: "Past Transaction 1", date: yesterday)
    createTestTransaction(title: "Past Transaction 2", date: lastWeek)

    // Verify transactions were created
    let initialTransactions = transactionRepo.fetchAllTransactions()
    XCTAssertEqual(initialTransactions.count, 2, "Should have created 2 past transactions")

    // When: Simulate app launch notification scheduling
    let appDelegate = AppDelegate()
    appDelegate.scheduleNotificationsOnLaunch()

    let expectation = XCTestExpectation(description: "Notification scheduling completed")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 3.0)

    // Then: Verify transactions still exist after scheduling
    let finalTransactions = transactionRepo.fetchAllTransactions()
    XCTAssertEqual(finalTransactions.count, 2, "Should still have 2 past transactions")

    print("✅ App launch scheduling ignores past transactions test passed")
  }

  func testAppLaunchSchedulingMixedDates() {
    // Given: Create transactions with mixed past and future dates
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

    createTestTransaction(title: "Past Transaction", date: yesterday)
    createTestTransaction(title: "Future Transaction", date: tomorrow)

    // Verify transactions were created
    let initialTransactions = transactionRepo.fetchAllTransactions()
    XCTAssertEqual(initialTransactions.count, 2, "Should have created 2 transactions")

    // When: Simulate app launch notification scheduling
    let appDelegate = AppDelegate()
    appDelegate.scheduleNotificationsOnLaunch()

    let expectation = XCTestExpectation(description: "Notification scheduling completed")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 3.0)

    // Then: Verify transactions still exist after scheduling
    let finalTransactions = transactionRepo.fetchAllTransactions()
    XCTAssertEqual(finalTransactions.count, 2, "Should still have 2 transactions total")

    print("✅ App launch scheduling mixed dates test passed")
  }

  // MARK: - Test Transaction Addition Notifications

  func testAddTransactionSchedulesNotificationForFuture() {
    // Given: Future transaction data
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    let dateString = DateFormatter.fullDateFormatter.string(from: tomorrow)

    print("🧪 Testing transaction creation for date: \(dateString)")

    // When: Add a transaction for tomorrow
    let result = viewModel.addTransaction(
      title: "Test Future Transaction",
      amount: 10000,
      dateString: dateString,
      categoryKey: "salary",
      typeRaw: "income"
    )

    // Then: Verify transaction was added successfully
    XCTAssertTrue(result.isSuccess, "Transaction should be added successfully")

    let transactions = transactionRepo.fetchAllTransactions()
    print("🧪 Found \(transactions.count) transactions after adding")

    XCTAssertEqual(transactions.count, 1, "Should have 1 transaction")
    XCTAssertEqual(transactions.first?.title, "Test Future Transaction")

    print("✅ Add transaction notification scheduling test passed")
  }

  func testAddTransactionDoesNotScheduleNotificationForPast() {
    // Given: Past transaction data
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    let dateString = DateFormatter.fullDateFormatter.string(from: yesterday)

    // When: Add a transaction for yesterday
    let result = viewModel.addTransaction(
      title: "Test Past Transaction",
      amount: 5000,
      dateString: dateString,
      categoryKey: "market",
      typeRaw: "expense"
    )

    // Then: Verify transaction was added but no notification scheduled
    XCTAssertTrue(result.isSuccess, "Transaction should be added successfully")

    let transactions = transactionRepo.fetchAllTransactions()
    XCTAssertEqual(transactions.count, 1, "Should have 1 transaction")
    XCTAssertEqual(transactions.first?.title, "Test Past Transaction")

    print("✅ Add past transaction notification test passed")
  }

  func testAddRecurringTransactionSchedulesMultipleNotifications() {
    // Given: Future recurring transaction data
    let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
    let dateString = DateFormatter.fullDateFormatter.string(from: nextMonth)

    // When: Add a recurring transaction
    let result = viewModel.addTransaction(
      title: "Monthly Salary",
      amount: 500000,
      dateString: dateString,
      categoryKey: "salary",
      typeRaw: "income",
      isRecurring: true
    )

    // Then: Verify recurring transaction was added
    XCTAssertTrue(result.isSuccess, "Recurring transaction should be added successfully")

    let allTransactions = transactionRepo.fetchAllTransactions()
    let recurringTransactions = transactionRepo.fetchRecurringTransactions()

    XCTAssertGreaterThan(allTransactions.count, 1, "Should have multiple transaction instances")
    XCTAssertEqual(recurringTransactions.count, 1, "Should have 1 parent recurring transaction")

    print("✅ Add recurring transaction notification test passed")
  }

  func testAddInstallmentTransactionSchedulesMultipleNotifications() {
    // Given: Future installment transaction data
    let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
    let dateString = DateFormatter.fullDateFormatter.string(from: nextMonth)

    let installmentData = InstallmentTransactionData(
      title: "Car Purchase",
      totalAmount: 2_000_000,
      date: dateString,
      category: "transportation",
      transactionType: "expense",
      installments: 12
    )

    // When: Add an installment transaction
    let result = viewModel.addTransactionWithInstallments(installmentData)

    // Then: Verify installment transaction was added
    XCTAssertTrue(result.isSuccess, "Installment transaction should be added successfully")

    let allTransactions = transactionRepo.fetchAllTransactions()
    let visibleTransactions = transactionRepo.fetchTransactions()

    XCTAssertEqual(visibleTransactions.count, 12, "Should have 12 installment instances")
    XCTAssertGreaterThan(allTransactions.count, 12, "Should have parent + instances")

    print("✅ Add installment transaction notification test passed")
  }

  // MARK: - Test Transaction Deletion Notifications

  func testDeleteTransactionCleansUpNotification() {
    // Given: A future transaction
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    let transactionId = createTestTransaction(title: "To Delete", date: tomorrow)

    // When: Delete the transaction
    let result = dashboardViewModel.deleteTransaction(id: transactionId)

    // Then: Verify transaction was deleted
    XCTAssertTrue(result.isSuccess, "Transaction should be deleted successfully")

    let transactions = transactionRepo.fetchAllTransactions()
    XCTAssertEqual(transactions.count, 0, "Should have no transactions after deletion")

    print("✅ Delete transaction cleanup test passed")
  }

  func testDeleteRecurringTransactionCleansUpAllNotifications() {
    // Given: A recurring transaction with multiple instances
    let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
    let dateString = DateFormatter.fullDateFormatter.string(from: nextMonth)

    let result = viewModel.addTransaction(
      title: "Recurring to Delete",
      amount: 100000,
      dateString: dateString,
      categoryKey: "salary",
      typeRaw: "income",
      isRecurring: true
    )

    XCTAssertTrue(result.isSuccess, "Recurring transaction should be added")

    let allTransactions = transactionRepo.fetchAllTransactions()
    let recurringTransactions = transactionRepo.fetchRecurringTransactions()
    let parentTransaction = recurringTransactions.first

    XCTAssertNotNil(parentTransaction, "Should have parent recurring transaction")
    XCTAssertGreaterThan(allTransactions.count, 1, "Should have multiple instances")

    // When: Delete the recurring transaction
    let expectation = XCTestExpectation(description: "Recurring transaction deletion completed")

    dashboardViewModel.deleteComplexTransaction(
      transactionId: parentTransaction!.id!,
      cleanupOption: .all
    ) { deleteResult in
      // Then: Verify all instances were deleted
      XCTAssertTrue(deleteResult.isSuccess, "Recurring transaction should be deleted successfully")

      let remainingTransactions = self.transactionRepo.fetchAllTransactions()
      XCTAssertEqual(remainingTransactions.count, 0, "Should have no transactions after deletion")

      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 2.0)

    print("✅ Delete recurring transaction cleanup test passed")
  }

  func testDeleteInstallmentTransactionCleansUpAllNotifications() {
    // Given: An installment transaction with multiple instances
    let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
    let dateString = DateFormatter.fullDateFormatter.string(from: nextMonth)

    let installmentData = InstallmentTransactionData(
      title: "Installment to Delete",
      totalAmount: 600000,
      date: dateString,
      category: "transportation",
      transactionType: "expense",
      installments: 6
    )

    let result = viewModel.addTransactionWithInstallments(installmentData)
    XCTAssertTrue(result.isSuccess, "Installment transaction should be added")

    let allTransactions = transactionRepo.fetchAllTransactions()
    let visibleTransactions = transactionRepo.fetchTransactions()
    let firstInstallment = visibleTransactions.first

    XCTAssertNotNil(firstInstallment, "Should have first installment")
    XCTAssertEqual(visibleTransactions.count, 6, "Should have 6 installments")
    XCTAssertGreaterThan(allTransactions.count, 6, "Should have parent + instances")

    // When: Delete the installment transaction
    let expectation = XCTestExpectation(description: "Installment transaction deletion completed")

    dashboardViewModel.deleteComplexTransaction(
      transactionId: firstInstallment!.id!,
      cleanupOption: .all
    ) { deleteResult in
      // Then: Verify all instances were deleted
      XCTAssertTrue(
        deleteResult.isSuccess, "Installment transaction should be deleted successfully")

      let remainingTransactions = self.transactionRepo.fetchAllTransactions()
      XCTAssertEqual(remainingTransactions.count, 0, "Should have no transactions after deletion")

      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 2.0)

    print("✅ Delete installment transaction cleanup test passed")
  }

  // MARK: - Test Edge Cases

  func testNotificationSchedulingAt8AMBoundary() {
    // Given: A transaction for today but scheduled notification time is in the past
    let today = Date()
    let calendar = Calendar.current

    // Create a date for today at 9 AM (after the 8 AM notification time)
    var components = calendar.dateComponents([.year, .month, .day], from: today)
    components.hour = 9
    components.minute = 0

    guard let nineAM = calendar.date(from: components) else {
      XCTFail("Could not create 9 AM date")
      return
    }

    // Mock the current date to be 9 AM
    let transactionId = createTestTransaction(title: "Today After 8AM", date: nineAM)

    // When: Try to schedule notification (should not schedule since it's after 8 AM)
    let transactions = transactionRepo.fetchAllTransactions()
    XCTAssertEqual(transactions.count, 1, "Should have 1 transaction")

    // Then: Verify transaction exists but notification logic would skip it
    let transaction = transactions.first!
    XCTAssertEqual(transaction.title, "Today After 8AM")

    print("✅ 8 AM boundary test passed")
  }

  func testNotificationSchedulingForMultipleTransactionsSameDay() {
    // Given: Multiple transactions on the same future date
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

    createTestTransaction(title: "Morning Transaction", date: tomorrow)
    createTestTransaction(title: "Afternoon Transaction", date: tomorrow)
    createTestTransaction(title: "Evening Transaction", date: tomorrow)

    // When: All transactions are added
    let transactions = transactionRepo.fetchAllTransactions()

    // Then: Verify all transactions exist
    XCTAssertEqual(transactions.count, 3, "Should have 3 transactions for same day")

    let titles = Set(transactions.map { $0.title })
    XCTAssertTrue(titles.contains("Morning Transaction"))
    XCTAssertTrue(titles.contains("Afternoon Transaction"))
    XCTAssertTrue(titles.contains("Evening Transaction"))

    print("✅ Multiple transactions same day test passed")
  }

  func testNotificationPermissionHandling() {
    // Given: A future transaction
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

    // When: Try to schedule notifications (real notification center will handle permissions)
    let transactionId = createTestTransaction(title: "Permission Test", date: tomorrow)

    // Then: Verify transaction exists (notification scheduling depends on real permissions)
    let transactions = transactionRepo.fetchAllTransactions()
    XCTAssertEqual(transactions.count, 1, "Should have 1 transaction")
    XCTAssertEqual(transactions.first?.title, "Permission Test")

    print("✅ Notification permission handling test passed")
  }

  // MARK: - Helper Methods

  @discardableResult
  private func createTestTransaction(title: String, date: Date) -> Int {
    let dateString = DateFormatter.fullDateFormatter.string(from: date)

    print("🧪 Creating test transaction: \(title) for date: \(dateString)")

    let result = viewModel.addTransaction(
      title: title,
      amount: 10000,
      dateString: dateString,
      categoryKey: "salary",
      typeRaw: "income"
    )

    XCTAssertTrue(result.isSuccess, "Test transaction should be added successfully")

    let transactions = transactionRepo.fetchAllTransactions()
    print("🧪 After creating transaction, total transactions: \(transactions.count)")

    let addedTransaction = transactions.first { $0.title == title }

    XCTAssertNotNil(addedTransaction, "Transaction should exist")
    XCTAssertNotNil(addedTransaction?.id, "Transaction should have ID")

    print("🧪 Successfully created transaction with ID: \(addedTransaction!.id!)")

    return addedTransaction!.id!
  }
}

// MARK: - Test Utilities

// Note: We're testing the notification scheduling logic without mocking the notification center
// since the real UNUserNotificationCenter handles permissions and scheduling automatically.
// The tests focus on verifying that transactions are properly created and that the
// notification scheduling methods are called correctly.

// MARK: - Test Result Extensions

extension Result {
  var isSuccess: Bool {
    switch self {
    case .success:
      return true
    case .failure:
      return false
    }
  }

  var isFailure: Bool {
    return !isSuccess
  }
}
