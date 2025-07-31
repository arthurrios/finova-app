//
//  RecurringTransactionManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 10/06/25.
//

import Foundation
import NotificationCenter

enum RecurringCleanupOption {
  case all
  case futureOnly
}

final class RecurringTransactionManager {
  private let transactionRepo: TransactionRepository
  private let calendar: Calendar
  private let notificationCenter = UNUserNotificationCenter.current()

  init(transactionRepo: TransactionRepository = TransactionRepository()) {
    self.transactionRepo = transactionRepo
    
    // Usar calendar com fuso horário UTC para consistência com monthAnchor
    var utcCalendar = Calendar(identifier: .gregorian)
    utcCalendar.timeZone = TimeZone(abbreviation: "UTC")!
    self.calendar = utcCalendar
  }

  func generateRecurringTransactionsForRange(
    _ monthRange: ClosedRange<Int>,
    referenceDate: Date = Date(),
    transactionStartDate: Date? = nil
  ) {
    let recurringTransactions = transactionRepo.fetchRecurringTransactions()

    for recurringTx in recurringTransactions {
      generateInstancesForTransaction(
        recurringTx,
        in: monthRange,
        referenceDate: referenceDate,
        transactionStartDate: transactionStartDate
      )
    }
  }

  func generateInstancesForTransaction(
    _ recurringTx: Transaction,
    in monthRange: ClosedRange<Int>,
    referenceDate: Date,
    transactionStartDate: Date? = nil
  ) {
    guard let recurringTxId = recurringTx.id else { return }

    print("🔄 Generating instances for recurring transaction: '\(recurringTx.title)'")
    print("📅 Range: \(monthRange), Reference date: \(referenceDate)")

    // Get existing instances for this specific recurring transaction only
    let existingInstances = transactionRepo.fetchTransactionInstancesForRecurring(recurringTxId)
    let existingAnchors = Set(existingInstances.map { $0.budgetMonthDate })
    let recurringStartAnchor = recurringTx.budgetMonthDate

    print("📊 Existing instances: \(existingInstances.count)")
    print("📊 Existing anchors: \(existingAnchors)")

    // Coletar todas as novas instâncias para agendar notificações otimizadas
    var newInstances: [TransactionModel] = []

    for monthOffset in monthRange {
      guard let targetDate = calendar.date(byAdding: .month, value: monthOffset, to: referenceDate)
      else { continue }

      let targetAnchor = targetDate.monthAnchor

      let effectiveStartAnchor: Int
      if let startDate = transactionStartDate {
        effectiveStartAnchor = startDate.monthAnchor
      } else {
        effectiveStartAnchor = recurringStartAnchor
      }

      print("📅 Processing month offset \(monthOffset): targetDate=\(targetDate), targetAnchor=\(targetAnchor)")

      // Skip if an instance already exists for this period
      if existingAnchors.contains(targetAnchor) {
        print("⏭️ Skipping month \(targetAnchor) - instance already exists")
        continue
      }

      // Create instances for the effective start anchor and all future periods
      if targetAnchor >= effectiveStartAnchor {
        let originalDate = Date(timeIntervalSince1970: TimeInterval(recurringTx.dateTimestamp))
        
        print("📅 Original date: \(originalDate)")
        print("📅 Original day: \(calendar.component(.day, from: originalDate))")
        
        // Usar a nova função para gerar data válida
        let targetYear = calendar.component(.year, from: targetDate)
        let targetMonth = calendar.component(.month, from: targetDate)
        let instanceDate = generateValidDateForMonth(
          originalDate: originalDate,
          targetMonth: targetMonth,
          targetYear: targetYear
        )

        print("📅 Generated date: \(instanceDate)")
        print("📅 Generated day: \(calendar.component(.day, from: instanceDate))")

        // Verificar se a data gerada está no mês correto
        let generatedAnchor = instanceDate.monthAnchor
        print("📊 Target anchor: \(targetAnchor), Generated anchor: \(generatedAnchor)")
        
        // Usar o anchor gerado em vez do target anchor
        let finalAnchor = generatedAnchor
        print("🎯 Using final anchor: \(finalAnchor)")

        // Verificação adicional: não criar se já existe uma instância para este mês
        let existingInstancesForMonth = existingInstances.filter { $0.budgetMonthDate == finalAnchor }
        if !existingInstancesForMonth.isEmpty {
          print("⏭️ Skipping month \(finalAnchor) - already has \(existingInstancesForMonth.count) instance(s)")
          continue
        }

        // Verificação adicional: não criar se já existe uma instância para este anchor específico
        if existingAnchors.contains(finalAnchor) {
          print("⏭️ Skipping final anchor \(finalAnchor) - already exists in existingAnchors")
          continue
        }

        print("✅ Creating instance for anchor: \(finalAnchor)")

        // Create the instance
        let instanceModel = TransactionModel(
          title: recurringTx.title,
          category: recurringTx.category.key,
          amount: recurringTx.amount,
          type: recurringTx.type.key,
          dateTimestamp: Int(instanceDate.timeIntervalSince1970),
          budgetMonthDate: finalAnchor,
          parentTransactionId: recurringTxId
        )

        do {
          try transactionRepo.insertTransaction(instanceModel)
          print("✅ Created recurring instance: \(recurringTx.title) for \(instanceDate)")
          
          // Adicionar à lista para notificações otimizadas
          newInstances.append(instanceModel)
        } catch {
          print("❌ Error creating recurring transaction instance: \(error)")
        }
      }
    }
    
    // Agendar notificações otimizadas para todas as novas instâncias
    if !newInstances.isEmpty {
      scheduleOptimizedNotificationsForRecurringInstances(newInstances)
    }
  }

