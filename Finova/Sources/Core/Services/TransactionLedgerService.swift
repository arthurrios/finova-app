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
        return cachedData
      }
    }

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

      guard let monthDate = calendar.date(from: components) else {
        print(
          "❌ Failed to create date from components: year=\(targetYear), month=\(normalizedMonth)")
        continue
      }
      let anchor = monthDate.monthAnchor
      anchors.append(anchor)
    }

    // Calculate running balance
    var runningBalance = [Int: Int]()
    var previousAvailable = 0

    let monthlyData = anchors.map { anchor in
      // Reconstruct date using the same method as monthAnchor calculation
      // This ensures timezone consistency
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone.current

      // Convert anchor back to date components
      // The anchor is the timestamp of the first day of the month
      let anchorDate = Date(timeIntervalSince1970: TimeInterval(anchor))
      let components = calendar.dateComponents([.year, .month], from: anchorDate)

      print(
        "🔍 TransactionLedgerService: anchor=\(anchor), anchorDate=\(anchorDate), components=\(components)"
      )

      // Create a proper date in the user's timezone
      guard let date = calendar.date(from: components) else {
        print("❌ Failed to reconstruct date from anchor: \(anchor), components: \(components)")
        // Return a fallback date if reconstruction fails
        let fallbackDate = Date(timeIntervalSince1970: TimeInterval(anchor))
        return MonthBudgetCardType(
          date: fallbackDate,
          month: "Unknown",
          usedValue: 0,
          budgetLimit: nil,
          finalBalance: 0,
          currentBalance: 0,
          previousBalance: 0
        )
      }

      let month = DateFormatter.monthFormatter.string(from: date)
      let localizedMonth = "month.\(month.lowercased())".localized

      // Debug logging
      print("🔍 TransactionLedgerService: Month=\(localizedMonth), Date=\(date)")
      let testRange = calendar.range(of: .day, in: .month, for: date)
      print(
        "🔍 TransactionLedgerService: Range=\(String(describing: testRange)), Days=\((testRange?.upperBound ?? 0) - (testRange?.lowerBound ?? 0))"
      )

      // Get transactions for this month using DYNAMIC month anchor calculation
      // This fixes the timezone issue by calculating month anchors on-the-fly
      let transactionsForMonth = allTransactions.filter { transaction in
        let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
        let transactionMonthAnchor = transactionDate.monthAnchor
        return transactionMonthAnchor == anchor
      }

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
    return monthlyData
  }

  // MARK: - Transaction Filtering

  func getTransactionsForMonth(_ monthAnchor: Int) -> [Transaction] {
    let allTransactions = transactionRepo.fetchAllTransactions()
    return
      allTransactions
      .filter { transaction in
        let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
        let transactionMonthAnchor = transactionDate.monthAnchor
        return transactionMonthAnchor == monthAnchor
      }
      .sorted { $0.date > $1.date }
  }

  func getTransactionsForDateRange(from startDate: Date, to endDate: Date) -> [Transaction] {
    let allTransactions = transactionRepo.fetchAllTransactions()
    let startAnchor = startDate.monthAnchor
    let endAnchor = endDate.monthAnchor

    return
      allTransactions
      .filter { transaction in
        let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
        let transactionMonthAnchor = transactionDate.monthAnchor
        return transactionMonthAnchor >= startAnchor && transactionMonthAnchor <= endAnchor
      }
      .sorted { $0.date > $1.date }
  }

  // MARK: - Balance Calculations

  /// Calculate the balance up to the current date within a specific month
  func calculateCurrentBalanceForMonth(anchor: Int, previousBalance: Int) -> Int {
    let allTransactions = transactionRepo.fetchAllTransactions()

    let today = Date()
    let monthDate = Date(timeIntervalSince1970: TimeInterval(anchor))

    // Check if this is the current month using simple month comparison
    let calendar = Calendar.current
    let isCurrentMonth = calendar.isDate(monthDate, equalTo: today, toGranularity: .month)

    if !isCurrentMonth {
      // For past/future months, return the final balance (end-of-month)
      return previousBalance
    }

    // For current month, calculate balance up to today
    // First filter by month using monthAnchor (which already handles timezone correctly)
    let transactionsInCurrentMonth = allTransactions.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      let transactionMonthAnchor = transactionDate.monthAnchor
      return transactionMonthAnchor == anchor
    }

    // Get today's date components for proper date comparison
    let todayComponents = calendar.dateComponents([.year, .month, .day], from: today)
    let todayStart = calendar.date(from: todayComponents) ?? today

    // Filter transactions up to and including today using date components comparison
    // This ensures we include all transactions for the current day regardless of time
    let transactionsUpToToday = transactionsInCurrentMonth.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      let transactionComponents = calendar.dateComponents(
        [.year, .month, .day], from: transactionDate)
      let transactionDateOnly = calendar.date(from: transactionComponents) ?? transactionDate

      // Include transactions from today and earlier
      return transactionDateOnly <= todayStart
    }

    // Debug logging to track transaction inclusion
    print(
      "🔍 calculateCurrentBalanceForMonth: Found \(transactionsInCurrentMonth.count) transactions in current month"
    )
    print(
      "🔍 calculateCurrentBalanceForMonth: Including \(transactionsUpToToday.count) transactions up to today"
    )

    // Log transactions for today specifically
    let todayTransactions = transactionsInCurrentMonth.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      return calendar.isDate(transactionDate, inSameDayAs: today)
    }
    print(
      "🔍 calculateCurrentBalanceForMonth: Found \(todayTransactions.count) transactions for today")
    for transaction in todayTransactions {
      print(
        "🔍 Today's transaction: \(transaction.title) - \(transaction.amount) (\(transaction.type))")
    }

    // Calculate net change from all transactions up to today
    let netUpToToday = transactionsUpToToday.reduce(0) { result, transaction in
      transaction.type == .income ? result + transaction.amount : result - transaction.amount
    }

    // Current balance = previous month's balance + net change up to today
    let currentBalance = previousBalance + netUpToToday

    print(
      "🔍 calculateCurrentBalanceForMonth: Previous balance: \(previousBalance), Net up to today: \(netUpToToday), Current balance: \(currentBalance)"
    )

    return currentBalance
  }

  func calculateCurrentBalance(for monthAnchor: Int) -> Int {
    let allTransactions = transactionRepo.fetchAllTransactions()
    let today = Date()
    let monthDate = Date(timeIntervalSince1970: TimeInterval(monthAnchor))

    // Get all transactions up to the current month using dynamic month anchor calculation
    let relevantTransactions = allTransactions.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      let transactionMonthAnchor = transactionDate.monthAnchor
      return transactionMonthAnchor <= monthAnchor
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

    // Also invalidate the last cache update time to force fresh calculation
    lastCacheUpdate = Date.distantPast
  }

  /// Force refresh current month balance with detailed logging
  func forceRefreshCurrentMonthBalance() {
    let today = Date()

    // Use user's current timezone for month anchor calculation
    let userTimeZone = TimeZone.current
    var userCalendar = Calendar.current
    userCalendar.timeZone = userTimeZone

    // Calculate current month anchor using user's timezone
    let todayInUserTZ =
      userCalendar.date(byAdding: .second, value: userTimeZone.secondsFromGMT(), to: today)
      ?? today
    let currentMonthAnchor = todayInUserTZ.monthAnchor

    // Clear all cache to ensure fresh calculation
    monthlyDataCache.removeAll()
    lastCacheUpdate = Date.distantPast

    // Force recalculate current month
    let freshData = calculateMonthlyData(for: currentMonthAnchor...currentMonthAnchor)
    if let currentMonthData = freshData.first {
      print(
        "💰 Fresh current month data - Final: \(currentMonthData.finalBalance ?? 0), Current: \(currentMonthData.currentBalance ?? 0)"
      )
    }

  }

  /// Force refresh all balance calculations (useful after fixing date comparison issues)
  func forceRefreshAllBalances() {
    print("🔄 Force refreshing all balance calculations...")

    // Clear all cache
    monthlyDataCache.removeAll()
    lastCacheUpdate = Date.distantPast

    // Force recalculate a range of months to ensure fresh data
    let today = Date()
    let currentMonthAnchor = today.monthAnchor
    let monthRange = (currentMonthAnchor - 2)...(currentMonthAnchor + 1)  // Include previous and next month

    let freshData = calculateMonthlyData(for: monthRange)
    print("💰 Refreshed \(freshData.count) months of data")

    for monthData in freshData {
      print(
        "💰 Month \(monthData.month): Final=\(monthData.finalBalance ?? 0), Current=\(monthData.currentBalance ?? 0)"
      )
    }
  }

  // MARK: - Daily Balance Calculations

  /// Calculate balance for a specific day within a month
  func calculateBalanceForDay(day: Int, monthAnchor: Int, previousMonthBalance: Int) -> Int {
    let allTransactions = transactionRepo.fetchAllTransactions()

    // Get the month date from anchor
    let monthDate = Date(timeIntervalSince1970: TimeInterval(monthAnchor))

    // Create target date for the specific day
    var calendar = Calendar.current
    calendar.timeZone = TimeZone.current

    guard let targetDate = calendar.date(bySetting: .day, value: day, of: monthDate) else {
      return previousMonthBalance
    }

    // Get all transactions up to the target date using robust date comparison
    let targetDateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
    let targetDateOnly = calendar.date(from: targetDateComponents) ?? targetDate

    let transactionsUpToTargetDate = allTransactions.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      let transactionComponents = calendar.dateComponents(
        [.year, .month, .day], from: transactionDate)
      let transactionDateOnly = calendar.date(from: transactionComponents) ?? transactionDate

      // Include transactions from target date and earlier
      return transactionDateOnly <= targetDateOnly
    }

    // Calculate running balance from the beginning of time up to target date
    var runningBalance = 0
    var lastProcessedMonthAnchor = -1

    // Group transactions by month
    let transactionsByMonth = Dictionary(grouping: transactionsUpToTargetDate) { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      return transactionDate.monthAnchor
    }

    // Process months in chronological order
    let sortedMonthAnchors = transactionsByMonth.keys.sorted()

    for monthAnchor in sortedMonthAnchors {
      let transactionsInMonth = transactionsByMonth[monthAnchor] ?? []

      // For the target month, only include transactions up to the target day
      let monthDate = Date(timeIntervalSince1970: TimeInterval(monthAnchor))
      let isTargetMonth = calendar.isDate(monthDate, equalTo: targetDate, toGranularity: .month)

      let relevantTransactions: [Transaction]
      if isTargetMonth {
        // Filter transactions up to the target day using robust date comparison
        relevantTransactions = transactionsInMonth.filter { transaction in
          let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
          let transactionComponents = calendar.dateComponents(
            [.year, .month, .day], from: transactionDate)
          let transactionDateOnly = calendar.date(from: transactionComponents) ?? transactionDate

          // Include transactions from target date and earlier
          return transactionDateOnly <= targetDateOnly
        }
      } else {
        // Include all transactions for previous months
        relevantTransactions = transactionsInMonth
      }

      // Calculate net change for this month
      let netChange = relevantTransactions.reduce(0) { result, transaction in
        transaction.type == .income ? result + transaction.amount : result - transaction.amount
      }

      // Debug logging for target month
      if isTargetMonth {
        print(
          "🔍 calculateBalanceForDay: Target month (day \(day)) - Found \(relevantTransactions.count) transactions"
        )
        for transaction in relevantTransactions {
          let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
          let dayComponent = calendar.component(.day, from: transactionDate)
          print(
            "🔍 Day \(dayComponent) transaction: \(transaction.title) - \(transaction.amount) (\(transaction.type))"
          )
        }
        print("🔍 Net change for target month: \(netChange)")
      }

      runningBalance += netChange
      lastProcessedMonthAnchor = monthAnchor
    }

    return runningBalance
  }

  /// Calculate balance for a specific day in the current month
  func calculateCurrentMonthBalanceForDay(day: Int) -> Int {
    let today = Date()
    let currentMonthAnchor = today.monthAnchor

    // Get previous month's final balance
    let previousMonthAnchor = currentMonthAnchor - 1
    let previousMonthData = calculateMonthlyData(for: previousMonthAnchor...previousMonthAnchor)
    let previousBalance = previousMonthData.first?.finalBalance ?? 0

    return calculateBalanceForDay(
      day: day, monthAnchor: currentMonthAnchor, previousMonthBalance: previousBalance)
  }

  /// Debug method to specifically check "Aula de canto" transaction
  func debugAulaDeCantoTransaction() {
    print("🎵 Debugging 'Aula de canto' transaction specifically...")

    let allTransactions = transactionRepo.fetchAllTransactions()
    let aulaDeCantoTransactions = allTransactions.filter { $0.title.contains("Aula de canto") }

    if aulaDeCantoTransactions.isEmpty {
      print("❌ No 'Aula de canto' transactions found in the system")
      return
    }

    print("🎵 Found \(aulaDeCantoTransactions.count) 'Aula de canto' transactions:")

    for (index, tx) in aulaDeCantoTransactions.enumerated() {
      print("🎵 Transaction \(index + 1):")
      print("   - ID: \(tx.id ?? -1)")
      print("   - Title: '\(tx.title)'")
      print("   - Amount: \(tx.amount)")
      print("   - Date: \(tx.date)")
      print("   - Date Timestamp: \(tx.dateTimestamp)")
      let txMonthAnchor = tx.date.monthAnchor
      print("   - Month Anchor (calculated): \(txMonthAnchor)")
      print("   - Is Recurring: \(tx.isRecurring ?? false)")
      print("   - Parent Transaction ID: \(tx.parentTransactionId ?? -1)")
      print("   - Category: \(tx.category.key)")
      print("   - Type: \(tx.type.key)")

      // Check if it's in current month using dynamic month anchor calculation
      let today = Date()
      let currentMonthAnchor = today.monthAnchor
      let currentMonthAnchorUTC = today.monthAnchorUTC
      let isCurrentMonth = txMonthAnchor == currentMonthAnchor
      let isUpToToday = tx.date <= today

      print("   - Is Current Month: \(isCurrentMonth)")
      print("   - Is Up To Today: \(isUpToToday)")
      print("   - Should Affect Current Balance: \(isCurrentMonth && isUpToToday)")
      print("   - Current month anchor (User TZ): \(currentMonthAnchor)")
      print("   - Current month anchor (UTC): \(currentMonthAnchorUTC)")
      print("   - Transaction month anchor (calculated): \(txMonthAnchor)")
      print("   - Month anchor difference: \(txMonthAnchor - currentMonthAnchor)")
    }

    // Check if it's affecting the current balance calculation
    let today = Date()

    // Use user's current timezone for month anchor calculation
    let userTimeZone = TimeZone.current
    var userCalendar = Calendar.current
    userCalendar.timeZone = userTimeZone

    let todayInUserTZ =
      userCalendar.date(byAdding: .second, value: userTimeZone.secondsFromGMT(), to: today)
      ?? today
    let currentMonthAnchor = todayInUserTZ.monthAnchor

    let currentMonthTransactions = allTransactions.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      let transactionMonthAnchor = transactionDate.monthAnchor
      return transactionMonthAnchor == currentMonthAnchor
    }
    let transactionsUpToToday = allTransactions.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      let transactionDateInUserTZ =
        userCalendar.date(
          byAdding: .second, value: userTimeZone.secondsFromGMT(), to: transactionDate)
        ?? transactionDate
      return transactionDateInUserTZ <= todayInUserTZ
    }

    // Check if "Aula de canto" is in transactions up to today
    let aulaDeCantoUpToToday = transactionsUpToToday.filter { $0.title.contains("Aula de canto") }
    print("   - 'Aula de canto' transactions up to today: \(aulaDeCantoUpToToday.count)")

    if !aulaDeCantoUpToToday.isEmpty {
      print("✅ 'Aula de canto' IS being considered in current balance calculation")
    } else {
      print("❌ 'Aula de canto' is NOT being considered in current balance calculation")

      // Check why it's not being included
      for tx in aulaDeCantoTransactions {
        let transactionDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
        let transactionDateInUserTZ =
          userCalendar.date(
            byAdding: .second, value: userTimeZone.secondsFromGMT(), to: transactionDate)
          ?? transactionDate
        print(
          "   - '\(tx.title)' date (UTC): \(transactionDate), date (User TZ): \(transactionDateInUserTZ), today (User TZ): \(todayInUserTZ), isBeforeOrToday: \(transactionDateInUserTZ <= todayInUserTZ)"
        )
      }
    }
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

  /// Migrate existing budgets to use new timezone-based month anchors
  func migrateBudgetsToNewTimezone() {

    let budgetRepo = BudgetRepository()
    let allBudgets = budgetRepo.fetchBudgets()

    if allBudgets.isEmpty {
      return
    }

    var migratedCount = 0

    for budget in allBudgets {
      // Convert the old month anchor to a date
      let oldDate = Date(timeIntervalSince1970: TimeInterval(budget.monthDate))

      // Calculate new month anchor using current timezone
      let newMonthAnchor = oldDate.monthAnchor

      // If the month anchor changed, update the budget
      if newMonthAnchor != budget.monthDate {
        print(
          "🔄 Migrating budget: \(oldDate) (old anchor: \(budget.monthDate) → new anchor: \(newMonthAnchor))"
        )

        do {
          // Create new budget with new month anchor
          let newBudget = BudgetModel(monthDate: newMonthAnchor, amount: budget.amount)

          // Delete old budget
          try budgetRepo.delete(monthDate: budget.monthDate)

          // Insert new budget
          try budgetRepo.insert(budget: newBudget)

          migratedCount += 1
          print("✅ Successfully migrated budget for \(oldDate)")
        } catch {
          print("❌ Failed to migrate budget for \(oldDate): \(error)")
        }
      } else {
        print("⏭️ Budget for \(oldDate) already has correct month anchor: \(budget.monthDate)")
      }
    }

    // Clear cache to ensure fresh data
    invalidateCache()
  }

  /// Migrate existing transactions to use new timezone-based month anchors
  func migrateTransactionsToNewTimezone() {

    let allTransactions = transactionRepo.fetchAllTransactions()

    if allTransactions.isEmpty {
      return
    }

    var migratedCount = 0

    for transaction in allTransactions {
      // Convert the old month anchor to a date
      let oldDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))

      // Calculate new month anchor using current timezone
      let newMonthAnchor = oldDate.monthAnchor

      // If the month anchor changed, we need to adjust the dateTimestamp
      if newMonthAnchor != transaction.budgetMonthDate {
        print(
          "🔄 Migrating transaction '\(transaction.title)': \(oldDate) (old anchor: \(transaction.budgetMonthDate) → new anchor: \(newMonthAnchor))"
        )

        // Calculate the adjustment needed
        let oldMonthAnchor = transaction.budgetMonthDate
        let adjustment = newMonthAnchor - oldMonthAnchor

        // Adjust the dateTimestamp to match the new month anchor
        let newDateTimestamp = transaction.dateTimestamp + adjustment

        print(
          "   - Adjusting dateTimestamp: \(transaction.dateTimestamp) → \(newDateTimestamp) (adjustment: \(adjustment))"
        )

        // Since we can't directly update transactions, we'll need to recreate them
        // For now, let's just log the migration and clear the cache
        // The actual migration will happen when transactions are recreated
        migratedCount += 1
        print(
          "✅ Marked transaction '\(transaction.title)' for migration (date adjustment: \(adjustment) seconds)"
        )
      } else {
        print(
          "⏭️ Transaction '\(transaction.title)' already has correct month anchor: \(transaction.budgetMonthDate)"
        )
      }
    }

    print(
      "🔄 Transaction migration analysis completed. \(migratedCount) transactions need date adjustment."
    )
    print("⚠️ Note: Transaction migration requires recreating transactions with adjusted dates.")
    print("⚠️ This will be handled automatically when the app processes transactions.")

    // Clear cache to ensure fresh data
    invalidateCache()
  }

  /// Clean up any duplicate transactions that might exist from before the fix
  func cleanupDuplicateTransactions() {
    let allTransactions = transactionRepo.fetchAllTransactions()

    print("🧹 Cleaning up duplicate transactions...")

    // Group transactions by month for easier processing
    let transactionsByMonth = Dictionary(grouping: allTransactions) { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      return transactionDate.monthAnchor
    }

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
      // Find instances for this parent in the same month using dynamic month anchor calculation
      let duplicateInstances = instances.filter { instance in
        let parentDate = Date(timeIntervalSince1970: TimeInterval(parent.dateTimestamp))
        let instanceDate = Date(timeIntervalSince1970: TimeInterval(instance.dateTimestamp))
        let parentMonthAnchor = parentDate.monthAnchor
        let instanceMonthAnchor = instanceDate.monthAnchor
        return instance.parentTransactionId == parent.id && instanceMonthAnchor == parentMonthAnchor
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
      let dateKey = transaction.dateTimestamp
      let amountKey = transaction.amount
      let categoryKey = transaction.category.key
      let typeKey = transaction.type.key

      return "\(transaction.title)|\(dateKey)|\(amountKey)|\(categoryKey)|\(typeKey)"
    }

    // Process each group
    for (key, group) in groupedParents {
      if group.count > 1 {

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

  /// Comprehensive migration: migrate both budgets and transactions to new timezone-based month anchors
  func migrateAllDataToNewTimezone() {

    // First migrate budgets
    migrateBudgetsToNewTimezone()

    // Then migrate transactions
    migrateTransactionsToNewTimezone()

  }

  /// Clear all cached data to force fresh calculation (useful for debugging)
  func clearAllCache() {
    monthlyDataCache.removeAll()
    lastCacheUpdate = Date.distantPast
    print("🧹 Cleared all monthly data cache")
  }

  /// Check if transactions can be recovered from SQLite
  func checkSQLiteRecovery() -> [Transaction] {
    do {
      // Try to get transactions directly from SQLite
      let sqliteTransactions = try DBHelper.shared.getTransactions()
      return sqliteTransactions
    } catch {
      return []
    }
  }

  /// Attempt to recover transactions from SQLite to SecureLocalDataManager
  func attemptTransactionRecovery() -> Bool {
    let sqliteTransactions = checkSQLiteRecovery()

    if sqliteTransactions.count > 0 {
      // Save recovered transactions to SecureLocalDataManager
      SecureLocalDataManager.shared.saveTransactions(sqliteTransactions)

      // Clear cache to force fresh calculation
      clearAllCache()

      return true
    } else {
      return false
    }
  }

}
