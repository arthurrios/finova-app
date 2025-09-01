//
//  TransactionLedgerService.swift
//  FinanceApp
//
//  Created by Arthur Rios on 10/06/25.
//

import Foundation

final class TransactionLedgerService {
  private let transactionRepo: TransactionRepository
  private let budgetRepo: BudgetRepository
  private let calendar = Calendar.current

  // Cache for performance optimization
  private var monthlyDataCache: [Int: MonthBudgetCardType] = [:]
  private var lastCacheUpdate: Date = Date.distantPast
  private let cacheValidityDuration: TimeInterval = 60  // 1 minute

  init(
    transactionRepo: TransactionRepository = TransactionRepository(),
    budgetRepo: BudgetRepository = BudgetRepository()
  ) {
    self.transactionRepo = transactionRepo
    self.budgetRepo = budgetRepo
  }

  // MARK: - Monthly Calculations

  func calculateMonthlyData(for monthRange: ClosedRange<Int>, referenceDate: Date = Date())
    -> [MonthBudgetCardType]
  {
    // Check if cache is still valid
    if Date().timeIntervalSince(lastCacheUpdate) < cacheValidityDuration {
      let cachedData = monthRange.compactMap { monthlyDataCache[$0] }
      if cachedData.count == monthRange.count {
        print("📊 Using cached monthly data")
        return cachedData
      }
    }

    print("🔄 Calculating fresh monthly data for range \(monthRange)")

    let allTransactions = transactionRepo.fetchAllTransactions()
    let budgetsByAnchor = budgetRepo.fetchBudgets()
      .reduce(into: [:]) { acc, entry in
        acc[entry.monthDate] = entry.amount
      }

    var anchors: [Int] = []
    let currentComponents = calendar.dateComponents([.year, .month], from: referenceDate)
    let currentYear = currentComponents.year!
    let currentMonth = currentComponents.month!

    // Generate month anchors
    for offset in monthRange {
      let targetMonth = currentMonth + offset
      let targetYear = currentYear + (targetMonth - 1) / 12
      let normalizedMonth = ((targetMonth - 1) % 12) + 1

      var components = DateComponents()
      components.year = targetYear
      components.month = normalizedMonth
      components.day = 1
      components.hour = 0
      components.minute = 0
      components.second = 0

      let monthDate = calendar.date(from: components)!
      let anchor = monthDate.monthAnchor
      anchors.append(anchor)
    }

    // Calculate running balance
    var runningBalance = [Int: Int]()
    var previousAvailable = 0

    let monthlyData = anchors.map { anchor in
      let date = Date(timeIntervalSince1970: TimeInterval(anchor))
      let month = DateFormatter.monthFormatter.string(from: date)
      let localizedMonth = "month.\(month.lowercased())".localized

      let transactionsForMonth = allTransactions.filter { $0.budgetMonthDate == anchor }
      let expense = transactionsForMonth.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
      let income = transactionsForMonth.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
      let budgetLimit = budgetsByAnchor[anchor]

      let net = income - expense
      let available = previousAvailable + net
      previousAvailable = available
      runningBalance[anchor] = available

      let monthData = MonthBudgetCardType(
        date: date,
        month: localizedMonth,
        usedValue: expense,
        budgetLimit: budgetLimit,
        finalBalance: available,
        currentBalance: available,
        previousBalance: available - net
      )

      // Cache the result
      monthlyDataCache[anchor] = monthData

      return monthData
    }

    lastCacheUpdate = Date()
    print("✅ Generated monthly data for \(monthlyData.count) months")

    return monthlyData
  }

  // MARK: - Transaction Filtering

  func getTransactionsForMonth(_ monthAnchor: Int) -> [Transaction] {
    let allTransactions = transactionRepo.fetchAllTransactions()
    return
      allTransactions
      .filter { $0.budgetMonthDate == monthAnchor }
      .sorted { $0.date > $1.date }
  }

  func getTransactionsForDateRange(from startDate: Date, to endDate: Date) -> [Transaction] {
    let allTransactions = transactionRepo.fetchAllTransactions()
    let startAnchor = startDate.monthAnchor
    let endAnchor = endDate.monthAnchor

    return
      allTransactions
      .filter { $0.budgetMonthDate >= startAnchor && $0.budgetMonthDate <= endAnchor }
      .sorted { $0.date > $1.date }
  }

  // MARK: - Balance Calculations

  func calculateCurrentBalance(for monthAnchor: Int) -> Int {
    let allTransactions = transactionRepo.fetchAllTransactions()
    let today = Date()
    let monthDate = Date(timeIntervalSince1970: TimeInterval(monthAnchor))

    // Get all transactions up to the current month
    let relevantTransactions = allTransactions.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      return transaction.budgetMonthDate <= monthAnchor
    }

    // Calculate running balance
    var balance = 0
    for transaction in relevantTransactions.sorted(by: { $0.date < $1.date }) {
      if transaction.type == .income {
        balance += transaction.amount
      } else {
        balance -= transaction.amount
      }
    }

    return balance
  }

  func calculateRunningBalance(for monthRange: ClosedRange<Int>, referenceDate: Date = Date())
    -> [Int: Int]
  {
    let monthlyData = calculateMonthlyData(for: monthRange, referenceDate: referenceDate)
    return monthlyData.reduce(into: [:]) { result, monthData in
      let anchor = monthData.date.monthAnchor
      result[anchor] = monthData.finalBalance
    }
  }

  // MARK: - Cache Management

  func invalidateCache() {
    monthlyDataCache.removeAll()
    lastCacheUpdate = Date.distantPast
    print("🗑️ Transaction ledger cache invalidated")
  }

  func clearCache() {
    monthlyDataCache.removeAll()
    lastCacheUpdate = Date.distantPast
    print("🗑️ Transaction ledger cache cleared")
  }

  // MARK: - Data Cleanup

  /// Clean up any duplicate transactions that might exist from before the fix
  func cleanupDuplicateTransactions() {
    let allTransactions = transactionRepo.fetchAllTransactions()
    let transactionsByMonth = Dictionary(grouping: allTransactions) { $0.budgetMonthDate }

    print("🧹 Cleaning up duplicate transactions...")

    for (monthAnchor, transactions) in transactionsByMonth {
      if transactions.count > 1 {
        let date = Date(timeIntervalSince1970: TimeInterval(monthAnchor))
        print(
          "⚠️ Month \(date): Found \(transactions.count) transactions, checking for duplicates...")

        // Find parent recurring transactions and their instances for the same month
        let parentRecurring = transactions.filter {
          $0.isRecurring == true && $0.parentTransactionId == nil
        }
        let instances = transactions.filter { $0.parentTransactionId != nil }

        for parent in parentRecurring {
          // Find instances for this parent in the same month
          let duplicateInstances = instances.filter {
            $0.parentTransactionId == parent.id && $0.budgetMonthDate == monthAnchor
          }

          if !duplicateInstances.isEmpty {
            print(
              "🗑️ Found \(duplicateInstances.count) duplicate instances for parent '\(parent.title)' in month \(date)"
            )

            // Delete the duplicate instances (keep the parent)
            for instance in duplicateInstances {
              if let instanceId = instance.id {
                do {
                  try transactionRepo.delete(id: instanceId)
                  print("✅ Deleted duplicate instance: \(instance.title) (ID: \(instanceId))")
                } catch {
                  print("❌ Failed to delete duplicate instance: \(error)")
                }
              }
            }
          }
        }
      }
    }

    print("🧹 Duplicate transaction cleanup completed")
  }
}
