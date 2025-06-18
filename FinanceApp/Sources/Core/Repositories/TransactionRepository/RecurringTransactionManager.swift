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
  private let calendar = Calendar.current
  private let notificationCenter = UNUserNotificationCenter.current()

  init(transactionRepo: TransactionRepository = TransactionRepository()) {
    self.transactionRepo = transactionRepo
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

    let existingInstances = transactionRepo.fetchTransactionInstancesForRecurring(recurringTxId)
    let existingAnchors = Set(existingInstances.map { $0.budgetMonthDate })
    let recurringStartAnchor = recurringTx.budgetMonthDate

    for monthOffset in monthRange {
      guard let targetDate = calendar.date(byAdding: .month, value: monthOffset, to: referenceDate)
      else { continue }

      let targetAnchor = targetDate.monthAnchor

      if existingAnchors.contains(targetAnchor) { continue }

      let effectiveStartAnchor: Int
      if let startDate = transactionStartDate {
        effectiveStartAnchor = startDate.monthAnchor
      } else {
        effectiveStartAnchor = recurringStartAnchor
      }

      if targetAnchor >= effectiveStartAnchor {
        let originalDate = Date(timeIntervalSince1970: TimeInterval(recurringTx.dateTimestamp))
        let originalDay = calendar.component(.day, from: originalDate)

        var targetDateComponents = calendar.dateComponents([.year, .month], from: targetDate)
        targetDateComponents.day = originalDay

        // Handle month-end dates properly (e.g., Jan 31 → Feb 28/29)
        var instanceDate: Date
        if let attemptedDate = calendar.date(from: targetDateComponents) {
          instanceDate = attemptedDate
        } else {
          // If the day doesn't exist in the target month, use the last day of that month
          let daysInTargetMonth = calendar.range(of: .day, in: .month, for: targetDate)?.count ?? 28
          targetDateComponents.day = min(originalDay, daysInTargetMonth)
          instanceDate = calendar.date(from: targetDateComponents) ?? targetDate
        }

        let instanceModel = TransactionModel(
          title: recurringTx.title,
          category: recurringTx.category.key,
          amount: recurringTx.amount,
          type: recurringTx.type.key,
          dateTimestamp: Int(instanceDate.timeIntervalSince1970),
          budgetMonthDate: targetAnchor,
          parentTransactionId: recurringTxId
        )

        do {
          try transactionRepo.insertTransaction(instanceModel)
        } catch {
          print("Error creating recurring transaction instance: \(error)")
        }
      }
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
      } catch {
        print("Error deleting parent installment transaction: \(error)")
      }
    }
  }
}