  func cleanupRecurringInstancesOutsideRange(
    _ monthRange: ClosedRange<Int>, referenceDate: Date, cleanupOption: RecurringCleanupOption
  ) {

    let validAnchors = Set(
      monthRange.compactMap { offset in
        calendar.date(byAdding: .month, value: offset, to: referenceDate)?.monthAnchor
      })

    let allInstances = transactionRepo.fetchAllRecurringInstances()
    let recurringTransactions = transactionRepo.fetchRecurringTransactions()
    let recurringStartAnchors = Dictionary(
      uniqueKeysWithValues: recurringTransactions.map { ($0.id, $0.budgetMonthDate) })

    let currentAnchor = referenceDate.monthAnchor

    for instance in allInstances {
      let shouldDelete: Bool

      switch cleanupOption {
      case .all:
        shouldDelete =
          !validAnchors.contains(instance.budgetMonthDate)
          || (instance.parentTransactionId.map { parentId in
            instance.budgetMonthDate <= (recurringStartAnchors[parentId] ?? 0)
          } ?? false)

      case .futureOnly:
        let isOutsideRange = !validAnchors.contains(instance.budgetMonthDate)
        let isFutureInstance = instance.budgetMonthDate > currentAnchor
        let isBeforeRecurringStart =
          instance.parentTransactionId.map { parentId in
            instance.budgetMonthDate <= (recurringStartAnchors[parentId] ?? 0)
          } ?? false

        shouldDelete = (isOutsideRange && isFutureInstance) || isBeforeRecurringStart
      }

      guard let id = instance.id else { return }

      if shouldDelete {
        do {
          try transactionRepo.delete(id: id)

          // Clean up notification for deleted recurring instance
          let notifID = "transaction_\(id)"
          notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
        } catch {
          print("Error deleting outdated recurring instance: \(error)")
        }
      }
    }
  }

  func cleanupRecurringInstancesWithUserChoice(
    _ monthRange: ClosedRange<Int>,
    referenceDate: Date,
    onCleanupChoiceNeeded: @escaping (RecurringCleanupOption) -> Void
  ) {
    onCleanupChoiceNeeded(.futureOnly)
  }

