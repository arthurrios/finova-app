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
  private let creditCardService = CreditCardService()
  private let creditCardRepo = CreditCardRepository()

  init(transactionRepo: TransactionRepository = TransactionRepository()) {
    self.transactionRepo = transactionRepo
    self.recurringManager = RecurringTransactionManager(
      transactionRepo: transactionRepo,
      creditCardService: creditCardService,
      creditCardRepo: creditCardRepo
    )
  }

  /// Current context for transaction creation — determines which group (if any) the transaction belongs to
  var activeContext: DataContext = .personal

  // MARK: - Permission Checks

  func canAddTransaction(in group: BudgetGroup?) -> Bool {
    guard let group = group else { return true }
    return BudgetGroupService.shared.currentUserCan(\.canCreateTransactions, in: group)
  }

  func addTransaction(
    title: String,
    amount: Int,
    dateString: String,
    categoryKey: String,
    typeRaw: String,
    isRecurring: Bool? = nil,
    creditCardId: Int? = nil
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

        // Assign to group if in group context
        if let groupId = activeContext.groupId {
          transactionRepo.updateSharedGroupId(transactionId: insertedId, groupId: groupId)
          GroupNotificationService.shared.logActivity(
            action: .transactionCreated, groupId: groupId, detail: title)
        } else if MirrorModeManager.shared.isEnabled,
                  let groupId = MirrorModeManager.shared.linkedGroupId {
          transactionRepo.updateSharedGroupId(transactionId: insertedId, groupId: groupId)
        }

        // Check for similar existing recurring transactions
        if let existingSimilar = recurringManager.findSimilarRecurringTransaction(
          title: title,
          category: category.key,
          amount: amount,
          type: type.key
        ), let existingId = existingSimilar.id {
          // Link to existing recurring transaction instead of creating a new parent
          try recurringManager.linkToExistingRecurringTransaction(
            newTransactionId: insertedId,
            existingParentId: existingId
          )
        } else {
          // No similar transaction found, make this a new parent
          try transactionRepo.updateParentTransactionId(
            transactionId: insertedId, parentId: insertedId)
        }

        // LAZY GENERATION: Only generate instances for a small window (next 2 months)
        // Additional instances will be generated lazily when the user navigates to those months
        let immediateMonthAnchors: Set<Int> = {
          var anchors = Set<Int>()
          for monthOffset in 1...2 {
            if let futureDate = calendar.date(byAdding: .month, value: monthOffset, to: date) {
              anchors.insert(futureDate.monthAnchor)
            }
          }
          return anchors
        }()

        // Generate only the immediate window of instances
        // Completion runs on background queue - heavy work stays there
        recurringManager.generateInstancesLazilyForMonths(immediateMonthAnchors) { [weak self] _ in
          guard let self = self else { return }
          // These operations run on background thread (no UI blocking)
          self.scheduleNotificationsForRecurringTransactions()
          self.monitorNegativeBalance()
          // Only the notification post needs main thread
          DispatchQueue.main.async {
            self.invalidateLedgerCache()
          }
        }

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
        isRecurring: false,
        creditCardId: creditCardId
      )

      do {
        let insertedId = try transactionRepo.insertTransactionAndGetId(model)

        // Assign to group if in group context
        if let groupId = activeContext.groupId {
          transactionRepo.updateSharedGroupId(transactionId: insertedId, groupId: groupId)
          GroupNotificationService.shared.logActivity(
            action: .transactionCreated, groupId: groupId, detail: title)
        } else if MirrorModeManager.shared.isEnabled,
                  let groupId = MirrorModeManager.shared.linkedGroupId {
          transactionRepo.updateSharedGroupId(transactionId: insertedId, groupId: groupId)
        }

        // Handle credit card statement assignment
        if let cardId = creditCardId, let card = creditCardRepo.fetchCard(byId: cardId) {
          guard let uid = AuthenticationManager.shared.currentUser?.uid else {
            return .success(())
          }
          if let statement = creditCardService.getOrCreateStatement(for: card, transactionDate: date, userId: uid) {
            try transactionRepo.updateCreditCardFields(
              transactionId: insertedId,
              creditCardId: cardId,
              statementId: statement.id!,
              isCreditCardStatement: false
            )
            creditCardService.recalculateStatementTotal(statementId: statement.id!)
          }
        }

        // Schedule notification for the new transaction with its ID
        scheduleNotificationForNewTransaction(insertedId, model)

        // Monitor negative balance after adding transaction
        monitorNegativeBalance()

        // Invalidate ledger cache since transactions changed
        invalidateLedgerCache()

        return .success(())
      } catch {
        return .failure(error)
      }
    }
  }

  /// Async version for recurring transaction creation that waits for instance generation
  func addRecurringTransactionAsync(
    title: String,
    amount: Int,
    dateString: String,
    categoryKey: String,
    typeRaw: String,
    creditCardId: Int? = nil,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard let date = DateFormatter.fullDateFormatter.date(from: dateString) else {
      completion(.failure(TransactionError.invalidDateFormat))
      return
    }

    guard
      let category = TransactionCategory.allCases
        .first(where: { $0.key == categoryKey })
    else {
      completion(.failure(TransactionError.invalidCategory))
      return
    }

    guard
      let type = TransactionType.allCases
        .first(where: { String(describing: $0) == typeRaw })
    else {
      completion(.failure(TransactionError.invalidType))
      return
    }

    let timestamp = Int(date.timeIntervalSince1970)
    let anchor = date.monthAnchor

    let model = TransactionModel(
      title: title,
      category: category.key,
      amount: amount,
      type: type.key,
      dateTimestamp: timestamp,
      budgetMonthDate: anchor,
      isRecurring: true,
      creditCardId: creditCardId
    )

    do {
      let insertedId = try transactionRepo.insertTransactionAndGetId(model)

      // Check for similar existing recurring transactions
      if let existingSimilar = recurringManager.findSimilarRecurringTransaction(
        title: title,
        category: category.key,
        amount: amount,
        type: type.key
      ), let existingId = existingSimilar.id {
        try recurringManager.linkToExistingRecurringTransaction(
          newTransactionId: insertedId,
          existingParentId: existingId
        )
      } else {
        try transactionRepo.updateParentTransactionId(
          transactionId: insertedId, parentId: insertedId)
      }

      // Assign parent recurring transaction to credit card statement
      if let cardId = creditCardId, let card = creditCardRepo.fetchCard(byId: cardId) {
        guard let uid = AuthenticationManager.shared.currentUser?.uid else {
          completion(.success(()))
          return
        }
        if let statement = creditCardService.getOrCreateStatement(for: card, transactionDate: date, userId: uid) {
          try transactionRepo.updateCreditCardFields(
            transactionId: insertedId,
            creditCardId: cardId,
            statementId: statement.id!,
            isCreditCardStatement: false
          )
          creditCardService.recalculateStatementTotal(statementId: statement.id!)
        }
      }

      // Generate instances for immediate window (next 2 months)
      let immediateMonthAnchors: Set<Int> = {
        var anchors = Set<Int>()
        for monthOffset in 1...2 {
          if let futureDate = calendar.date(byAdding: .month, value: monthOffset, to: date) {
            anchors.insert(futureDate.monthAnchor)
          }
        }
        return anchors
      }()

      // Wait for instance generation to complete before calling completion
      recurringManager.generateInstancesLazilyForMonths(immediateMonthAnchors) { [weak self] _ in
        guard let self = self else {
          DispatchQueue.main.async { completion(.success(())) }
          return
        }

        // These operations run on background thread
        self.scheduleNotificationsForRecurringTransactions()
        self.monitorNegativeBalance()

        // Invalidate cache and call completion on main thread
        DispatchQueue.main.async {
          self.invalidateLedgerCache()
          completion(.success(()))
        }
      }

    } catch {
      completion(.failure(error))
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

      // LAZY GENERATION: Only create immediate installments (first 3 months)
      // Additional installments will be generated lazily when the user navigates to those months
      let immediateInstallmentCount = min(3, totalInstallments)

      var allInstallments: [TransactionModel] = []

      for installmentNumber in 1...immediateInstallmentCount {
        // Calcular a data da parcela usando a função de geração de datas válidas
        let targetDate =
          calendar.date(byAdding: .month, value: installmentNumber - 1, to: startDate) ?? startDate
        let targetYear = calendar.component(.year, from: targetDate)
        let targetMonth = calendar.component(.month, from: targetDate)

        let installmentDate = generateValidDateForMonth(
          originalDate: startDate,
          targetMonth: targetMonth,
          targetYear: targetYear
        )

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

        _ = try transactionRepo.insertTransactionAndGetId(installmentModel)

        // Adicionar à lista para notificações otimizadas
        allInstallments.append(installmentModel)
      }

      // Agendar notificações otimizadas para as parcelas criadas
      scheduleOptimizedNotificationsForInstallments(allInstallments)

      // Monitorar saldo negativo após adicionar transação parcelada
      monitorNegativeBalance()

      // Invalidate ledger cache since transactions changed
      invalidateLedgerCache()

      return .success(())
    } catch {
      return .failure(error)
    }
  }

  /// Async version for installment transaction creation
  func addTransactionWithInstallmentsAsync(
    _ data: InstallmentTransactionData,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    let totalInstallments = data.installments
    guard totalInstallments > 1 else {
      completion(.failure(TransactionError.invalidInstallmentCount))
      return
    }

    guard let startDate = DateFormatter.fullDateFormatter.date(from: data.date) else {
      completion(.failure(TransactionError.invalidDateFormat))
      return
    }

    guard
      let category = TransactionCategory.allCases
        .first(where: { $0.key == data.category })
    else {
      completion(.failure(TransactionError.invalidCategory))
      return
    }

    guard
      let type = TransactionType.allCases
        .first(where: { String(describing: $0) == data.transactionType })
    else {
      completion(.failure(TransactionError.invalidType))
      return
    }

    let amountPerInstallment = data.totalAmount / totalInstallments
    let remainder = data.totalAmount % totalInstallments

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else {
        DispatchQueue.main.async { completion(.failure(TransactionError.repositoryUnavailable)) }
        return
      }

      do {
        // Create parent transaction
        let parentModel = TransactionModel(
          title: "\(data.title) - Installment Parent",
          category: category.key,
          amount: 0,
          type: type.key,
          dateTimestamp: Int(startDate.timeIntervalSince1970),
          budgetMonthDate: startDate.monthAnchor,
          hasInstallments: true,
          originalAmount: data.totalAmount,
          totalInstallments: totalInstallments
        )

        let parentId = try self.transactionRepo.insertTransactionAndGetId(parentModel)

        // Create immediate installments (first 3 months)
        let immediateInstallmentCount = min(3, totalInstallments)
        var allInstallments: [TransactionModel] = []

        for installmentNumber in 1...immediateInstallmentCount {
          let targetDate =
            self.calendar.date(byAdding: .month, value: installmentNumber - 1, to: startDate)
            ?? startDate
          let targetYear = self.calendar.component(.year, from: targetDate)
          let targetMonth = self.calendar.component(.month, from: targetDate)

          let installmentDate = self.generateValidDateForMonth(
            originalDate: startDate,
            targetMonth: targetMonth,
            targetYear: targetYear
          )

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

          let insertedInstallmentId = try self.transactionRepo.insertTransactionAndGetId(installmentModel)
          allInstallments.append(installmentModel)

          // Assign installment to correct credit card statement
          if let cardId = data.creditCardId, let card = self.creditCardRepo.fetchCard(byId: cardId) {
            guard let uid = AuthenticationManager.shared.currentUser?.uid else { break }
            if let statement = self.creditCardService.getOrCreateStatement(for: card, transactionDate: installmentDate, userId: uid) {
              try self.transactionRepo.updateCreditCardFields(
                transactionId: insertedInstallmentId,
                creditCardId: cardId,
                statementId: statement.id!,
                isCreditCardStatement: false
              )
              self.creditCardService.recalculateStatementTotal(statementId: statement.id!)
            }
          }
        }

        // Schedule notifications
        self.scheduleOptimizedNotificationsForInstallments(allInstallments)
        self.monitorNegativeBalance()

        DispatchQueue.main.async {
          self.invalidateLedgerCache()
          completion(.success(()))
        }

      } catch {
        DispatchQueue.main.async {
          completion(.failure(error))
        }
      }
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

  /// Sistema otimizado para agendar notificações de parcelas
  private func scheduleOptimizedNotificationsForInstallments(_ installments: [TransactionModel]) {
    // Agrupar parcelas por mês
    var installmentsByMonth: [String: [TransactionModel]] = [:]

    for installment in installments {
      let date = Date(timeIntervalSince1970: TimeInterval(installment.data.dateTimestamp))
      let monthKey =
        "\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))"

      if installmentsByMonth[monthKey] == nil {
        installmentsByMonth[monthKey] = []
      }
      installmentsByMonth[monthKey]?.append(installment)
    }

    // Agendar notificação para cada mês (máximo 1 por mês)
    for (monthKey, monthInstallments) in installmentsByMonth {
      scheduleMonthlyInstallmentNotification(monthKey: monthKey, installments: monthInstallments)
    }
  }

  /// Agenda uma notificação mensal para todas as parcelas do mês
  private func scheduleMonthlyInstallmentNotification(
    monthKey: String, installments: [TransactionModel]
  ) {
    guard let firstInstallment = installments.first else { return }

    let date = Date(timeIntervalSince1970: TimeInterval(firstInstallment.data.dateTimestamp))

    // Verificar se a data é muito no futuro (mais de 1 ano)
    let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    if date > oneYearFromNow {
      return
    }

    // Create notification time (8 AM) in local timezone
    var notificationDate = calendar.startOfDay(for: date)
    notificationDate =
      calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    // Only schedule if notification time is in the future
    guard notificationDate > Date() else {
      return
    }

    let timeInterval = notificationDate.timeIntervalSinceNow

    // Verificar se o intervalo é muito grande (mais de 30 dias)
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    if timeInterval > thirtyDaysInSeconds {
      scheduleReminderNotification(for: monthKey, installments: installments)
      return
    }

    // Criar notificação mensal consolidada
    let totalAmount = installments.reduce(0) { $0 + $1.data.amount }
    let installmentCount = installments.count

    let title = "notification.installment.title".localized
    let bodyKey =
      installmentCount == 1
      ? "notification.installment.body.singular" : "notification.installment.body.plural"
    let body =
      installmentCount == 1
      ? String(format: bodyKey.localized, totalAmount.currencyString)
      : String(format: bodyKey.localized, installmentCount, totalAmount.currencyString)

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = [
      "type": "installment_month",
      "monthKey": monthKey,
      "installmentCount": installmentCount,
      "totalAmount": totalAmount,
    ]

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
    let request = UNNotificationRequest(
      identifier: "installment_month_\(monthKey)", content: content, trigger: trigger)

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling installment notification for month \(monthKey): \(error)")
      }
    }
  }

  /// Agenda uma notificação de lembrete para parcelas distantes (mais de 30 dias)
  private func scheduleReminderNotification(for monthKey: String, installments: [TransactionModel])
  {
    // For installments more than 30 days away, schedule a reminder for 30 days from now
    // This reminder will trigger the app to reschedule the actual notifications when closer
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: thirtyDaysInSeconds, repeats: false)

    let content = UNMutableNotificationContent()
    content.title = "notification.installment.reminder.title".localized
    content.body = "notification.installment.reminder.body".localized
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = ["type": "installment_reminder", "monthKey": monthKey]

    let request = UNNotificationRequest(
      identifier: "installment_reminder_\(monthKey)", content: content, trigger: trigger)

    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling installment reminder for month \(monthKey): \(error)")
      }
    }
  }

  private func scheduleNotification(for transactionId: Int, model: TransactionModel) {
    let date = Date(timeIntervalSince1970: TimeInterval(model.data.dateTimestamp))

    // Verificar se a data é muito no futuro (mais de 1 ano)
    let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    if date > oneYearFromNow {
      return
    }

    // Create notification time (8 AM) in local timezone
    var notificationDate = calendar.startOfDay(for: date)
    notificationDate =
      calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    // Only schedule if notification time is in the future
    guard notificationDate > Date() else {
      return
    }

    // Verificar se já existe uma notificação para este dia
    let dayIdentifier = "day_\(calendar.startOfDay(for: date).timeIntervalSince1970)"

    // Limpar notificações antigas para este dia se existirem
    notificationCenter.removePendingNotificationRequests(withIdentifiers: [dayIdentifier])

    let id = "transaction_\(transactionId)"
    let timeInterval = notificationDate.timeIntervalSinceNow

    // Verificar se o intervalo é muito grande (mais de 30 dias)
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    if timeInterval > thirtyDaysInSeconds {
      // Agendar para 30 dias e depois reagendar quando chegar mais perto
      let adjustedInterval = thirtyDaysInSeconds
      let trigger = UNTimeIntervalNotificationTrigger(
        timeInterval: adjustedInterval, repeats: false)

      let content = UNMutableNotificationContent()
      content.title = "notification.transaction.reminder.title".localized
      content.body = "notification.transaction.reminder.body".localized
      content.sound = .default
      content.categoryIdentifier = "TRANSACTION_REMINDER"
      content.userInfo = ["type": "reminder", "transactionId": transactionId]

      let request = UNNotificationRequest(
        identifier: dayIdentifier, content: content, trigger: trigger)
      notificationCenter.add(request) { error in
        if let error = error {
          logError("Error scheduling reminder notification: \(error)")
        }
      }
      return
    }

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
    content.userInfo = ["transactionId": transactionId, "date": date.timeIntervalSince1970]

    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    notificationCenter.add(request) { error in
      if let error = error {
        logError("Error scheduling notification for \(model.data.title): \(error)")
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
        logError("Error scheduling notification for \(tx.title): \(error)")
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

    // Calcular o último dia do mês específico primeiro
    let lastDayOfMonth: Int

    switch targetMonth {
    case 2:  // Fevereiro
      let isLeapYear = (targetYear % 4 == 0 && targetYear % 100 != 0) || (targetYear % 400 == 0)
      lastDayOfMonth = isLeapYear ? 29 : 28
    case 4, 6, 9, 11:  // Abril, Junho, Setembro, Novembro
      lastDayOfMonth = 30
    default:  // Janeiro, Março, Maio, Julho, Agosto, Outubro, Dezembro
      lastDayOfMonth = 31
    }

    // Determinar o dia a usar
    let dayToUse = min(originalDay, lastDayOfMonth)

    // Criar a data com o dia determinado
    var dateComponents = DateComponents()
    dateComponents.year = targetYear
    dateComponents.month = targetMonth
    dateComponents.day = dayToUse
    dateComponents.hour = 12  // Usar meio-dia para evitar problemas de fuso horário
    dateComponents.minute = 0
    dateComponents.second = 0

    // Criar a data
    guard let validDate = calendar.date(from: dateComponents) else {
      logError("Failed to create date for \(dayToUse)/\(targetMonth)/\(targetYear), using fallback")
      // Fallback: usar o primeiro dia do mês
      dateComponents.day = 1
      let fallbackDate = calendar.date(from: dateComponents) ?? Date()
      return fallbackDate
    }

    return validDate
  }

  // MARK: - Balance Monitoring

  /// Monitora o saldo negativo do mês atual
  private func monitorNegativeBalance() {
    // Check if user is authenticated first
    guard let user = UserDefaultsManager.getUser(),
      let firebaseUID = user.firebaseUID
    else {
      return
    }

    // Create balance monitor and check current month
    let balanceMonitor = BalanceMonitorManager()
    balanceMonitor.monitorCurrentMonthBalance()
  }

  // MARK: - Update Transaction Methods

  func updateTransaction(
    id: Int,
    title: String,
    amount: Int,
    dateString: String,
    categoryKey: String,
    typeRaw: String,
    isRecurring: Bool = false,
    creditCardId: Int? = nil
  ) -> Result<Void, Error> {

    guard
      let transactionCategory = TransactionCategory.allCases.first(where: { $0.key == categoryKey })
    else {
      return .failure(TransactionError.invalidCategory)
    }

    guard
      let transactionType = TransactionType.allCases.first(where: {
        String(describing: $0) == typeRaw
      })
    else {
      return .failure(TransactionError.invalidType)
    }

    guard let dateObj = DateFormatter.fullDateFormatter.date(from: dateString) else {
      return .failure(TransactionError.invalidDateFormat)
    }

    do {
      // Look up original transaction to preserve CC fields and recalculate statement
      let originalTransaction = transactionRepo.fetchAllTransactions().first(where: { $0.id == id })
      let originalCreditCardId = originalTransaction?.creditCardId
      let originalStatementId = originalTransaction?.statementId

      // Determine new credit card and statement assignment
      var newCreditCardId: Int? = creditCardId
      var newStatementId: Int? = originalStatementId

      let creditCardChanged = creditCardId != originalCreditCardId

      if creditCardChanged {
        if let cardId = creditCardId, let card = creditCardRepo.fetchCard(byId: cardId) {
          // Assigned to a credit card (new or changed)
          guard let uid = AuthenticationManager.shared.currentUser?.uid else {
            return .failure(TransactionError.repositoryUnavailable)
          }
          if let statement = creditCardService.getOrCreateStatement(for: card, transactionDate: dateObj, userId: uid) {
            newStatementId = statement.id
            newCreditCardId = cardId
          }
        } else {
          // Removed from credit card → cash/debit
          newCreditCardId = nil
          newStatementId = nil
        }
      } else if let cardId = creditCardId, let card = creditCardRepo.fetchCard(byId: cardId) {
        // Same card but date might have changed → recalculate statement
        guard let uid = AuthenticationManager.shared.currentUser?.uid else {
          return .failure(TransactionError.repositoryUnavailable)
        }
        if let statement = creditCardService.getOrCreateStatement(for: card, transactionDate: dateObj, userId: uid) {
          newStatementId = statement.id
        }
      }

      let updatedTransaction = TransactionModel(
        id: id,
        title: title,
        category: transactionCategory.key,
        amount: amount,
        type: String(describing: transactionType),
        dateTimestamp: Int(dateObj.timeIntervalSince1970),
        budgetMonthDate: dateObj.monthAnchor,
        isRecurring: isRecurring,
        hasInstallments: false,
        parentTransactionId: nil,
        originalAmount: amount,
        installmentNumber: nil,
        totalInstallments: nil,
        creditCardId: newCreditCardId,
        statementId: newStatementId,
        isCreditCardStatement: newCreditCardId != nil ? false : nil
      )

      try transactionRepo.updateTransaction(updatedTransaction)

      // Recalculate old statement if transaction moved away from it
      if let oldStmtId = originalStatementId, oldStmtId != newStatementId {
        creditCardService.recalculateStatementTotal(statementId: oldStmtId)
      }

      // Recalculate new statement
      if let newStmtId = newStatementId {
        creditCardService.recalculateStatementTotal(statementId: newStmtId)
      }

      invalidateLedgerCache()
      return .success(())

    } catch {
      return .failure(error)
    }
  }

  func updateTransactionWithInstallments(id: Int, _ data: InstallmentTransactionData) -> Result<
    Void, Error
  > {
    guard
      let transactionCategory = TransactionCategory.allCases.first(where: {
        $0.key == data.category
      })
    else {
      return .failure(TransactionError.invalidCategory)
    }

    guard
      let transactionType = TransactionType.allCases.first(where: {
        String(describing: $0) == data.transactionType
      })
    else {
      return .failure(TransactionError.invalidType)
    }

    guard let dateObj = DateFormatter.fullDateFormatter.date(from: data.date) else {
      return .failure(TransactionError.invalidDateFormat)
    }

    guard data.installments > 0 && data.installments <= 120 else {
      return .failure(TransactionError.invalidInstallmentCount)
    }

    do {
      // Find the existing transaction to get its parent ID
      let existingTransactions = transactionRepo.fetchAllTransactions()
      guard let existingTransaction = existingTransactions.first(where: { $0.id == id }) else {
        logError("Could not find transaction with ID: \(id)")
        return .failure(TransactionError.transactionNotFound)
      }

      // For installment transactions, we need to find the main installment transaction
      // (the one with hasInstallments=true and parentTransactionId=nil)
      let mainInstallmentTransaction: Transaction
      if let parentId = existingTransaction.parentTransactionId {
        // This is an individual installment, find the main installment transaction

        // The main installment transaction has hasInstallments=true and parentTransactionId=nil
        // First try to find by exact ID match
        if let mainTransaction = existingTransactions.first(where: {
          $0.hasInstallments == true && $0.parentTransactionId == nil && $0.id == parentId
        }) {
          mainInstallmentTransaction = mainTransaction
        } else {
          // Try to find the main installment transaction by looking for any transaction
          // with hasInstallments=true and parentTransactionId=nil in the same month

          let individualInstallmentMonth = existingTransaction.budgetMonthDate
          if let fallbackMainTransaction = existingTransactions.first(where: {
            $0.hasInstallments == true && $0.parentTransactionId == nil
              && $0.budgetMonthDate == individualInstallmentMonth && $0.amount == 0  // Main installment transactions typically have amount 0
          }) {

            // Update all individual installments to point to the correct main transaction
            let individualInstallments = existingTransactions.filter {
              $0.parentTransactionId == parentId
            }

            for installment in individualInstallments {
              // Update the installment to point to the correct main transaction
              try transactionRepo.updateSingleTransactionOnly(
                id: installment.id ?? 0,
                title: installment.title,
                category: installment.category,
                type: installment.type,
                amount: installment.amount,
                date: installment.date
              )
            }

            mainInstallmentTransaction = fallbackMainTransaction
          } else {
            // Main installment transaction is missing - this is a data inconsistency
            // We'll create a new main installment transaction to fix this

            // Find the first individual installment to get the basic info
            guard
              let firstInstallment = existingTransactions.first(where: {
                $0.parentTransactionId == parentId
              })
            else {
              logError("Could not find any individual installments for parent ID: \(parentId)")
              return .failure(TransactionError.transactionNotFound)
            }

            // Create a new main installment transaction
            let newMainTransaction = TransactionModel(
              id: nil,  // Let the database auto-generate the ID
              title: firstInstallment.title,
              category: firstInstallment.category.key,
              amount: 0,  // Zero amount for parent transaction
              type: String(describing: firstInstallment.type),
              dateTimestamp: Int(firstInstallment.date.timeIntervalSince1970),
              budgetMonthDate: firstInstallment.budgetMonthDate,
              isRecurring: false,
              hasInstallments: true,
              parentTransactionId: nil,
              originalAmount: nil,
              installmentNumber: nil,
              totalInstallments: firstInstallment.totalInstallments
            )

            // Insert the new main transaction
            let newMainTransactionId: Int
            do {
              newMainTransactionId = try transactionRepo.insertTransactionAndGetId(
                newMainTransaction)

              // Delete the old main installment transaction if it exists
              if let oldMainTransaction = existingTransactions.first(where: {
                $0.hasInstallments == true && $0.parentTransactionId == nil
                  && $0.budgetMonthDate == individualInstallmentMonth && $0.amount == 0
                  && $0.id != parentId  // Don't delete the one we just created
              }) {
                try transactionRepo.delete(id: oldMainTransaction.id ?? 0)
              }

              // Update all individual installments to point to the new main transaction
              let individualInstallments = existingTransactions.filter {
                $0.parentTransactionId == parentId
              }

              for installment in individualInstallments {
                // Update the installment to point to the new main transaction
                try transactionRepo.updateTransactionParentId(
                  transactionId: installment.id ?? 0,
                  parentId: newMainTransactionId
                )
              }

            } catch {
              logError("Failed to create main installment transaction: \(error)")
              return .failure(error)
            }

            // Convert to Transaction for consistency
            let newMainTransactionData = UITransactionData(
              id: newMainTransactionId,
              title: firstInstallment.title,
              amount: 0,
              dateTimestamp: Int(firstInstallment.date.timeIntervalSince1970),
              budgetMonthDate: firstInstallment.budgetMonthDate,
              isRecurring: false,
              hasInstallments: true,
              parentTransactionId: nil,
              installmentNumber: nil,
              totalInstallments: firstInstallment.totalInstallments,
              originalAmount: nil,
              category: firstInstallment.category,
              type: firstInstallment.type
            )

            mainInstallmentTransaction = Transaction(data: newMainTransactionData)
          }
        }

        // After finding/creating the main installment transaction, we need to ensure
        // that the transaction details screen will show the correct individual installment
        // We'll update the individual installment that was being edited to point to the correct main transaction
        if let currentInstallmentId = existingTransaction.id {
          // Update the current individual installment to ensure it points to the correct main transaction
          try transactionRepo.updateSingleTransactionOnly(
            id: currentInstallmentId,
            title: existingTransaction.title,
            category: existingTransaction.category,
            type: existingTransaction.type,
            amount: existingTransaction.amount,
            date: existingTransaction.date
          )
        }
      } else {
        // This is already the main installment transaction
        mainInstallmentTransaction = existingTransaction
      }

      let updatedTransaction = TransactionModel(
        id: mainInstallmentTransaction.id,  // Use the main installment transaction ID
        title: data.title,
        category: transactionCategory.key,
        amount: data.totalAmount,
        type: String(describing: transactionType),
        dateTimestamp: Int(dateObj.timeIntervalSince1970),
        budgetMonthDate: dateObj.monthAnchor,
        isRecurring: false,
        hasInstallments: true,
        parentTransactionId: nil,
        originalAmount: data.totalAmount,
        installmentNumber: nil,
        totalInstallments: data.installments,
        creditCardId: data.creditCardId,
        isCreditCardStatement: data.creditCardId != nil ? false : nil
      )

      do {
        try transactionRepo.updateTransaction(updatedTransaction)
        invalidateLedgerCache()
        return .success(())
      } catch {
        logError("Installment update error: \(error)")
        return .failure(error)
      }

    } catch {
      return .failure(error)
    }
  }

  func updateSingleTransaction(
    id: Int,
    title: String,
    amount: Int,
    dateString: String,
    categoryKey: String,
    typeRaw: String,
    creditCardId: Int? = nil
  ) -> Result<Void, Error> {

    guard
      let transactionCategory = TransactionCategory.allCases.first(where: { $0.key == categoryKey })
    else {
      return .failure(TransactionError.invalidCategory)
    }

    guard
      let transactionType = TransactionType.allCases.first(where: {
        String(describing: $0) == typeRaw
      })
    else {
      return .failure(TransactionError.invalidType)
    }

    guard let dateObj = DateFormatter.fullDateFormatter.date(from: dateString) else {
      return .failure(TransactionError.invalidDateFormat)
    }

    do {
      // Look up original transaction to check CC fields
      let originalTransaction = transactionRepo.fetchAllTransactions().first(where: { $0.id == id })
      let originalCreditCardId = originalTransaction?.creditCardId
      let originalStatementId = originalTransaction?.statementId

      try transactionRepo.updateSingleTransactionOnly(
        id: id,
        title: title,
        category: transactionCategory,
        type: transactionType,
        amount: amount,
        date: dateObj
      )

      // Handle credit card statement assignment
      let creditCardChanged = creditCardId != originalCreditCardId
      var newStatementId: Int? = originalStatementId

      if creditCardChanged {
        if let cardId = creditCardId, let card = creditCardRepo.fetchCard(byId: cardId) {
          // Assigned to a credit card (new or changed)
          guard let uid = AuthenticationManager.shared.currentUser?.uid else {
            invalidateLedgerCache()
            return .success(())
          }
          if let statement = creditCardService.getOrCreateStatement(for: card, transactionDate: dateObj, userId: uid) {
            try transactionRepo.updateCreditCardFields(
              transactionId: id,
              creditCardId: cardId,
              statementId: statement.id!,
              isCreditCardStatement: false
            )
            newStatementId = statement.id
          }
        } else {
          // Removed from credit card
          try transactionRepo.clearCreditCardFields(transactionId: id)
          newStatementId = nil
        }
      } else if let cardId = creditCardId, let card = creditCardRepo.fetchCard(byId: cardId) {
        // Same card but date might have changed → recalculate statement
        guard let uid = AuthenticationManager.shared.currentUser?.uid else {
          invalidateLedgerCache()
          return .success(())
        }
        if let statement = creditCardService.getOrCreateStatement(for: card, transactionDate: dateObj, userId: uid) {
          try transactionRepo.updateCreditCardFields(
            transactionId: id,
            creditCardId: cardId,
            statementId: statement.id!,
            isCreditCardStatement: false
          )
          newStatementId = statement.id
        }
      }

      // Recalculate old statement if transaction moved away from it
      if let oldStmtId = originalStatementId, oldStmtId != newStatementId {
        creditCardService.recalculateStatementTotal(statementId: oldStmtId)
      }

      // Recalculate new statement
      if let newStmtId = newStatementId {
        creditCardService.recalculateStatementTotal(statementId: newStmtId)
      }

      invalidateLedgerCache()
      return .success(())

    } catch {
      return .failure(error)
    }
  }

  func updateSingleTransactionWithInstallments(id: Int, _ data: InstallmentTransactionData)
    -> Result<Void, Error>
  {
    guard
      let transactionCategory = TransactionCategory.allCases.first(where: {
        $0.key == data.category
      })
    else {
      return .failure(TransactionError.invalidCategory)
    }

    guard
      let transactionType = TransactionType.allCases.first(where: {
        String(describing: $0) == data.transactionType
      })
    else {
      return .failure(TransactionError.invalidType)
    }

    guard let dateObj = DateFormatter.fullDateFormatter.date(from: data.date) else {
      return .failure(TransactionError.invalidDateFormat)
    }

    do {
      try transactionRepo.updateSingleTransactionOnly(
        id: id,
        title: data.title,
        category: transactionCategory,
        type: transactionType,
        amount: data.totalAmount,
        date: dateObj
      )
      invalidateLedgerCache()
      return .success(())

    } catch {
      return .failure(error)
    }
  }

  // MARK: - Ledger Cache Management

  /// Invalidates the transaction ledger cache to ensure fresh calculations
  func updateRecurringTransactionWithOption(
    id: Int,
    title: String,
    amount: Int,
    dateString: String,
    categoryKey: String,
    typeRaw: String,
    editOption: RecurringEditOption
  ) -> Result<Void, Error> {

    guard
      let transactionCategory = TransactionCategory.allCases.first(where: { $0.key == categoryKey })
    else {
      return .failure(TransactionError.invalidCategory)
    }

    guard
      let transactionType = TransactionType.allCases.first(where: {
        String(describing: $0) == typeRaw
      })
    else {
      return .failure(TransactionError.invalidType)
    }

    guard let dateObj = DateFormatter.fullDateFormatter.date(from: dateString) else {
      return .failure(TransactionError.invalidDateFormat)
    }

    do {
      // Find the existing transaction to get its parent ID and determine if it's a recurring transaction
      let existingTransactions = transactionRepo.fetchAllTransactions()
      guard let existingTransaction = existingTransactions.first(where: { $0.id == id }) else {
        logError("Could not find transaction with ID: \(id)")
        return .failure(TransactionError.transactionNotFound)
      }

      // Determine the parent transaction ID for recurring transactions
      let parentTransactionId: Int
      if let parentId = existingTransaction.parentTransactionId {
        // This is a recurring instance, use the parent ID
        parentTransactionId = parentId
      } else if existingTransaction.isRecurring == true {
        // This is the parent recurring transaction
        parentTransactionId = id
      } else {
        // Not a recurring transaction, use regular update
        return updateTransaction(
          id: id,
          title: title,
          amount: amount,
          dateString: dateString,
          categoryKey: categoryKey,
          typeRaw: typeRaw,
          isRecurring: true
        )
      }

      // Create the new transaction data
      let newTransactionData = TransactionModel(
        id: id,
        title: title,
        category: transactionCategory.key,
        amount: amount,
        type: String(describing: transactionType),
        dateTimestamp: Int(dateObj.timeIntervalSince1970),
        budgetMonthDate: dateObj.monthAnchor,
        isRecurring: true,
        hasInstallments: false,
        parentTransactionId: parentTransactionId,
        originalAmount: amount,
        installmentNumber: nil,
        totalInstallments: nil
      )

      // Use the recurring transaction manager to handle the edit with the specified option
      try recurringManager.editRecurringTransactionsFromDate(
        parentTransactionId: parentTransactionId,
        selectedTransactionDate: dateObj,
        editOption: editOption,
        newData: newTransactionData
      )

      invalidateLedgerCache()
      return .success(())

    } catch {
      return .failure(error)
    }
  }

  /// Async version that doesn't block the UI
  func updateRecurringTransactionWithOptionAsync(
    id: Int,
    title: String,
    amount: Int,
    dateString: String,
    categoryKey: String,
    typeRaw: String,
    creditCardId: Int? = nil,
    editOption: RecurringEditOption,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard
      let transactionCategory = TransactionCategory.allCases.first(where: { $0.key == categoryKey })
    else {
      completion(.failure(TransactionError.invalidCategory))
      return
    }

    guard
      let transactionType = TransactionType.allCases.first(where: {
        String(describing: $0) == typeRaw
      })
    else {
      completion(.failure(TransactionError.invalidType))
      return
    }

    guard let dateObj = DateFormatter.fullDateFormatter.date(from: dateString) else {
      completion(.failure(TransactionError.invalidDateFormat))
      return
    }

    // Run heavy work on background queue
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else {
        DispatchQueue.main.async { completion(.failure(TransactionError.repositoryUnavailable)) }
        return
      }

      // Find the existing transaction to get its parent ID
      let existingTransactions = self.transactionRepo.fetchAllTransactions()
      guard let existingTransaction = existingTransactions.first(where: { $0.id == id }) else {
        DispatchQueue.main.async { completion(.failure(TransactionError.transactionNotFound)) }
        return
      }

      // Determine the parent transaction ID for recurring transactions
      let parentTransactionId: Int
      if let parentId = existingTransaction.parentTransactionId {
        parentTransactionId = parentId
      } else if existingTransaction.isRecurring == true {
        parentTransactionId = id
      } else {
        // Not a recurring transaction - fallback to sync update
        DispatchQueue.main.async {
          let result = self.updateTransaction(
            id: id,
            title: title,
            amount: amount,
            dateString: dateString,
            categoryKey: categoryKey,
            typeRaw: typeRaw,
            isRecurring: true,
            creditCardId: creditCardId
          )
          completion(result)
        }
        return
      }

      // Create the new transaction data
      let newTransactionData = TransactionModel(
        id: id,
        title: title,
        category: transactionCategory.key,
        amount: amount,
        type: String(describing: transactionType),
        dateTimestamp: Int(dateObj.timeIntervalSince1970),
        budgetMonthDate: dateObj.monthAnchor,
        isRecurring: true,
        hasInstallments: false,
        parentTransactionId: parentTransactionId,
        originalAmount: amount,
        installmentNumber: nil,
        totalInstallments: nil,
        creditCardId: creditCardId
      )

      // Use async editing method
      self.recurringManager.editRecurringTransactionsFromDateAsync(
        parentTransactionId: parentTransactionId,
        selectedTransactionDate: dateObj,
        editOption: editOption,
        newData: newTransactionData
      ) { [weak self] result in
        if case .success = result {
          self?.invalidateLedgerCache()
        }
        completion(result)
      }
    }
  }

  private func invalidateLedgerCache() {
    // Post notification to invalidate ledger cache
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
  }
}
