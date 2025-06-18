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

  func testRecurringInstanceGeneration() {
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

    let allTransactions = transactionRepo.fetchTransactions()
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

    let allTransactions = transactionRepo.fetchTransactions()
    let parentTransaction = allTransactions.first { $0.isRecurring == true }!
    let initialInstanceCount = allTransactions.filter {
      $0.parentTransactionId == parentTransaction.id
    }.count

    XCTAssertTrue(initialInstanceCount > 0, "Should have created instances")

    let expectation = XCTestExpectation(description: "Delete all recurring")
    dashboardViewModel.deleteRecurringTransaction(
      transactionId: parentTransaction.id!,
      selectedTransactionDate: parentTransaction.date,
      cleanupOption: .all
    ) { result in
      switch result {
      case .success():
        expectation.fulfill()
      case .failure(let error):
        XCTFail("Should successfully delete all, but failed: \(error)")
      }
    }

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

    let allTransactions = transactionRepo.fetchTransactions()
    let parentTransaction = allTransactions.first { $0.isRecurring == true }!
    let instances = allTransactions.filter { $0.parentTransactionId == parentTransaction.id }

    let marchDate = DateFormatter.fullDateFormatter.date(from: "15/03/2025")!
    let marchInstance = instances.first {
      Calendar.current.isDate($0.date, equalTo: marchDate, toGranularity: .month)
    }

    XCTAssertNotNil(marchInstance, "Should have March instance")

    let expectation = XCTestExpectation(description: "Delete future only")
    dashboardViewModel.deleteRecurringTransaction(
      transactionId: marchInstance!.id!,
      selectedTransactionDate: marchDate,
      cleanupOption: .futureOnly
    ) { result in
      switch result {
      case .success():
        expectation.fulfill()
      case .failure(let error):
        XCTFail("Should successfully delete future, but failed: \(error)")
      }
    }

    wait(for: [expectation], timeout: 2.0)

    let remainingTransactions = transactionRepo.fetchTransactions()
    let remainingParent = remainingTransactions.first { $0.id == parentTransaction.id }
    let remainingInstances = remainingTransactions.filter {
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
    let parentTransaction = allTransactions.first { $0.hasInstallments == true }
    let installments = allTransactions.filter {
      $0.parentTransactionId != nil && $0.installmentNumber != nil
    }

    XCTAssertNotNil(parentTransaction, "Parent transaction should exist")
    XCTAssertEqual(installments.count, 6, "Should create 6 installments")
    XCTAssertEqual(parentTransaction?.totalInstallments, 6)
    XCTAssertEqual(parentTransaction?.originalAmount, 299999)

    // Verify installment amounts sum to total
    let totalInstallmentAmount = installments.reduce(0) { $0 + $1.amount }
    XCTAssertEqual(totalInstallmentAmount, 299999, "Installment amounts should sum to total")
  }

  func testInstallmentAmountDistribution() {
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

    let allTransactions = transactionRepo.fetchTransactions()
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

    let allTransactions = transactionRepo.fetchTransactions()
    let regularTransaction = allTransactions.first { $0.title == "Regular Transaction" }!
    let parentTransaction = allTransactions.first { $0.isRecurring == true }!
    let instanceTransaction = allTransactions.first {
      $0.parentTransactionId == parentTransaction.id
    }!

    XCTAssertFalse(
      dashboardViewModel.isRecurringTransaction(id: regularTransaction.id!),
      "Regular transaction should not be recurring")
    XCTAssertTrue(
      dashboardViewModel.isRecurringTransaction(id: parentTransaction.id!),
      "Parent transaction should be recurring")
    XCTAssertTrue(
      dashboardViewModel.isRecurringTransaction(id: instanceTransaction.id!),
      "Instance transaction should be recurring")
  }

  // MARK: - Error Handling Tests

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