  func cleanupRecurringInstancesFromDate(
    parentTransactionId: Int,
    selectedTransactionDate: Date,
    cleanupOption: RecurringCleanupOption
  ) {
    let selectedAnchor = selectedTransactionDate.monthAnchor
    let allInstances = transactionRepo.fetchAllRecurringInstances()

    let relatedInstances = allInstances.filter {
      $0.parentTransactionId == parentTransactionId
    }

    for instance in relatedInstances {
      let shouldDelete: Bool

      switch cleanupOption {
      case .all:
        shouldDelete = true
      case .futureOnly:
        shouldDelete = instance.budgetMonthDate >= selectedAnchor
      }

      if shouldDelete, let instanceId = instance.id {
        do {
          try transactionRepo.delete(id: instanceId)

          let notifID = "transaction_\(instanceId)"
          notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
        } catch {
          print("Error deleting recurring instance: \(error)")
        }
      }
    }

    if cleanupOption == .all {
      do {
        try transactionRepo.delete(id: parentTransactionId)

        // Clean up notification for deleted parent transaction
        let notifID = "transaction_\(parentTransactionId)"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
        print(
          "🔔 🗑️ Removed notification for deleted parent recurring transaction: \(parentTransactionId)"
        )
      } catch {
        print("Error deleting parent recurring transaction: \(error)")
      }
    }
  }

  func cleanupInstallmentTransactionsFromDate(
    parentTransactionId: Int,
    selectedTransactionDate: Date,
    cleanupOption: RecurringCleanupOption
  ) {
    let allTransactions = transactionRepo.fetchAllTransactions()
    let installmentInstances = allTransactions.filter {
      $0.parentTransactionId == parentTransactionId
    }

    for instance in installmentInstances {
      let shouldDelete: Bool

      switch cleanupOption {
      case .all:
        shouldDelete = true
      case .futureOnly:
        shouldDelete = instance.date >= selectedTransactionDate
      }

      if shouldDelete, let instanceId = instance.id {
        do {
          try transactionRepo.delete(id: instanceId)

          let notifID = "transaction_\(instanceId)"
          notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
        } catch {
          print("Error deleting installment instance: \(error)")
        }
      }
    }

    if cleanupOption == .all {
      do {
        try transactionRepo.delete(id: parentTransactionId)

        // Clean up notification for deleted parent transaction
        let notifID = "transaction_\(parentTransactionId)"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
        print(
          "🔔 🗑️ Removed notification for deleted parent installment transaction: \(parentTransactionId)"
        )
      } catch {
        print("Error deleting parent installment transaction: \(error)")
      }
    }
  }

  // MARK: - Helper Methods
  
  /// Gera uma data válida para o mês especificado, lidando com dias que não existem
  /// - Parameters:
  ///   - originalDate: Data original da transação recorrente
  ///   - targetMonth: Mês para o qual gerar a data
  ///   - targetYear: Ano para o qual gerar a data
  /// - Returns: Data válida para o mês especificado
  private func generateValidDateForMonth(
    originalDate: Date,
    targetMonth: Int,
    targetYear: Int
  ) -> Date {
    let originalDay = calendar.component(.day, from: originalDate)
    
    print("🔧 generateValidDateForMonth: originalDay=\(originalDay), targetMonth=\(targetMonth), targetYear=\(targetYear)")
    
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
      print("⚠️ Using fallback date (1st day) for month \(targetMonth)/\(targetYear)")
      return fallbackDate
    }
    
    if dayToUse != originalDay {
      print("📅 Adjusted date for month \(targetMonth)/\(targetYear): original day \(originalDay) → adjusted day \(dayToUse)")
    } else {
      print("✅ Original day \(originalDay) works for month \(targetMonth)/\(targetYear)")
    }
    
