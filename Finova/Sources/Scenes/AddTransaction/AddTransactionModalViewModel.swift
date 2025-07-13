//
//  AddTransactionModalViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/05/25.
//

import Foundation
import UserNotifications

final class AddTransactionModalViewModel {
  private let transactionRepo: TransactionRepository
  private let recurringManager: RecurringTransactionManager
  private let carouselRange: ClosedRange<Int> = -12...24
  private let calendar = Calendar.current
  private let notificationCenter = UNUserNotificationCenter.current()

  init(transactionRepo: TransactionRepository = TransactionRepository()) {
    self.transactionRepo = transactionRepo
    self.recurringManager = RecurringTransactionManager(transactionRepo: transactionRepo)
  }

  func addTransaction(
    title: String,
    amount: Int,
    dateString: String,
    categoryKey: String,
    typeRaw: String,
    isRecurring: Bool? = nil
  ) -> Result<Void, Error> {

    guard let date = DateFormatter.fullDateFormatter.date(from: dateString) else {
      return .failure(TransactionError.invalidDateFormat)
    }

    let timestamp = Int(date.timeIntervalSince1970)

    guard
      let category = TransactionCategory.allCases
        .first(where: { $0.key == categoryKey })
    else {
      return .failure(TransactionError.invalidCategory)
    }

    guard
      let type = TransactionType.allCases
        .first(where: { String(describing: $0) == typeRaw })
    else {
      return .failure(TransactionError.invalidType)
    }

    let anchor = date.monthAnchor

    if let isRecurring = isRecurring, isRecurring {

      let model = TransactionModel(
        title: title,
        category: category.key,
        amount: amount,
        type: type.key,
        dateTimestamp: timestamp,
        budgetMonthDate: anchor,
        isRecurring: true
      )

      do {
        let insertedId = try transactionRepo.insertTransactionAndGetId(model)
        try transactionRepo.updateParentTransactionId(
          transactionId: insertedId, parentId: insertedId)

        // Use a more inclusive range to ensure the original transaction date is included
        let today = Date()

        // Calculate how many months back we need to go to include the transaction date
        let monthsBack = max(
          12, calendar.dateComponents([.month], from: date, to: today).month ?? 0)
        let inclusiveRange = -monthsBack...24

        recurringManager.generateRecurringTransactionsForRange(
          inclusiveRange,
          referenceDate: today,
          transactionStartDate: date
        )

        // Schedule notifications for all newly created recurring instances
        scheduleNotificationsForRecurringTransactions()

        return .success(())
      } catch {
        return .failure(error)
      }
    } else {
      let model = TransactionModel(
        title: title,
        category: category.key,
        amount: amount,
        type: type.key,
        dateTimestamp: timestamp,
        budgetMonthDate: anchor,
        isRecurring: false
      )

      do {
        let insertedId = try transactionRepo.insertTransactionAndGetId(model)

        // Schedule notification for the new transaction with its ID
        scheduleNotificationForNewTransaction(insertedId, model)

        return .success(())
      } catch {
        return .failure(error)
      }
    }
  }

  func addTransactionWithInstallments(
    _ data: InstallmentTransactionData
  ) -> Result<Void, Error> {
    let totalInstallments = data.installments
    guard totalInstallments > 1 else {
      return .failure(TransactionError.invalidInstallmentCount)
    }

    guard let startDate = DateFormatter.fullDateFormatter.date(from: data.date) else {
      return .failure(TransactionError.invalidDateFormat)
    }

    guard
      let category = TransactionCategory.allCases
        .first(where: { $0.key == data.category })
    else {
      return .failure(TransactionError.invalidCategory)
    }

    guard
      let type = TransactionType.allCases
        .first(where: { String(describing: $0) == data.transactionType })
    else {
      return .failure(TransactionError.invalidType)
    }

    let amountPerInstallment = data.totalAmount / totalInstallments
    let remainder = data.totalAmount % totalInstallments

    do {
      // Create a placeholder parent (NOT visible in UI)
      // This is used only for linking installments together
      let parentModel = TransactionModel(
        title: "\(data.title) - Installment Parent",  // Mark it clearly as parent
        category: category.key,
        amount: 0,  // Zero amount so it doesn't affect totals
        type: type.key,
        dateTimestamp: Int(startDate.timeIntervalSince1970),
        budgetMonthDate: startDate.monthAnchor,
        hasInstallments: true,
        originalAmount: data.totalAmount,
        totalInstallments: totalInstallments
      )

      let parentId = try transactionRepo.insertTransactionAndGetId(parentModel)

      for installmentNumber in 1...totalInstallments {
        let installmentDate =
          Calendar.current.date(byAdding: .month, value: installmentNumber - 1, to: startDate)
          ?? startDate
        let installmentAmount =
          installmentNumber == 1 ? amountPerInstallment + remainder : amountPerInstallment

        let installmentModel = TransactionModel(
          title: data.title,
          category: category.key,
          amount: installmentAmount,
          type: type.key,
          dateTimestamp: Int(installmentDate.timeIntervalSince1970),
          budgetMonthDate: installmentDate.monthAnchor,
          parentTransactionId: parentId,
          originalAmount: data.totalAmount,
          installmentNumber: installmentNumber,
          totalInstallments: totalInstallments
        )

        let installmentId = try transactionRepo.insertTransactionAndGetId(installmentModel)

        // Schedule notification for each installment if it's in the future
        scheduleNotificationForNewTransaction(installmentId, installmentModel)
      }
      return .success(())
    } catch {
      return .failure(error)
    }
  }

