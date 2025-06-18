//
//  DashboardViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation
import UIKit
import UserNotifications

final class DashboardViewModel {
  let budgetRepo: BudgetRepository
  let transactionRepo: TransactionRepository
  private let recurringManager: RecurringTransactionManager
  private let calendar = Calendar.current

  private let monthRange: ClosedRange<Int>
  private let notificationCenter = UNUserNotificationCenter.current()

  var onCleanupChoiceNeeded: ((RecurringCleanupOption) -> Void)?

  init(
    budgetRepo: BudgetRepository = BudgetRepository(),
    transactionRepo: TransactionRepository = TransactionRepository(),
    monthRange: ClosedRange<Int> = -12...24
  ) {  // 3 years
    self.budgetRepo = budgetRepo
    self.transactionRepo = transactionRepo
    self.monthRange = monthRange
    self.recurringManager = RecurringTransactionManager(transactionRepo: transactionRepo)
  }

  func loadMonthlyCards() -> [MonthBudgetCardType] {
    let today = Date()

    let budgetsByAnchor: [Int: Int] = budgetRepo.fetchBudgets()
      .reduce(into: [:]) { acc, entry in
        acc[entry.monthDate] = entry.amount
      }

    let allTxs = transactionRepo.fetchTransactions()

    let expensesByAnchor =
      allTxs
      .filter { $0.type == .expense }
      .reduce(into: [:]) { acc, tx in
        acc[tx.budgetMonthDate, default: 0] += tx.amount
      }

    let incomesByAnchor =
      allTxs
      .filter { $0.type == .income }
      .reduce(into: [:]) { acc, tx in
        acc[tx.budgetMonthDate, default: 0] += tx.amount
      }

    let anchors = monthRange.map { offset in
      let dt = calendar.date(byAdding: .month, value: offset, to: today)!
      return dt.monthAnchor
    }.sorted()

    var runningBalance = [Int: Int]()
    var previousAvailable = 0

    let cards: [MonthBudgetCardType] = anchors.compactMap { anchor in
      let date = Date(timeIntervalSince1970: TimeInterval(anchor))
      let month = DateFormatter.monthFormatter.string(from: date)

      let expense = expensesByAnchor[anchor] ?? 0
      let income = incomesByAnchor[anchor] ?? 0
      let budgetLimit = budgetsByAnchor[anchor]

      let net = income - expense
      let available = previousAvailable + net

      previousAvailable = available
      runningBalance[anchor] = available

      return MonthBudgetCardType(
        date: date,
        month: "month.\(month.lowercased())".localized,
        usedValue: expense,
        budgetLimit: budgetLimit,
        availableValue: available
      )
    }

    return cards.sorted { $0.date < $1.date }
  }

  func cleanupRecurringTransactionsWithUserPrompt(
    onCleanupNeeded: @escaping (@escaping (RecurringCleanupOption) -> Void) -> Void
  ) {
    onCleanupNeeded { [weak self] cleanupOption in
      self?.updateRecurringTransactionsWithCleanupChoice(cleanupOption: cleanupOption)
    }
  }

  private func updateRecurringTransactions() {
    recurringManager.generateRecurringTransactionsForRange(0...24)
    recurringManager.cleanupRecurringInstancesOutsideRange(
      monthRange, referenceDate: Date(), cleanupOption: .futureOnly)
  }

  func updateRecurringTransactionsWithCleanupChoice(
    cleanupOption: RecurringCleanupOption = .futureOnly
  ) {
    recurringManager.generateRecurringTransactionsForRange(monthRange)
    recurringManager.cleanupRecurringInstancesOutsideRange(
      monthRange, referenceDate: Date(), cleanupOption: cleanupOption)
  }

  func deleteTransaction(id: Int) -> Result<Void, Error> {
    do {
      let allTransactions = transactionRepo.fetchTransactions()
      guard let transaction = allTransactions.first(where: { $0.id == id }) else {
        return .failure(TransactionError.transactionNotFound)
      }

      // Handle simple transactions directly
      if transaction.isRecurring != true && transaction.parentTransactionId == nil
        && transaction.hasInstallments != true {
        try transactionRepo.delete(id: id)

        let notifID = "transaction_\(id)"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
        return .success(())
      }

      // For complex transactions, we need user input - return a special error
      // The UI should catch this and show the user prompt
      return .failure(TransactionError.notARecurringTransaction)

    } catch {
      return .failure(error)
    }
  }