    return validDate
  }

  // MARK: - Notification Management
  
  /// Sistema otimizado para agendar notificações de transações recorrentes
  private func scheduleOptimizedNotificationsForRecurringInstances(_ instances: [TransactionModel]) {
    print("🔔 🔄 Scheduling optimized notifications for \(instances.count) recurring instances")
    
    // Agrupar instâncias por mês
    var instancesByMonth: [String: [TransactionModel]] = [:]
    
    for instance in instances {
      let date = Date(timeIntervalSince1970: TimeInterval(instance.data.dateTimestamp))
      let monthKey = "\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))"
      
      if instancesByMonth[monthKey] == nil {
        instancesByMonth[monthKey] = []
      }
      instancesByMonth[monthKey]?.append(instance)
    }
    
    print("🔔 📅 Grouped recurring instances into \(instancesByMonth.count) months")
    
    // Agendar notificação para cada mês (máximo 1 por mês)
    for (monthKey, monthInstances) in instancesByMonth {
      scheduleMonthlyRecurringNotification(monthKey: monthKey, instances: monthInstances)
    }
  }
  
  /// Agenda uma notificação mensal para todas as instâncias recorrentes do mês
  private func scheduleMonthlyRecurringNotification(monthKey: String, instances: [TransactionModel]) {
    guard let firstInstance = instances.first else { return }
    
    let date = Date(timeIntervalSince1970: TimeInterval(firstInstance.data.dateTimestamp))
    
    // Verificar se a data é muito no futuro (mais de 1 ano)
    let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    if date > oneYearFromNow {
      print("🔔 ⚠️ Recurring month \(monthKey) is more than 1 year in the future, skipping notification")
      return
    }
    
    // Create notification time (8 AM) in local timezone
    var notificationDate = calendar.startOfDay(for: date)
    notificationDate = calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate
    
    // Only schedule if notification time is in the future
    guard notificationDate > Date() else {
      print("🔔 ⚠️ Recurring notification time is in the past, skipping")
      return
    }
    
    let timeInterval = notificationDate.timeIntervalSinceNow
    
    // Verificar se o intervalo é muito grande (mais de 30 dias)
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    if timeInterval > thirtyDaysInSeconds {
      print("🔔 ⚠️ Recurring month \(monthKey) is more than 30 days away, scheduling reminder")
      scheduleRecurringReminderNotification(for: monthKey, instances: instances)
      return
    }
    
    // Criar notificação mensal consolidada
    let totalAmount = instances.reduce(0) { $0 + $1.data.amount }
    let instanceCount = instances.count
    
    let title = "notification.recurring.title".localized
    let bodyKey = instanceCount == 1 ? "notification.recurring.body.singular" : "notification.recurring.body.plural"
    let body = instanceCount == 1 
      ? String(format: bodyKey.localized, totalAmount.currencyString)
      : String(format: bodyKey.localized, instanceCount, totalAmount.currencyString)
    
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = [
      "type": "recurring_month",
      "monthKey": monthKey,
      "instanceCount": instanceCount,
      "totalAmount": totalAmount
    ]
    
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
    let request = UNNotificationRequest(identifier: "recurring_month_\(monthKey)", content: content, trigger: trigger)
    
    notificationCenter.add(request) { error in
      if let error = error {
        print("🔔 ❌ Error scheduling recurring notification for month \(monthKey): \(error)")
      } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        print("🔔 ✅ Scheduled recurring notification for month \(monthKey) at \(formatter.string(from: notificationDate))")
      }
    }
  }
  
  /// Agenda uma notificação de lembrete para instâncias recorrentes distantes
  private func scheduleRecurringReminderNotification(for monthKey: String, instances: [TransactionModel]) {
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: thirtyDaysInSeconds, repeats: false)
    
    let content = UNMutableNotificationContent()
    content.title = "notification.recurring.reminder.title".localized
    content.body = "notification.recurring.reminder.body".localized
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = ["type": "recurring_reminder", "monthKey": monthKey]
    
    let request = UNNotificationRequest(identifier: "recurring_reminder_\(monthKey)", content: content, trigger: trigger)
    
    notificationCenter.add(request) { error in
      if let error = error {
        print("🔔 ❌ Error scheduling recurring reminder for month \(monthKey): \(error)")
      } else {
        print("🔔 ✅ Scheduled recurring reminder for month \(monthKey)")
      }
    }
  }
}