  // MARK: - Notification Scheduling

  private func scheduleNotificationForNewTransaction(
    _ transactionId: Int, _ model: TransactionModel
  ) {
    // Check if we have notification permission first
    notificationCenter.getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized else {
        print("🔔 ❌ Notification permission not granted")
        return
      }

      DispatchQueue.main.async { [weak self] in
        self?.scheduleNotification(for: transactionId, model: model)
      }
    }
  }

  private func scheduleNotification(for transactionId: Int, model: TransactionModel) {
    let date = Date(timeIntervalSince1970: TimeInterval(model.data.dateTimestamp))

    // Create notification time (8 AM on transaction date)
    var comps = calendar.dateComponents([.year, .month, .day], from: date)
    comps.hour = 8
    comps.minute = 0

    guard let notificationDate = calendar.date(from: comps) else {
      print("🔔 ❌ Could not create notification date for: \(model.data.title)")
      return
    }

    // Only schedule if notification time is in the future
    guard notificationDate > Date() else {
      print("🔔 ❌ Notification time (\(notificationDate)) is in the past for: \(model.data.title)")
      return
    }

    let id = "transaction_\(transactionId)"
    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

    let titleKey =
      model.data.type == "income"
      ? "notification.transaction.title.income"
      : "notification.transaction.title.expense"
    let bodyKey =
      model.data.type == "income"
      ? "notification.transaction.body.income"
      : "notification.transaction.body.expense"

    let amountString = model.data.amount.currencyString
    let title = titleKey.localized
    let body = bodyKey.localized(amountString, model.data.title)

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"

    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    notificationCenter.add(request) { error in
      if let error = error {
        print("🔔 ❌ Error scheduling notification for \(model.data.title): \(error)")
      } else {
        print(
          "🔔 ✅ Successfully scheduled notification for \(model.data.title) at \(notificationDate)")
      }
    }
  }

  private func scheduleNotificationsForRecurringTransactions() {
    // This will schedule notifications for newly created recurring transactions
    notificationCenter.getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized else {
        return
      }

      DispatchQueue.main.async { [weak self] in
        // Get all transactions and schedule notifications for future ones only
        let allTxs = self?.transactionRepo.fetchTransactions() ?? []
        let now = Date()

        print(
          "🔔 Scheduling notifications for recurring transactions"
        )

        // Only schedule for future transactions and don't clear existing ones
        let futureTxs = allTxs.filter { tx in
          // Get the transaction date and create notification time (8 AM)
          let calendar = Calendar.current
          var comps = calendar.dateComponents([.year, .month, .day], from: tx.date)
          comps.hour = 8
          comps.minute = 0

          guard let notificationDate = calendar.date(from: comps) else { return false }
          return notificationDate > now
        }

        print("🔔 Found \(futureTxs.count) future transactions for notification scheduling")

        futureTxs.forEach { tx in
          self?.scheduleNotificationForTransaction(tx)
        }
      }
    }
  }

  private func scheduleNotificationForTransaction(_ tx: Transaction) {
    guard let transactionId = tx.id else {
      print("🔔 ❌ No transaction ID for: \(tx.title)")
      return
    }

    let id = "transaction_\(transactionId)"

    // Get the transaction date and create notification time (8 AM)
    var comps = calendar.dateComponents([.year, .month, .day], from: tx.date)
    comps.hour = 8
    comps.minute = 0

    guard let notificationDate = calendar.date(from: comps) else {
      print("🔔 ❌ Could not create notification date for: \(tx.title)")
      return
    }

    // Only schedule if notification time is in the future
    guard notificationDate > Date() else {
      print("🔔 ❌ Notification time (\(notificationDate)) is in the past for: \(tx.title)")
      return
    }

    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

    let titleKey =
      tx.type == .income
      ? "notification.transaction.title.income"
      : "notification.transaction.title.expense"
    let bodyKey =
      tx.type == .income
      ? "notification.transaction.body.income"
      : "notification.transaction.body.expense"

    let amountString = tx.amount.currencyString
    let title = titleKey.localized
    let body = bodyKey.localized(amountString, tx.title)

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"

    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    notificationCenter.add(request) { error in
      if let error = error {
        print("�� ❌ Error scheduling notification for \(tx.title): \(error)")
      } else {
        print("🔔 ✅ Successfully scheduled notification for \(tx.title) at \(notificationDate)")
      }
    }
  }
}