  func deleteComplexTransaction(
    transactionId: Int,
    cleanupOption: RecurringCleanupOption,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    do {
      let allTransactions = transactionRepo.fetchTransactions()
      guard let transaction = allTransactions.first(where: { $0.id == transactionId }) else {
        completion(.failure(TransactionError.transactionNotFound))
        return
      }

      // Handle recurring transaction instances
      if let parentTransactionId = transaction.parentTransactionId {
        let parentTransaction = allTransactions.first(where: { $0.id == parentTransactionId })

        if parentTransaction?.isRecurring == true {
          // This is a recurring transaction instance
          recurringManager.cleanupRecurringInstancesFromDate(
            parentTransactionId: parentTransactionId,
            selectedTransactionDate: transaction.date,
            cleanupOption: cleanupOption
          )
        } else {
          // This is an installment transaction
          recurringManager.cleanupInstallmentTransactionsFromDate(
            parentTransactionId: parentTransactionId,
            selectedTransactionDate: transaction.date,
            cleanupOption: cleanupOption
          )
        }

        completion(.success(()))
        return
      }

      // Handle parent recurring transaction
      if transaction.isRecurring == true {
        recurringManager.cleanupRecurringInstancesFromDate(
          parentTransactionId: transactionId,
          selectedTransactionDate: transaction.date,
          cleanupOption: cleanupOption
        )
        completion(.success(()))
        return
      }

      // Handle parent installment transaction
      if transaction.hasInstallments == true {
        recurringManager.cleanupInstallmentTransactionsFromDate(
          parentTransactionId: transactionId,
          selectedTransactionDate: transaction.date,
          cleanupOption: cleanupOption
        )
        completion(.success(()))
        return
      }

      completion(.failure(TransactionError.transactionNotFound))

    } catch {
      completion(.failure(error))
    }
  }

  @available(*, deprecated, message: "Use deleteComplexTransaction instead")
  func deleteRecurringTransaction(
    transactionId: Int,
    selectedTransactionDate: Date,
    cleanupOption: RecurringCleanupOption,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    deleteComplexTransaction(
      transactionId: transactionId, cleanupOption: cleanupOption, completion: completion)
  }

  func scheduleAllTransactionNotifications() {
    let allTxs = transactionRepo.fetchTransactions()
    let now = Date()

    allTxs
      .filter { $0.date >= now }
      .forEach { scheduleNotification(for: $0) }
  }

  private func scheduleNotification(for tx: Transaction) {
    let id = "transaction_\(String(describing: tx.id))"

    var comps = calendar.dateComponents([.year, .month, .day], from: tx.date)
    comps.hour = 8
    comps.minute = 0

    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

    let titleKey =
      tx.type == .income
      ? "notification.transaction.title.income" : "notification.transaction.title.expense"
    let bodyKey =
      tx.type == .income
      ? "notification.transaction.body.income" : "notification.transaction.body.expense"

    let amountString = tx.amount.currencyString
    let title = titleKey.localized
    let body = bodyKey.localized(amountString, tx.title)

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    notificationCenter.add(request) { error in
      if let error = error {
        print("Error scheduling notification: \(error)")
      }
    }
  }

  func isRecurringTransaction(id: Int) -> Bool {
    guard let transaction = transactionRepo.fetchTransactions().first(where: { $0.id == id }) else {
      return false
    }

    // Return true if it's a parent recurring transaction OR a recurring instance
    return transaction.isRecurring == true || transaction.parentTransactionId != nil
  }

  func getTransactionType(id: Int) -> TransactionComplexityType {
    guard let transaction = transactionRepo.fetchTransactions().first(where: { $0.id == id }) else {
      return .simple
    }

    // Check if this is a recurring transaction instance
    if let parentId = transaction.parentTransactionId {
      let parentTransaction = transactionRepo.fetchTransactions().first(where: { $0.id == parentId }
      )
      if parentTransaction?.isRecurring == true {
        return .recurringInstance
      } else {
        return .installmentInstance
      }
    }

    // Check if this is a parent recurring transaction
    if transaction.isRecurring == true {
      return .recurringParent
    }

    // Check if this is a parent installment transaction
    if transaction.hasInstallments == true {
      return .installmentParent
    }

    return .simple
  }

  private func printPendingNotifications() {
    notificationCenter.getPendingNotificationRequests { requests in
      for request in requests {
        let title = request.content.title
        let body = request.content.body
        print("🔔 Pending — title: \(title), body: \(body)")
      }
    }
  }
}
