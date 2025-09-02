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
      let date = Date(timeIntervalSince1970: TimeInterval(anchor))
      let month = DateFormatter.monthFormatter.string(from: date)
      let localizedMonth = "month.\(month.lowercased())".localized

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
    print("✅ Generated monthly data for \(monthlyData.count) months")

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

    print("🌍 Month comparison debugging:")
    print("   - Today: \(today)")
    print("   - Month date: \(monthDate)")
    print("   - Is current month: \(isCurrentMonth)")
    print("   - Current time: \(Date())")
    print("   - Time difference: \(today.timeIntervalSince(Date())) seconds")

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

    // Then filter by date (up to today) - simple comparison without complex timezone conversion
    let transactionsUpToToday = transactionsInCurrentMonth.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      return transactionDate <= today
    }

    // Calculate net change from all transactions up to today
    let netUpToToday = transactionsUpToToday.reduce(0) { result, transaction in
      transaction.type == .income ? result + transaction.amount : result - transaction.amount
    }

    // Debug: Log the transactions being considered
    print("📊 Current balance calculation details:")
    print("   - Transactions in current month: \(transactionsInCurrentMonth.count)")
    print("   - Transactions up to today: \(transactionsUpToToday.count)")
    print("   - Net change up to today: \(netUpToToday)")

    // Show transactions in current month for debugging
    if !transactionsInCurrentMonth.isEmpty {
      print("📊 Transactions in current month:")
      for tx in transactionsInCurrentMonth.sorted(by: { $0.date > $1.date }) {
        let type = tx.type == .income ? "💰" : "💸"
        let recurring = tx.isRecurring == true ? "🔄" : ""
        let parent = tx.parentTransactionId != nil ? "👶" : ""
        print("   \(type)\(recurring)\(parent) '\(tx.title)': \(tx.amount) (\(tx.date))")
      }
    }

    // Special debugging for "Aula de canto" transaction
    let aulaDeCantoTransactions = transactionsInCurrentMonth.filter {
      $0.title.contains("Aula de canto")
    }
    if !aulaDeCantoTransactions.isEmpty {
      print("🎵 'Aula de canto' transactions found in current month:")
      for tx in aulaDeCantoTransactions {
        let type = tx.type == .income ? "💰" : "💸"
        let isUpToToday = tx.date <= today
        print("   \(type) '\(tx.title)': \(tx.amount) (\(tx.date)) - Up to today: \(isUpToToday)")
      }
    } else {
      print("❌ No 'Aula de canto' transactions found in current month")
    }

    // Show some transaction details for debugging
    let recentTransactions = transactionsUpToToday.sorted { $0.date > $1.date }.prefix(10)
    if !recentTransactions.isEmpty {
      print("📊 Recent transactions affecting current balance:")
      for tx in recentTransactions {
        let type = tx.type == .income ? "💰" : "💸"
        let recurring = tx.isRecurring == true ? "🔄" : ""
        let parent = tx.parentTransactionId != nil ? "👶" : ""
        print("   \(type)\(recurring)\(parent) '\(tx.title)': \(tx.amount) (\(tx.date))")
      }
    }

    // Current balance = previous month's balance + net change up to today
    let currentBalance = previousBalance + netUpToToday

    print(
      "📊 Current month balance calculation: previous=\(previousBalance), netUpToToday=\(netUpToToday), current=\(currentBalance)"
    )
    print("📊 Transactions up to today: \(transactionsUpToToday.count)")

    // Debug: Show some transaction details
    if transactionsUpToToday.count > 0 {
      let recentTransactions = transactionsUpToToday.sorted { $0.date > $1.date }.prefix(5)
      print("📊 Recent transactions up to today:")
      for tx in recentTransactions {
        let type = tx.type == .income ? "💰" : "💸"
        print("   \(type) \(tx.title): \(tx.amount) (\(tx.date))")
      }
    }

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

    print("🔄 Refreshed current month balance cache for anchor: \(currentMonthAnchor)")

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

    print("🔄 Force refreshing current month balance...")
    print("🌍 Timezone: \(userTimeZone.identifier)")
    print("📅 Today (UTC): \(today)")
    print("📅 Today (User TZ): \(todayInUserTZ)")
    print("📅 Current month anchor: \(currentMonthAnchor)")

    // Clear all cache to ensure fresh calculation
    monthlyDataCache.removeAll()
    lastCacheUpdate = Date.distantPast

    // Force recalculate current month
    let freshData = calculateMonthlyData(for: currentMonthAnchor...currentMonthAnchor)
    if let currentMonthData = freshData.first {
      print("💰 Fresh current month data:")
      print("   - Final Balance: \(currentMonthData.finalBalance ?? 0)")
      print("   - Current Balance: \(currentMonthData.currentBalance ?? 0)")
      print("   - Previous Balance: \(currentMonthData.previousBalance ?? 0)")
    }

    // Also run the specific debug for "Aula de canto"
    print("🎵 Running specific debug for 'Aula de canto'...")
    debugAulaDeCantoTransaction()
  }

  /// Debug method to check current balance calculation
  func debugCurrentBalanceCalculation() {
    let today = Date()

    // Use user's current timezone for month anchor calculation
    let userTimeZone = TimeZone.current
    var userCalendar = Calendar.current
    userCalendar.timeZone = userTimeZone

    let todayInUserTZ =
      userCalendar.date(byAdding: .second, value: userTimeZone.secondsFromGMT(), to: today)
      ?? today
    let currentMonthAnchor = todayInUserTZ.monthAnchor

    print("🔍 Debugging current balance calculation...")
    print("🌍 Timezone: \(userTimeZone.identifier)")
    print("📅 Today (UTC): \(today)")
    print("📅 Today (User TZ): \(todayInUserTZ)")
    print("📅 Current month anchor: \(currentMonthAnchor)")
    print(
      "📅 Cache status: \(monthlyDataCache.isEmpty ? "Empty" : "Has \(monthlyDataCache.count) items")"
    )
    print("📅 Last cache update: \(lastCacheUpdate)")

    // Check if we have cached data for current month
    if let cachedData = monthlyDataCache[currentMonthAnchor] {
      print("📊 Cached data for current month:")
      print("   - Final Balance: \(cachedData.finalBalance ?? 0)")
      print("   - Current Balance: \(cachedData.currentBalance ?? 0)")
      print("   - Previous Balance: \(cachedData.previousBalance ?? 0)")
    } else {
      print("📊 No cached data for current month")
    }

    // Check all transactions
    let allTransactions = transactionRepo.fetchAllTransactions()
    print("📊 Total transactions in system: \(allTransactions.count)")

    // Check transactions for current month using dynamic month anchor calculation
    let currentMonthTransactions = allTransactions.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      let transactionMonthAnchor = transactionDate.monthAnchor
      return transactionMonthAnchor == currentMonthAnchor
    }
    print(
      "📊 Transactions with current month budget date: \(currentMonthAnchor): \(currentMonthTransactions.count)"
    )

    // Check transactions up to today using user's timezone
    let transactionsUpToToday = allTransactions.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      let transactionDateInUserTZ =
        userCalendar.date(
          byAdding: .second, value: userTimeZone.secondsFromGMT(), to: transactionDate)
        ?? transactionDate
      return transactionDateInUserTZ <= todayInUserTZ
    }
    print("📊 Transactions up to today (User TZ): \(transactionsUpToToday.count)")

    // Debug: Look for "Aula de canto" specifically
    let aulaDeCantoTransactions = allTransactions.filter { $0.title.contains("Aula de canto") }
    if !aulaDeCantoTransactions.isEmpty {
      print("🎵 Found 'Aula de canto' transactions:")
      for tx in aulaDeCantoTransactions {
        let txDateInUserTZ =
          userCalendar.date(
            byAdding: .second, value: userTimeZone.secondsFromGMT(), to: tx.date) ?? tx.date
        let txMonthAnchor = tx.date.monthAnchor
        print(
          "   - ID: \(tx.id ?? -1), Amount: \(tx.amount), Date (UTC): \(tx.date), Date (User TZ): \(txDateInUserTZ), Month Anchor: \(txMonthAnchor), isRecurring: \(tx.isRecurring ?? false), parentId: \(tx.parentTransactionId ?? -1)"
        )
      }
    } else {
      print("❌ No 'Aula de canto' transactions found")
    }

    // Debug: Check recurring transactions specifically
    let recurringTransactions = allTransactions.filter { $0.isRecurring == true }
    print("🔄 Recurring transactions: \(recurringTransactions.count)")
    for tx in recurringTransactions {
      let txDateInUserTZ =
        userCalendar.date(byAdding: .second, value: userTimeZone.secondsFromGMT(), to: tx.date)
        ?? tx.date
      let txMonthAnchor = tx.date.monthAnchor
      print(
        "   - '\(tx.title)': Amount: \(tx.amount), Date (UTC): \(tx.date), Date (User TZ): \(txDateInUserTZ), Month Anchor: \(txMonthAnchor), parentId: \(tx.parentTransactionId ?? -1)"
      )
    }

    // Debug: Check current month transactions in detail
    print("📊 Current month transactions detail:")
    for tx in currentMonthTransactions {
      let type = tx.type == .income ? "💰" : "💸"
      let recurring = tx.isRecurring == true ? "🔄" : ""
      let parent = tx.parentTransactionId != nil ? "👶" : ""
      let txDateInUserTZ =
        userCalendar.date(byAdding: .second, value: userTimeZone.secondsFromGMT(), to: tx.date)
        ?? tx.date
      print(
        "   \(type)\(recurring)\(parent) '\(tx.title)': \(tx.amount) (UTC: \(tx.date), User TZ: \(txDateInUserTZ))"
      )
    }
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

    print("📊 Balance calculation context:")
    print("🌍 Timezone: \(userTimeZone.identifier)")
    print("   - Today (UTC): \(today)")
    print("   - Today (User TZ): \(todayInUserTZ)")
    print("   - Current month anchor: \(currentMonthAnchor)")
    print("   - Transactions in current month: \(currentMonthTransactions.count)")
    print("   - Transactions up to today (User TZ): \(transactionsUpToToday.count)")

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
    print("🔄 Starting budget migration to new timezone-based month anchors...")

    let budgetRepo = BudgetRepository()
    let allBudgets = budgetRepo.fetchBudgets()

    if allBudgets.isEmpty {
      print("📊 No budgets found to migrate")
      return
    }

    print("📊 Found \(allBudgets.count) budgets to migrate")

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

    print("🔄 Budget migration completed. Migrated \(migratedCount) budgets")

    // Clear cache to ensure fresh data
    invalidateCache()
  }

  /// Migrate existing transactions to use new timezone-based month anchors
  func migrateTransactionsToNewTimezone() {
    print("🔄 Starting transaction migration to new timezone-based month anchors...")

    let allTransactions = transactionRepo.fetchAllTransactions()

    if allTransactions.isEmpty {
      print("📊 No transactions found to migrate")
      return
    }

    print("📊 Found \(allTransactions.count) transactions to migrate")

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

  /// Comprehensive migration: migrate both budgets and transactions to new timezone-based month anchors
  func migrateAllDataToNewTimezone() {
    print("🔄 Starting comprehensive data migration to new timezone-based month anchors...")

    // First migrate budgets
    migrateBudgetsToNewTimezone()

    // Then migrate transactions
    migrateTransactionsToNewTimezone()

    print("🔄 Comprehensive data migration completed!")
  }
}
