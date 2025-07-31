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
  private var calendar: Calendar = {
    var cal = Calendar.current
    cal.timeZone = TimeZone.current  // Ensure we use local timezone
    return cal
  }()
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
        // Calcular a data da parcela usando a função de geração de datas válidas
        let targetDate = calendar.date(byAdding: .month, value: installmentNumber - 1, to: startDate) ?? startDate
        let targetYear = calendar.component(.year, from: targetDate)
        let targetMonth = calendar.component(.month, from: targetDate)
        
        print("🔄 Creating installment \(installmentNumber)/\(totalInstallments) for month \(targetMonth)/\(targetYear)")
        
        let installmentDate = generateValidDateForMonth(
          originalDate: startDate,
          targetMonth: targetMonth,
          targetYear: targetYear
        )
        
        print("📅 Installment \(installmentNumber) date: \(installmentDate)")
        
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
        print("✅ Created installment \(installmentNumber): \(data.title) for \(installmentDate)")

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
        return
      }

      DispatchQueue.main.async { [weak self] in
        self?.scheduleNotification(for: transactionId, model: model)
      }
    }
  }

  private func scheduleNotification(for transactionId: Int, model: TransactionModel) {
    let date = Date(timeIntervalSince1970: TimeInterval(model.data.dateTimestamp))

    // Create notification time (8 AM) in local timezone
    var notificationDate = calendar.startOfDay(for: date)
    notificationDate =
      calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    // Only schedule if notification time is in the future
    guard notificationDate > Date() else {
      return
    }

    let id = "transaction_\(transactionId)"
    let timeInterval = notificationDate.timeIntervalSinceNow
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

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

        // Only schedule for future transactions and don't clear existing ones
        let futureTxs = allTxs.filter { tx in
          // Create notification time (8 AM) in local timezone
          var notificationDate = self?.calendar.startOfDay(for: tx.date) ?? tx.date
          notificationDate =
            self?.calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate
          return notificationDate > now
        }

        futureTxs.forEach { tx in
          self?.scheduleNotificationForTransaction(tx)
        }
      }
    }
  }

  private func scheduleNotificationForTransaction(_ tx: Transaction) {
    guard let transactionId = tx.id else {
      return
    }

    let id = "transaction_\(transactionId)"

    // Create notification time (8 AM) in local timezone
    var notificationDate = calendar.startOfDay(for: tx.date)
    notificationDate =
      calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    // Only schedule if notification time is in the future
    guard notificationDate > Date() else {
      return
    }

    let timeInterval = notificationDate.timeIntervalSinceNow
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

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
        print("🔔 ❌ Error scheduling notification for \(tx.title): \(error)")
      }
    }
  }

  // MARK: - Helper Methods
  
  /// Gera uma data válida para o mês especificado, lidando com dias que não existem
  /// - Parameters:
  ///   - originalDate: Data original da transação
  ///   - targetMonth: Mês para o qual gerar a data
  ///   - targetYear: Ano para o qual gerar a data
  /// - Returns: Data válida para o mês especificado
  private func generateValidDateForMonth(
    originalDate: Date,
    targetMonth: Int,
    targetYear: Int
  ) -> Date {
    let originalDay = calendar.component(.day, from: originalDate)
    
    print("🔧 generateValidDateForMonth (installments): originalDay=\(originalDay), targetMonth=\(targetMonth), targetYear=\(targetYear)")
    
    // Calcular o último dia do mês específico primeiro
    let lastDayOfMonth: Int
    
    switch targetMonth {
    case 2: // Fevereiro
      let isLeapYear = (targetYear % 4 == 0 && targetYear % 100 != 0) || (targetYear % 400 == 0)
      lastDayOfMonth = isLeapYear ? 29 : 28
    case 4, 6, 9, 11: // Abril, Junho, Setembro, Novembro
      lastDayOfMonth = 30
    default: // Janeiro, Março, Maio, Julho, Agosto, Outubro, Dezembro
      lastDayOfMonth = 31
    }
    
    print("📅 Last day of month \(targetMonth)/\(targetYear): \(lastDayOfMonth)")
    
    // Determinar o dia a usar
    let dayToUse = min(originalDay, lastDayOfMonth)
    print("📅 Using day: \(dayToUse) (original: \(originalDay), last day: \(lastDayOfMonth))")
    
    // Criar a data com o dia determinado
    var dateComponents = DateComponents()
    dateComponents.year = targetYear
    dateComponents.month = targetMonth
    dateComponents.day = dayToUse
    dateComponents.hour = 12 // Usar meio-dia para evitar problemas de fuso horário
    dateComponents.minute = 0
    dateComponents.second = 0
    
    // Criar a data
    guard let validDate = calendar.date(from: dateComponents) else {
      print("❌ Failed to create date for \(dayToUse)/\(targetMonth)/\(targetYear), using fallback")
      // Fallback: usar o primeiro dia do mês
      dateComponents.day = 1
      let fallbackDate = calendar.date(from: dateComponents) ?? Date()
      print("⚠️ Using fallback date (1st day) for installment month \(targetMonth)/\(targetYear)")
      return fallbackDate
    }
    
    if dayToUse != originalDay {
      print("📅 Adjusted installment date for month \(targetMonth)/\(targetYear): original day \(originalDay) → adjusted day \(dayToUse)")
    } else {
      print("✅ Original day \(originalDay) works for installment month \(targetMonth)/\(targetYear)")
    }
    
    return validDate
  }
}
