//
//  AddTransactionModalViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/05/25.
//

import Foundation

final class AddTransactionModalViewModel {
  private let transactionRepo: TransactionRepository
  private let recurringManager: RecurringTransactionManager
  private let carouselRange: ClosedRange<Int> = -12...24
  private var calendar: Calendar = {
    var cal = Calendar.current
    cal.timeZone = TimeZone.current  // Ensure we use local timezone
    return cal
  }()
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
    creditCardId: Int? = nil,
    businessDayRule: BusinessDayRule = .exact
  ) -> Result<Void, Error> {

    guard let date = DateFormatter.fullDateFormatter.date(from: dateString) else {
      return .failure(TransactionError.invalidDateFormat)
    }

    // `date` is the canonical value the user picked; `effectiveDate` is it passed through the rule.
    // The month anchor below is always derived from `date`, never from `effectiveDate`, so a shift
    // across a month boundary still counts in the month the user chose.
    let effectiveDate = BusinessDayAdjuster.adjust(
      date, rule: businessDayRule, calendar: calendar)
    let timestamp = Int(effectiveDate.timeIntervalSince1970)

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

    // A series counts in the month it is scheduled for (one occurrence per month); a one-off counts
    // in the month it actually lands, where there is no such invariant to protect.
    let anchor = (isRecurring == true) ? date.monthAnchor : effectiveDate.monthAnchor

    if let isRecurring = isRecurring, isRecurring {

      let model = TransactionModel(
        title: title,
        category: category.key,
        amount: amount,
        type: type.key,
        dateTimestamp: timestamp,
        budgetMonthDate: anchor,
        isRecurring: true,
        businessDayRule: businessDayRule,
        unadjustedDateTimestamp: Int(date.timeIntervalSince1970),
        seriesPeriod: date.monthAnchor
      )

      do {
        let insertedId = try transactionRepo.insertTransactionAndGetId(model)

        // Pre-generate CK record name so the notification includes it
        let ckRecordName = "transaction-\(UUID().uuidString)"
        transactionRepo.setCKRecordId(for: insertedId, ckRecordName: ckRecordName)

        // Assign to group if in group context
        logWarning("CREATE (recurring): activeContext=\(activeContext), groupId=\(activeContext.groupId ?? "nil")")
        if let groupId = activeContext.groupId {
          transactionRepo.updateSharedGroupId(transactionId: insertedId, groupId: groupId)
          GroupNotificationService.shared.logActivity(
            action: .transactionCreated, groupId: groupId, detail: title,
            targetRecordName: ckRecordName)
          SyncEngine.shared.pushPendingChangesNow()
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

        // UPFRONT GENERATION: eagerly generate the full recurring horizon so every occurrence
        // exists as a real, syncable row at creation time (see RecurringTransactionManager.horizonMonths).
        let immediateMonthAnchors: Set<Int> = {
          var anchors = Set<Int>()
          for monthOffset in 1...RecurringTransactionManager.horizonMonths {
            if let futureDate = calendar.date(byAdding: .month, value: monthOffset, to: date) {
              anchors.insert(futureDate.monthAnchor)
            }
          }
          return anchors
        }()

        // Generate the full horizon, then push immediately so sync happens right after creation
        // (not on a later navigation). Completion runs on background queue - heavy work stays there.
        recurringManager.generateInstancesLazilyForMonths(immediateMonthAnchors) { [weak self] created in
          guard let self = self else { return }
          logWarning("[RecurringCreate] upfront generation produced \(created) future instance(s) for '\(title)'")
          DispatchQueue.main.async {
            self.invalidateLedgerCache()
            SyncEngine.shared.pushPendingChangesNow()
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
        creditCardId: creditCardId,
        businessDayRule: businessDayRule,
        unadjustedDateTimestamp: Int(date.timeIntervalSince1970),
        seriesPeriod: date.monthAnchor
      )

      do {
        let insertedId = try transactionRepo.insertTransactionAndGetId(model)

        // Pre-generate CK record name so the notification includes it
        let ckRecordName = "transaction-\(UUID().uuidString)"
        transactionRepo.setCKRecordId(for: insertedId, ckRecordName: ckRecordName)

        // Assign to group if in group context
        logWarning("CREATE: activeContext=\(activeContext), groupId=\(activeContext.groupId ?? "nil")")
        if let groupId = activeContext.groupId {
          transactionRepo.updateSharedGroupId(transactionId: insertedId, groupId: groupId)
          GroupNotificationService.shared.logActivity(
            action: .transactionCreated, groupId: groupId, detail: title,
            targetRecordName: ckRecordName)
          SyncEngine.shared.pushPendingChangesNow()
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
        TransactionNotificationManager.shared.scheduleNotification(transactionId: insertedId, model: model)

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
    businessDayRule: BusinessDayRule = .exact,
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

    // Anchor from the picked date, timestamp from the adjusted one - see `addTransaction`.
    let effectiveDate = BusinessDayAdjuster.adjust(date, rule: businessDayRule, calendar: calendar)
    let timestamp = Int(effectiveDate.timeIntervalSince1970)
    let anchor = effectiveDate.monthAnchor

    let model = TransactionModel(
      title: title,
      category: category.key,
      amount: amount,
      type: type.key,
      dateTimestamp: timestamp,
      budgetMonthDate: anchor,
      isRecurring: true,
      creditCardId: creditCardId,
      businessDayRule: businessDayRule,
      unadjustedDateTimestamp: Int(date.timeIntervalSince1970),
      seriesPeriod: date.monthAnchor
    )

    do {
      let insertedId = try transactionRepo.insertTransactionAndGetId(model)

      // Pre-generate CK record name so the notification includes it
      let ckRecordName = "transaction-\(UUID().uuidString)"
      transactionRepo.setCKRecordId(for: insertedId, ckRecordName: ckRecordName)

      // Assign to group if in group context or mirror mode
      logWarning("CREATE (recurringAsync): activeContext=\(self.activeContext), groupId=\(self.activeContext.groupId ?? "nil")")
      if let groupId = self.activeContext.groupId {
        self.transactionRepo.updateSharedGroupId(transactionId: insertedId, groupId: groupId)
        GroupNotificationService.shared.logActivity(
          action: .transactionCreated, groupId: groupId, detail: title,
          targetRecordName: ckRecordName)
        SyncEngine.shared.pushPendingChangesNow()
      }

      // Check for similar existing recurring transactions
      if let existingSimilar = recurringManager.findSimilarRecurringTransaction(
        title: title,
        category: category.key,
        amount: amount,
        type: type.key
      ), let existingId = existingSimilar.id {
        logWarning("[RecurringCreate] '\(title)' LINKED to existing series parent=\(existingId) (not a new series) — future months belong to that series")
        try recurringManager.linkToExistingRecurringTransaction(
          newTransactionId: insertedId,
          existingParentId: existingId
        )
      } else {
        logWarning("[RecurringCreate] '\(title)' created as NEW series parent=\(insertedId)")
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

      // UPFRONT GENERATION: eagerly generate the full recurring horizon so every occurrence
      // exists as a real, syncable row at creation time (see RecurringTransactionManager.horizonMonths).
      let immediateMonthAnchors: Set<Int> = {
        var anchors = Set<Int>()
        for monthOffset in 1...RecurringTransactionManager.horizonMonths {
          if let futureDate = calendar.date(byAdding: .month, value: monthOffset, to: date) {
            anchors.insert(futureDate.monthAnchor)
          }
        }
        return anchors
      }()

      // Wait for instance generation to complete before calling completion, then push
      // immediately so sync happens right after creation (not on a later navigation).
      recurringManager.generateInstancesLazilyForMonths(immediateMonthAnchors) { [weak self] created in
        // `created` is APP-WIDE (all recurring parents this pass). Log THIS series' actual
        // materialized months so a shortfall (e.g. dedup skipping months that already have a
        // same-title row from earlier testing) is unambiguous.
        let seriesMonths = self?.transactionRepo
          .fetchTransactionInstancesForRecurring(insertedId)
          .map { $0.budgetMonthDate }.sorted() ?? []
        logWarning("[RecurringCreate] '\(title)' parent=\(insertedId): this series now spans \(seriesMonths.count) month(s); app-wide new this pass=\(created)")
        // If the series is empty, dump the same-title rows blocking generation + their group tag,
        // so we can tell whether context-blind dedup (personal rows blocking a group series) is the cause.
        if seriesMonths.count <= 1, let repo = self?.transactionRepo {
          let sameTitle = repo.fetchAllTransactions().filter { $0.title == title }
          logWarning("[RecurringDiag] \(sameTitle.count) existing active '\(title)' row(s) blocking generation:")
          for t in sameTitle.prefix(45) {
            let gid = t.id.flatMap { repo.fetchSharedGroupId(for: $0) } ?? "nil"
            logWarning("[RecurringDiag]   id=\(t.id ?? -1) month=\(t.budgetMonthDate) parent=\(t.parentTransactionId ?? -1) recurring=\(t.isRecurring ?? false) group=\(gid)")
          }
        }
        guard let self = self else {
          DispatchQueue.main.async {
            SyncEngine.shared.pushPendingChangesNow()
            completion(.success(()))
          }
          return
        }

        // These operations run on background thread
        // Notification scheduling is handled by RecurringTransactionManager via RecurringNotificationManager

        // Invalidate cache and call completion on main thread
        DispatchQueue.main.async {
          self.invalidateLedgerCache()
          SyncEngine.shared.pushPendingChangesNow()
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

      // Pre-generate CK record name so the notification includes it
      let ckRecordName = "transaction-\(UUID().uuidString)"
      transactionRepo.setCKRecordId(for: parentId, ckRecordName: ckRecordName)

      // Assign parent to group if in group context or mirror mode
      let groupId: String? = activeContext.groupId
      if let groupId = groupId {
        transactionRepo.updateSharedGroupId(transactionId: parentId, groupId: groupId)
        GroupNotificationService.shared.logActivity(
          action: .transactionCreated, groupId: groupId, detail: data.title,
          targetRecordName: ckRecordName)
        SyncEngine.shared.pushPendingChangesNow()
      }

      // UPFRONT GENERATION: Create ALL installments at once for cloud sync consistency
      let immediateInstallmentCount = totalInstallments

      var allInstallments: [TransactionModel] = []
      // Track the previous installment's statement so installment N+1 lands in the
      // billing cycle right after N, regardless of date-based routing rules.
      var previousStatement: CreditCardStatement? = nil

      for installmentNumber in 1...immediateInstallmentCount {
        // Calcular a data da parcela usando a função de geração de datas válidas
        let targetDate =
          calendar.date(byAdding: .month, value: installmentNumber - 1, to: startDate) ?? startDate
        let targetYear = calendar.component(.year, from: targetDate)
        let targetMonth = calendar.component(.month, from: targetDate)

        let installment = OccurrenceDateCalculator.occurrencePair(
          from: startDate,
          targetMonth: targetMonth,
          targetYear: targetYear,
          rule: data.businessDayRule,
          calendar: calendar
        )

        let installmentAmount =
          installmentNumber == 1 ? amountPerInstallment + remainder : amountPerInstallment

        let installmentModel = TransactionModel(
          title: data.title,
          category: category.key,
          amount: installmentAmount,
          type: type.key,
          dateTimestamp: Int(installment.adjusted.timeIntervalSince1970),
          budgetMonthDate: installment.unadjusted.monthAnchor,
          parentTransactionId: parentId,
          originalAmount: data.totalAmount,
          installmentNumber: installmentNumber,
          totalInstallments: totalInstallments,
          businessDayRule: data.businessDayRule,
          unadjustedDateTimestamp: Int(installment.unadjusted.timeIntervalSince1970),
          seriesPeriod: installment.unadjusted.monthAnchor
        )

        let installmentId = try transactionRepo.insertTransactionAndGetId(installmentModel)

        // Assign installment to group
        if let groupId = groupId {
          transactionRepo.updateSharedGroupId(transactionId: installmentId, groupId: groupId)
        }

        // Assign installment to correct credit card statement + remap date to due date
        if let cardId = data.creditCardId, let card = creditCardRepo.fetchCard(byId: cardId) {
          if let uid = AuthenticationManager.shared.currentUser?.uid {
            let statement: CreditCardStatement?
            if let prev = previousStatement {
              statement = creditCardService.nextStatement(after: prev, for: card, userId: uid)
            } else {
              statement = creditCardService.getOrCreateStatement(for: card, transactionDate: installment.unadjusted, userId: uid)
            }
            if let statement = statement {
              try transactionRepo.updateCreditCardFields(
                transactionId: installmentId,
                creditCardId: cardId,
                statementId: statement.id!,
                isCreditCardStatement: false
              )
              creditCardService.recalculateStatementTotal(statementId: statement.id!)

              // Remap installment date to statement due date
              let dueDateTimestamp = Int(statement.dueDate.timeIntervalSince1970)
              let dueDateBudgetMonth = statement.dueDate.monthAnchor
              transactionRepo.updateDateAndBudgetMonth(
                transactionId: installmentId,
                newDateTimestamp: dueDateTimestamp,
                newBudgetMonthDate: dueDateBudgetMonth
              )

              previousStatement = statement
            }
          }
        }

        // Adicionar à lista para notificações otimizadas
        allInstallments.append(installmentModel)
      }

      // Agendar notificações otimizadas para as parcelas criadas
      InstallmentNotificationManager.shared.scheduleNotifications(for: allInstallments)

      // Invalidate ledger cache since transactions changed
      invalidateLedgerCache()

      // Push immediately so sync happens right after creation (all installments are eager).
      SyncEngine.shared.pushPendingChangesNow()

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

        // Pre-generate CK record name so the notification includes it
        let ckRecordName = "transaction-\(UUID().uuidString)"
        self.transactionRepo.setCKRecordId(for: parentId, ckRecordName: ckRecordName)

        // Assign parent to group if in group context or mirror mode
        let groupId: String? = self.activeContext.groupId
        if let groupId = groupId {
          self.transactionRepo.updateSharedGroupId(transactionId: parentId, groupId: groupId)
          GroupNotificationService.shared.logActivity(
            action: .transactionCreated, groupId: groupId, detail: data.title,
            targetRecordName: ckRecordName)
        }

        // UPFRONT GENERATION: Create ALL installments at once for cloud sync consistency
        let immediateInstallmentCount = totalInstallments
        var allInstallments: [TransactionModel] = []
        // Track previous installment's statement so each installment lands in the
        // billing cycle right after the previous one (consecutive cycles).
        var previousStatement: CreditCardStatement? = nil

        for installmentNumber in 1...immediateInstallmentCount {
          let targetDate =
            self.calendar.date(byAdding: .month, value: installmentNumber - 1, to: startDate)
            ?? startDate
          let targetYear = self.calendar.component(.year, from: targetDate)
          let targetMonth = self.calendar.component(.month, from: targetDate)

          let installment = OccurrenceDateCalculator.occurrencePair(
            from: startDate,
            targetMonth: targetMonth,
            targetYear: targetYear,
            rule: data.businessDayRule,
            calendar: self.calendar
          )

          let installmentAmount =
            installmentNumber == 1 ? amountPerInstallment + remainder : amountPerInstallment

          let installmentModel = TransactionModel(
            title: data.title,
            category: category.key,
            amount: installmentAmount,
            type: type.key,
            dateTimestamp: Int(installment.adjusted.timeIntervalSince1970),
            budgetMonthDate: installment.unadjusted.monthAnchor,
            parentTransactionId: parentId,
            originalAmount: data.totalAmount,
            installmentNumber: installmentNumber,
            totalInstallments: totalInstallments,
            businessDayRule: data.businessDayRule,
            unadjustedDateTimestamp: Int(installment.unadjusted.timeIntervalSince1970),
            seriesPeriod: installment.unadjusted.monthAnchor
          )

          let insertedInstallmentId = try self.transactionRepo.insertTransactionAndGetId(installmentModel)
          allInstallments.append(installmentModel)

          // Assign installment to group
          if let groupId = groupId {
            self.transactionRepo.updateSharedGroupId(transactionId: insertedInstallmentId, groupId: groupId)
          }

          // Assign installment to correct credit card statement + remap date to due date
          if let cardId = data.creditCardId, let card = self.creditCardRepo.fetchCard(byId: cardId) {
            guard let uid = AuthenticationManager.shared.currentUser?.uid else { break }
            let statement: CreditCardStatement?
            if let prev = previousStatement {
              statement = self.creditCardService.nextStatement(after: prev, for: card, userId: uid)
            } else {
              statement = self.creditCardService.getOrCreateStatement(for: card, transactionDate: installment.unadjusted, userId: uid)
            }
            if let statement = statement {
              try self.transactionRepo.updateCreditCardFields(
                transactionId: insertedInstallmentId,
                creditCardId: cardId,
                statementId: statement.id!,
                isCreditCardStatement: false
              )
              self.creditCardService.recalculateStatementTotal(statementId: statement.id!)

              // Remap installment date to statement due date
              let dueDateTimestamp = Int(statement.dueDate.timeIntervalSince1970)
              let dueDateBudgetMonth = statement.dueDate.monthAnchor
              self.transactionRepo.updateDateAndBudgetMonth(
                transactionId: insertedInstallmentId,
                newDateTimestamp: dueDateTimestamp,
                newBudgetMonthDate: dueDateBudgetMonth
              )

              previousStatement = statement
            }
          }
        }

        // Schedule notifications
        InstallmentNotificationManager.shared.scheduleNotifications(for: allInstallments)

        DispatchQueue.main.async {
          self.invalidateLedgerCache()
          // Push immediately so sync happens right after creation (all installments are eager).
          SyncEngine.shared.pushPendingChangesNow()
          completion(.success(()))
        }

      } catch {
        DispatchQueue.main.async {
          completion(.failure(error))
        }
      }
    }
  }

  // MARK: - Helper Methods

  // Occurrence dates come from `OccurrenceDateCalculator`, which this file used to duplicate.

  // MARK: - Update Transaction Methods

  func updateTransaction(
    id: Int,
    title: String,
    amount: Int,
    dateString: String,
    categoryKey: String,
    typeRaw: String,
    isRecurring: Bool = false,
    creditCardId: Int? = nil,
    businessDayRule: BusinessDayRule = .exact
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

      let effectiveDate = BusinessDayAdjuster.adjust(
        dateObj, rule: businessDayRule, calendar: calendar)

      let updatedTransaction = TransactionModel(
        id: id,
        title: title,
        category: transactionCategory.key,
        amount: amount,
        type: String(describing: transactionType),
        dateTimestamp: Int(effectiveDate.timeIntervalSince1970),
        budgetMonthDate: isRecurring ? dateObj.monthAnchor : effectiveDate.monthAnchor,
        isRecurring: isRecurring,
        hasInstallments: false,
        parentTransactionId: nil,
        originalAmount: amount,
        installmentNumber: nil,
        totalInstallments: nil,
        creditCardId: newCreditCardId,
        statementId: newStatementId,
        isCreditCardStatement: newCreditCardId != nil ? false : nil,
        businessDayRule: businessDayRule,
        unadjustedDateTimestamp: Int(dateObj.timeIntervalSince1970),
        seriesPeriod: dateObj.monthAnchor
      )

      // Carries the business-day columns itself; a second write here would leave the row stuck
      // `pending` (see the note in `DBHelper.updateTransaction`).
      try transactionRepo.updateTransaction(updatedTransaction)

      // Log group activity if transaction belongs to a group (or mirror mode)
      let fetchedGroupId = transactionRepo.fetchSharedGroupId(for: id)
      logWarning("EDIT: fetchSharedGroupId=\(fetchedGroupId ?? "nil"), activeContext=\(activeContext)")
      let editGroupId = fetchedGroupId
      if let groupId = editGroupId {
        let ckRecordName = transactionRepo.fetchCKRecordName(for: id)
        GroupNotificationService.shared.logActivity(
          action: .transactionEdited, groupId: groupId, detail: title,
          targetRecordName: ckRecordName)
        SyncEngine.shared.pushPendingChangesNow()
      }

      // Recalculate old statement if transaction moved away from it
      if let oldStmtId = originalStatementId, oldStmtId != newStatementId {
        creditCardService.recalculateStatementTotal(statementId: oldStmtId)
      }

      // Recalculate new statement
      if let newStmtId = newStatementId {
        creditCardService.recalculateStatementTotal(statementId: newStmtId)
      }

      // Push CC statement changes to cloud (even for personal transactions)
      if newCreditCardId != nil || originalCreditCardId != nil {
        SyncEngine.shared.pushPendingChangesNow()
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
        isCreditCardStatement: data.creditCardId != nil ? false : nil,
        // This model IS the template `updateAllInstallmentTransactions` rebuilds every child from,
        // so the rule has to be on it or the rebuilt series comes back `.exact`.
        businessDayRule: data.businessDayRule,
        unadjustedDateTimestamp: Int(dateObj.timeIntervalSince1970),
        seriesPeriod: dateObj.monthAnchor
      )

      do {
        try transactionRepo.updateTransaction(updatedTransaction)

        // Log group activity if transaction belongs to a group (or mirror mode)
        let txId = mainInstallmentTransaction.id ?? id
        let installEditGroupId = transactionRepo.fetchSharedGroupId(for: txId)
        if let groupId = installEditGroupId {
          let ckRecordName = transactionRepo.fetchCKRecordName(for: txId)
          GroupNotificationService.shared.logActivity(
            action: .transactionEdited, groupId: groupId, detail: data.title,
            targetRecordName: ckRecordName)
        }

        // Push CC statement changes to cloud (even for personal transactions)
        if data.creditCardId != nil {
          SyncEngine.shared.pushPendingChangesNow()
        }

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
    creditCardId: Int? = nil,
    businessDayRule: BusinessDayRule = .exact
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
        date: BusinessDayAdjuster.adjust(dateObj, rule: businessDayRule, calendar: calendar)
      )
      DBHelper.shared.setBusinessDayRule(
        transactionId: id, rule: businessDayRule,
        unadjustedDateTimestamp: Int(dateObj.timeIntervalSince1970))

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

      // Log group activity if transaction belongs to a group (or mirror mode)
      let singleEditGroupId = transactionRepo.fetchSharedGroupId(for: id)
      if let groupId = singleEditGroupId {
        let ckRecordName = transactionRepo.fetchCKRecordName(for: id)
        GroupNotificationService.shared.logActivity(
          action: .transactionEdited, groupId: groupId, detail: title,
          targetRecordName: ckRecordName)
      }

      // Push CC statement changes to cloud (even for personal transactions)
      if creditCardId != nil || originalCreditCardId != nil {
        SyncEngine.shared.pushPendingChangesNow()
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

      // Re-assign CC statement and remap date to due date for CC installments
      if let cardId = data.creditCardId, let card = creditCardRepo.fetchCard(byId: cardId) {
        if let uid = AuthenticationManager.shared.currentUser?.uid,
           let statement = creditCardService.getOrCreateStatement(for: card, transactionDate: dateObj, userId: uid) {
          try transactionRepo.updateCreditCardFields(
            transactionId: id,
            creditCardId: cardId,
            statementId: statement.id!,
            isCreditCardStatement: false
          )
          creditCardService.recalculateStatementTotal(statementId: statement.id!)

          let dueDateTimestamp = Int(statement.dueDate.timeIntervalSince1970)
          let dueDateBudgetMonth = statement.dueDate.monthAnchor
          transactionRepo.updateDateAndBudgetMonth(
            transactionId: id,
            newDateTimestamp: dueDateTimestamp,
            newBudgetMonthDate: dueDateBudgetMonth
          )
        }
      }

      // Log group activity if transaction belongs to a group (or mirror mode)
      let singleInstallEditGroupId = transactionRepo.fetchSharedGroupId(for: id)
      if let groupId = singleInstallEditGroupId {
        let ckRecordName = transactionRepo.fetchCKRecordName(for: id)
        GroupNotificationService.shared.logActivity(
          action: .transactionEdited, groupId: groupId, detail: data.title,
          targetRecordName: ckRecordName)
      }

      // Push CC statement changes to cloud (even for personal transactions)
      if data.creditCardId != nil {
        SyncEngine.shared.pushPendingChangesNow()
      }

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
    editOption: RecurringEditOption,
    businessDayRule: BusinessDayRule = .exact
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
        totalInstallments: nil,
        businessDayRule: businessDayRule,
        unadjustedDateTimestamp: Int(dateObj.timeIntervalSince1970),
        seriesPeriod: dateObj.monthAnchor
      )

      // Use the recurring transaction manager to handle the edit with the specified option
      try recurringManager.editRecurringTransactionsFromDate(
        parentTransactionId: parentTransactionId,
        selectedTransactionDate: dateObj,
        editOption: editOption,
        newData: newTransactionData
      )

      // Log group activity if transaction belongs to a group (or mirror mode)
      let recurEditGroupId = transactionRepo.fetchSharedGroupId(for: id)
      if let groupId = recurEditGroupId {
        let ckRecordName = transactionRepo.fetchCKRecordName(for: id)
        GroupNotificationService.shared.logActivity(
          action: .transactionEdited, groupId: groupId, detail: title,
          targetRecordName: ckRecordName)
      }

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
    businessDayRule: BusinessDayRule = .exact,
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
        creditCardId: creditCardId,
        businessDayRule: businessDayRule,
        unadjustedDateTimestamp: Int(dateObj.timeIntervalSince1970),
        seriesPeriod: dateObj.monthAnchor
      )

      // Use async editing method
      self.recurringManager.editRecurringTransactionsFromDateAsync(
        parentTransactionId: parentTransactionId,
        selectedTransactionDate: dateObj,
        editOption: editOption,
        newData: newTransactionData
      ) { [weak self] result in
        if case .success = result {
          // Log group activity if transaction belongs to a group (or mirror mode)
          let asyncRecurEditGroupId = self?.transactionRepo.fetchSharedGroupId(for: id)
          if let groupId = asyncRecurEditGroupId {
            let ckRecordName = self?.transactionRepo.fetchCKRecordName(for: id)
            GroupNotificationService.shared.logActivity(
              action: .transactionEdited, groupId: groupId, detail: title,
              targetRecordName: ckRecordName)
            SyncEngine.shared.pushPendingChangesNow()
          }
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
