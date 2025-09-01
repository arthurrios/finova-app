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

      // Calculate current balance (balance up to current date within the month)
      let currentBalance = calculateCurrentBalanceForMonth(
        anchor: anchor, previousBalance: previousAvailable)

      let monthData = MonthBudgetCardType(
        date: date,
        month: localizedMonth,
        usedValue: expense,
        budgetLimit: budgetLimit,
        finalBalance: available,
        currentBalance: currentBalance,
        previousBalance: previousAvailable
      )

      // Cache the result
      monthlyDataCache[anchor] = monthData

      // Update for next iteration
      previousAvailable = available
      runningBalance[anchor] = available

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

  /// Calculate the balance up to the current date within a specific month
  func calculateCurrentBalanceForMonth(anchor: Int, previousBalance: Int) -> Int {
    let allTransactions = transactionRepo.fetchAllTransactions()
    let today = Date()
    let monthDate = Date(timeIntervalSince1970: TimeInterval(anchor))

    // Check if this is the current month
    let calendar = Calendar.current
    let isCurrentMonth = calendar.isDate(monthDate, equalTo: today, toGranularity: .month)

    if !isCurrentMonth {
      // For past/future months, return the final balance (end-of-month)
      return previousBalance
    }

    // For current month, calculate balance up to today
    let transactionsInMonth = allTransactions.filter { $0.budgetMonthDate == anchor }
    let transactionsUpToToday = transactionsInMonth.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      return transactionDate <= today
    }

    // Calculate net change from transactions up to today
    let netUpToToday = transactionsUpToToday.reduce(0) { result, transaction in
      transaction.type == .income ? result + transaction.amount : result - transaction.amount
    }

    // Current balance = previous month's balance + net change up to today
    let currentBalance = previousBalance + netUpToToday

    print(
      "📊 Current month balance calculation: previous=\(previousBalance), netUpToToday=\(netUpToToday), current=\(currentBalance)"
    )

    return currentBalance
  }

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

  /// Get the current balance for a specific month (up to current date if it's the current month)
  func getCurrentBalance(for monthAnchor: Int) -> Int? {
    let monthlyData = calculateMonthlyData(for: monthAnchor...monthAnchor)
    return monthlyData.first?.currentBalance
  }

  /// Get the final balance for a specific month (end-of-month balance)
  func getFinalBalance(for monthAnchor: Int) -> Int? {
    let monthlyData = calculateMonthlyData(for: monthAnchor...monthAnchor)
    return monthlyData.first?.finalBalance
  }

  /// Refresh the current balance for the current month (useful after transaction changes)
  func refreshCurrentMonthBalance() {
    let today = Date()
    let currentMonthAnchor = today.monthAnchor

    // Invalidate cache for current month only
    monthlyDataCache.removeValue(forKey: currentMonthAnchor)

    print("🔄 Refreshed current month balance cache for anchor: \(currentMonthAnchor)")
  }

  // MARK: - Cache Management

  func invalidateCache() {
    monthlyDataCache.removeAll()
    lastCacheUpdate = Date.distantPast
    print("🗑️ Transaction ledger cache invalidated")
  }

  /// Invalidate cache for specific month (useful for targeted updates)
  func invalidateCacheForMonth(_ monthAnchor: Int) {
    monthlyDataCache.removeValue(forKey: monthAnchor)
    print("🗑️ Transaction ledger cache invalidated for month anchor: \(monthAnchor)")
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

    print("🧹 Cleaning up duplicate transactions...")

    // Group transactions by month for easier processing
    let transactionsByMonth = Dictionary(grouping: allTransactions) { $0.budgetMonthDate }

    var totalDuplicatesRemoved = 0

    for (monthAnchor, transactions) in transactionsByMonth {
      if transactions.count > 1 {
        let date = Date(timeIntervalSince1970: TimeInterval(monthAnchor))
        print(
          "⚠️ Month \(date): Found \(transactions.count) transactions, checking for duplicates...")

        // Find exact duplicates based on name, date, amount, and category
        let duplicatesRemoved = removeExactDuplicates(from: transactions, monthAnchor: monthAnchor)
        totalDuplicatesRemoved += duplicatesRemoved

        if duplicatesRemoved > 0 {
          print("✅ Removed \(duplicatesRemoved) exact duplicates from month \(date)")
        }
      }
    }

    print(
      "🧹 Duplicate transaction cleanup completed. Total duplicates removed: \(totalDuplicatesRemoved)"
    )
  }

  /// Remove exact duplicates based on name, date, amount, and category
  private func removeExactDuplicates(from transactions: [Transaction], monthAnchor: Int) -> Int {
    var duplicatesRemoved = 0

    // First, handle recurring transaction duplicates specifically
    duplicatesRemoved += handleRecurringTransactionDuplicates(transactions)

    // Then handle general exact duplicates
    duplicatesRemoved += handleGeneralDuplicates(transactions)

    return duplicatesRemoved
  }

  /// Handle recurring transaction duplicates (parent + instance in same month)
  private func handleRecurringTransactionDuplicates(_ transactions: [Transaction]) -> Int {
    var duplicatesRemoved = 0

    // Find parent recurring transactions and their instances
    let parentRecurring = transactions.filter {
      $0.isRecurring == true && $0.parentTransactionId == nil
    }
    let instances = transactions.filter { $0.parentTransactionId != nil }

    // First, handle duplicate parent recurring transactions
    duplicatesRemoved += handleDuplicateParentRecurringTransactions(parentRecurring)

    // Then handle instances in the same month as their parent
    for parent in parentRecurring {
      // Find instances for this parent in the same month
      let duplicateInstances = instances.filter {
        $0.parentTransactionId == parent.id && $0.budgetMonthDate == parent.budgetMonthDate
      }

      if !duplicateInstances.isEmpty {
        print(
          "🔄 Found \(duplicateInstances.count) recurring instances for parent '\(parent.title)' in same month"
        )

        // Remove all instances for the same month (keep the parent)
        for instance in duplicateInstances {
          if let instanceId = instance.id {
            do {
              try transactionRepo.delete(id: instanceId)
              duplicatesRemoved += 1
              print("✅ Deleted recurring duplicate: \(instance.title) (ID: \(instanceId))")
            } catch {
              print("❌ Failed to delete recurring duplicate: \(error)")
            }
          }
        }
      }
    }

    return duplicatesRemoved
  }

  /// Handle duplicate parent recurring transactions (same name, amount, category, type)
  private func handleDuplicateParentRecurringTransactions(_ parentTransactions: [Transaction])
    -> Int
  {
    var duplicatesRemoved = 0

    // Group parent recurring transactions by their key characteristics
    let groupedParents = Dictionary(grouping: parentTransactions) { transaction in
      let amountKey = transaction.amount
      let categoryKey = transaction.category.key
      let typeKey = transaction.type.key

      return "\(transaction.title)|\(amountKey)|\(categoryKey)|\(typeKey)"
    }

    // Process each group
    for (key, group) in groupedParents {
      if group.count > 1 {
        print("🔄 Found \(group.count) duplicate parent recurring transactions: \(key)")

        // Sort by ID to keep the oldest (lowest ID)
        let sortedGroup = group.sorted { ($0.id ?? 0) < ($1.id ?? 0) }
        let parentToKeep = sortedGroup.first!
        let duplicatesToRemove = Array(sortedGroup.dropFirst())

        print("📌 Keeping parent recurring transaction ID: \(parentToKeep.id ?? -1) (oldest)")
        print("🗑️ Removing \(duplicatesToRemove.count) duplicate parents...")

        // Remove duplicate parents and all their instances
        for duplicateParent in duplicatesToRemove {
          if let duplicateParentId = duplicateParent.id {
            // First, remove all instances of this duplicate parent
            let parentInstances = transactionRepo.fetchTransactionInstancesForRecurring(
              duplicateParentId)
            for instance in parentInstances {
              if let instanceId = instance.id {
                do {
                  try transactionRepo.delete(id: instanceId)
                  print(
                    "✅ Deleted instance of duplicate parent: \(instance.title) (ID: \(instanceId))")
                } catch {
                  print("❌ Failed to delete instance: \(error)")
                }
              }
            }

            // Then remove the duplicate parent
            do {
              try transactionRepo.delete(id: duplicateParentId)
              duplicatesRemoved += 1
              print(
                "✅ Deleted duplicate parent: \(duplicateParent.title) (ID: \(duplicateParentId))")
            } catch {
              print("❌ Failed to delete duplicate parent: \(error)")
            }
          }
        }
      }
    }

    return duplicatesRemoved
  }

  /// Handle general exact duplicates
  private func handleGeneralDuplicates(_ transactions: [Transaction]) -> Int {
    var duplicatesRemoved = 0

    // Group transactions by their key characteristics
    let groupedTransactions = Dictionary(grouping: transactions) { transaction in
      // Create a unique key based on essential properties
      let dateKey = transaction.dateTimestamp
      let amountKey = transaction.amount
      let categoryKey = transaction.category.key
      let typeKey = transaction.type.key

      return "\(transaction.title)|\(dateKey)|\(amountKey)|\(categoryKey)|\(typeKey)"
    }

    // Process each group
    for (key, group) in groupedTransactions {
      if group.count > 1 {
        print("🔍 Found \(group.count) transactions with identical properties: \(key)")

        // Sort by ID to ensure we keep the oldest transaction (lowest ID)
        let sortedGroup = group.sorted { ($0.id ?? 0) < ($1.id ?? 0) }
        let transactionToKeep = sortedGroup.first!
        let duplicatesToRemove = Array(sortedGroup.dropFirst())

        print("📌 Keeping transaction ID: \(transactionToKeep.id ?? -1) (oldest)")
        print("🗑️ Removing \(duplicatesToRemove.count) duplicates...")

        // Remove duplicates
        for duplicate in duplicatesToRemove {
          if let duplicateId = duplicate.id {
            do {
              try transactionRepo.delete(id: duplicateId)
              duplicatesRemoved += 1
              print("✅ Deleted duplicate: \(duplicate.title) (ID: \(duplicateId))")
            } catch {
              print("❌ Failed to delete duplicate: \(error)")
            }
          }
        }
      }
    }

    return duplicatesRemoved
  }
}
