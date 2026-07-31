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
  private let creditCardService = CreditCardService()
  private let calendar = Calendar.current

  // Cache for performance optimization
  private var monthlyDataCache: [Int: MonthBudgetCardType] = [:]
  private var lastCacheUpdate: Date = Date.distantPast
  private let cacheValidityDuration: TimeInterval = 60  // 1 minute

  // P2: memoize the full transaction+statement array for a short window. Per-day balance calls
  // (e.g. dragging the day slider) previously re-fetched and re-mapped the ENTIRE table on every
  // call; this serves them from one fetch. Same staleness window as monthlyDataCache and cleared
  // by the same invalidation points, so it never serves data older than the balances beside it.
  private var cachedAllTransactions: [Transaction]?
  private var cachedAllTransactionsTime: Date = Date.distantPast

  init(
    transactionRepo: TransactionRepository = TransactionRepository(),
    budgetRepo: BudgetRepository = BudgetRepository()
  ) {
    self.transactionRepo = transactionRepo
    self.budgetRepo = budgetRepo
  }

  /// Fetches all transactions including synthetic CC statement transactions for balance calculations
  private func fetchAllTransactionsIncludingStatements() -> [Transaction] {
    if let cached = cachedAllTransactions,
       Date().timeIntervalSince(cachedAllTransactionsTime) < cacheValidityDuration {
      return cached
    }
    var transactions = transactionRepo.fetchAllTransactions()
    if let uid = AuthenticationManager.shared.currentUser?.uid {
      let statementTxs = creditCardService.generateStatementTransactions(userId: uid)
      transactions.append(contentsOf: statementTxs)
    }
    cachedAllTransactions = transactions
    cachedAllTransactionsTime = Date()
    return transactions
  }

  // MARK: - Group-Aware Fetching

  /// Fetches transactions for group context — includes ALL members' transactions
  private func fetchGroupTransactionsIncludingStatements(groupId: String) -> [Transaction] {
    var transactions = transactionRepo.fetchTransactionsForGroup(groupId: groupId)

    let sharedCards = CreditCardRepository().fetchCardsForGroup(groupId: groupId)
    for card in sharedCards {
      let statementTxs = creditCardService.generateStatementTransactions(
        forCard: card,
        in: .group(groupId)
      )
      transactions.append(contentsOf: statementTxs)
    }
    return transactions
  }

  /// Group-aware monthly data calculation
  func calculateMonthlyDataForGroup(
    groupId: String,
    for monthRange: ClosedRange<Int>,
    referenceDate: Date = Date()
  ) -> [MonthBudgetCardType] {
    let currentComponents = calendar.dateComponents([.year, .month], from: referenceDate)
    let currentYear = currentComponents.year!
    let currentMonth = currentComponents.month!

    var anchors: [Int] = []
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

      guard let monthDate = calendar.date(from: components) else { continue }
      anchors.append(monthDate.monthAnchor)
    }

    let allTransactions = fetchGroupTransactionsIncludingStatements(groupId: groupId)
    let budgetsByAnchor = budgetRepo.fetchBudgetsForGroup(groupId: groupId)
      .reduce(into: [:]) { acc, entry in acc[entry.monthDate] = entry.amount }

    var previousAvailable = UIDUserDefaultsManager.shared.getGroupBalanceOffset(groupId: groupId)

    return anchors.map { anchor in
      var cal = Calendar(identifier: .gregorian)
      cal.timeZone = TimeZone.current
      let anchorDate = Date(timeIntervalSince1970: TimeInterval(anchor))
      let components = cal.dateComponents([.year, .month], from: anchorDate)

      guard let date = cal.date(from: components) else {
        return MonthBudgetCardType(
          date: Date(timeIntervalSince1970: TimeInterval(anchor)),
          month: "Unknown", usedValue: 0, budgetLimit: nil,
          finalBalance: 0, currentBalance: 0, previousBalance: 0)
      }

      let month = DateFormatter.monthFormatter.string(from: date)
      let localizedMonth = "month.\(month.lowercased())".localized

      let transactionsForMonth = allTransactions.filter { transaction in
        let txDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
        return txDate.monthAnchor == anchor
      }

      let cashTransactions = transactionsForMonth.filter { tx in
        tx.creditCardId == nil || tx.isCreditCardStatement == true
      }
      let expense = cashTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
      let income = cashTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
      let budgetLimit = budgetsByAnchor[anchor]

      // usedValue counts individual CC transactions in the month they were created
      // (same logic as personal path). Statement synthetics only affect balance.
      let usedTransactions = transactionsForMonth.filter { tx in
        tx.isCreditCardStatement != true
      }
      let usedValue = usedTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }

      let net = income - expense
      let available = previousAvailable + net

      // Calculate current balance (balance up to current date) for groups too
      let currentBalance = calculateCurrentBalanceForGroupMonth(
        anchor: anchor, previousBalance: previousAvailable,
        transactions: allTransactions)

      let monthData = MonthBudgetCardType(
        date: date,
        month: localizedMonth,
        usedValue: usedValue,
        budgetLimit: budgetLimit,
        finalBalance: available,
        currentBalance: currentBalance,
        previousBalance: previousAvailable
      )

      previousAvailable = available
      return monthData
    }
  }

  /// Calculate the balance up to the current date for a group month
  private func calculateCurrentBalanceForGroupMonth(
    anchor: Int, previousBalance: Int, transactions: [Transaction]
  ) -> Int {
    let today = Date()
    let monthDate = Date(timeIntervalSince1970: TimeInterval(anchor))

    let transactionsInMonth = transactions.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      return transactionDate.monthAnchor == anchor
    }

    let isCurrentMonth = calendar.isDate(monthDate, equalTo: today, toGranularity: .month)
    let isPastMonth = monthDate < today && !isCurrentMonth

    let cashTransactions = transactionsInMonth.filter { tx in
      tx.creditCardId == nil || tx.isCreditCardStatement == true
    }

    if isPastMonth {
      let netForMonth = cashTransactions.reduce(0) { result, transaction in
        transaction.type == .income ? result + transaction.amount : result - transaction.amount
      }
      return previousBalance + netForMonth
    }

    if !isCurrentMonth {
      return previousBalance
    }

    // Current month: only include transactions up to today
    let todayComponents = calendar.dateComponents([.year, .month, .day], from: today)
    let todayStart = calendar.date(from: todayComponents) ?? today

    let transactionsUpToToday = cashTransactions.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      let transactionComponents = calendar.dateComponents(
        [.year, .month, .day], from: transactionDate)
      let transactionDateOnly = calendar.date(from: transactionComponents) ?? transactionDate
      return transactionDateOnly <= todayStart
    }

    let netUpToToday = transactionsUpToToday.reduce(0) { result, transaction in
      transaction.type == .income ? result + transaction.amount : result - transaction.amount
    }

    return previousBalance + netUpToToday
  }

  // MARK: - Monthly Calculations

  func calculateMonthlyData(for monthRange: ClosedRange<Int>, referenceDate: Date = Date())
    -> [MonthBudgetCardType]
  {
    let currentComponents = calendar.dateComponents([.year, .month], from: referenceDate)
    let currentYear = currentComponents.year!
    let currentMonth = currentComponents.month!

    // Generate month anchors from offsets
    var anchors: [Int] = []
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
        logError(
          "Failed to create date from components: year=\(targetYear), month=\(normalizedMonth)")
        continue
      }
      let anchor = monthDate.monthAnchor
      anchors.append(anchor)
    }

    // Check if cache is still valid (look up by anchor, not offset)
    if Date().timeIntervalSince(lastCacheUpdate) < cacheValidityDuration {
      let cachedData = anchors.compactMap { monthlyDataCache[$0] }
      if cachedData.count == anchors.count {
        return cachedData
      }
    }

    let allTransactions = fetchAllTransactionsIncludingStatements()

    let budgetsByAnchor = budgetRepo.fetchBudgets()
      .reduce(into: [:]) { acc, entry in
        acc[entry.monthDate] = entry.amount
      }

    // Calculate running balance
    var runningBalance = [Int: Int]()
    var previousAvailable = UIDUserDefaultsManager.shared.getCurrentUserBalanceOffset()

    let monthlyData = anchors.map { anchor in
      // Reconstruct date using the same method as monthAnchor calculation
      // This ensures timezone consistency
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone.current

      // Convert anchor back to date components
      // The anchor is the timestamp of the first day of the month
      let anchorDate = Date(timeIntervalSince1970: TimeInterval(anchor))
      let components = calendar.dateComponents([.year, .month], from: anchorDate)

      // Create a proper date in the user's timezone
      guard let date = calendar.date(from: components) else {
        logError("Failed to reconstruct date from anchor: \(anchor), components: \(components)")
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

      // Get transactions for this month using DYNAMIC month anchor calculation
      // This fixes the timezone issue by calculating month anchors on-the-fly
      let transactionsForMonth = allTransactions.filter { transaction in
        let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
        let transactionMonthAnchor = transactionDate.monthAnchor
        return transactionMonthAnchor == anchor
      }

      // Exclude credit card transactions from balance (they go to the statement instead)
      let cashTransactions = transactionsForMonth.filter { tx in
        tx.creditCardId == nil || tx.isCreditCardStatement == true
      }
      let expense = cashTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
      let income = cashTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
      let budgetLimit = budgetsByAnchor[anchor]

      // usedValue counts individual CC transactions in the month they were created
      // (matching how budget allocations track spending). Statement synthetics are
      // excluded here — they only affect balance, not "used" budget.
      let usedTransactions = transactionsForMonth.filter { tx in
        tx.isCreditCardStatement != true
      }
      let usedValue = usedTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }

      let net = income - expense
      let available = previousAvailable + net

      // Calculate current balance (balance up to current date within the month)
      let currentBalance = calculateCurrentBalanceForMonth(
        anchor: anchor, previousBalance: previousAvailable, transactions: allTransactions)

      let monthData = MonthBudgetCardType(
        date: date,
        month: localizedMonth,
        usedValue: usedValue,
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
      .sorted { $0.date != $1.date ? $0.date > $1.date : ($0.id ?? 0) > ($1.id ?? 0) }
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
      .sorted { $0.date != $1.date ? $0.date > $1.date : ($0.id ?? 0) > ($1.id ?? 0) }
  }

  // MARK: - Balance Calculations

  /// Calculate the balance up to the current date within a specific month
  func calculateCurrentBalanceForMonth(anchor: Int, previousBalance: Int, transactions: [Transaction]? = nil) -> Int {
    let allTransactions = transactions ?? fetchAllTransactionsIncludingStatements()

    let today = Date()
    let monthDate = Date(timeIntervalSince1970: TimeInterval(anchor))

    // Get transactions for this month
    let transactionsInMonth = allTransactions.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      let transactionMonthAnchor = transactionDate.monthAnchor
      return transactionMonthAnchor == anchor
    }

    // Check if this month is in the past, current, or future
    let isCurrentMonth = calendar.isDate(monthDate, equalTo: today, toGranularity: .month)
    let isPastMonth = monthDate < today && !isCurrentMonth

    // Exclude credit card transactions from balance
    let cashTransactionsInMonth = transactionsInMonth.filter { tx in
      tx.creditCardId == nil || tx.isCreditCardStatement == true
    }

    if isPastMonth {
      // For past months, current balance = final balance (all transactions)
      let netForMonth = cashTransactionsInMonth.reduce(0) { result, transaction in
        transaction.type == .income ? result + transaction.amount : result - transaction.amount
      }
      return previousBalance + netForMonth
    }

    if !isCurrentMonth {
      // For future months, no transactions have happened yet
      return previousBalance
    }

    // For current month, calculate balance up to today
    let todayComponents = calendar.dateComponents([.year, .month, .day], from: today)
    let todayStart = calendar.date(from: todayComponents) ?? today

    // Filter transactions up to and including today (excluding CC transactions)
    let transactionsUpToToday = cashTransactionsInMonth.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      let transactionComponents = calendar.dateComponents(
        [.year, .month, .day], from: transactionDate)
      let transactionDateOnly = calendar.date(from: transactionComponents) ?? transactionDate
      return transactionDateOnly <= todayStart
    }

    // Calculate net change from transactions up to today
    let netUpToToday = transactionsUpToToday.reduce(0) { result, transaction in
      transaction.type == .income ? result + transaction.amount : result - transaction.amount
    }

    return previousBalance + netUpToToday
  }

  func calculateCurrentBalance(for monthAnchor: Int) -> Int {
    let allTransactions = fetchAllTransactionsIncludingStatements()
    let today = Date()
    let monthDate = Date(timeIntervalSince1970: TimeInterval(monthAnchor))

    // Get all transactions up to the current month using dynamic month anchor calculation
    // Exclude credit card transactions from balance
    let relevantTransactions = allTransactions.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      let transactionMonthAnchor = transactionDate.monthAnchor
      return transactionMonthAnchor <= monthAnchor
        && (transaction.creditCardId == nil || transaction.isCreditCardStatement == true)
    }

    // Calculate running balance
    var balance = UIDUserDefaultsManager.shared.getCurrentUserBalanceOffset()
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
    let offset = monthOffsetFromAnchor(monthAnchor)
    let monthlyData = calculateMonthlyData(for: offset...offset)
    return monthlyData.first?.currentBalance
  }

  /// Get the final balance for a specific month (end-of-month balance)
  func getFinalBalance(for monthAnchor: Int) -> Int? {
    let offset = monthOffsetFromAnchor(monthAnchor)
    let monthlyData = calculateMonthlyData(for: offset...offset)
    return monthlyData.first?.finalBalance
  }

  /// Get monthly data for a specific month anchor
  func getMonthlyData(for monthAnchor: Int) -> MonthBudgetCardType? {
    let offset = monthOffsetFromAnchor(monthAnchor)
    let monthlyData = calculateMonthlyData(for: offset...offset)
    return monthlyData.first
  }

  /// Convert a month anchor to an offset from the current month
  func monthOffsetFromAnchor(_ anchor: Int) -> Int {
    let anchorDate = Date(timeIntervalSince1970: TimeInterval(anchor))
    let anchorComponents = calendar.dateComponents([.year, .month], from: anchorDate)
    let currentComponents = calendar.dateComponents([.year, .month], from: Date())

    guard let anchorYear = anchorComponents.year, let anchorMonth = anchorComponents.month,
      let currentYear = currentComponents.year, let currentMonth = currentComponents.month
    else {
      return 0
    }

    return (anchorYear - currentYear) * 12 + (anchorMonth - currentMonth)
  }

  /// Refresh the current balance for the current month (useful after transaction changes)
  func refreshCurrentMonthBalance() {
    let today = Date()
    let currentMonthAnchor = today.monthAnchor

    // Invalidate cache for current month only
    monthlyDataCache.removeValue(forKey: currentMonthAnchor)
    cachedAllTransactions = nil

    // Also invalidate the last cache update time to force fresh calculation
    lastCacheUpdate = Date.distantPast
  }

  /// Force refresh current month balance with detailed logging
  func forceRefreshCurrentMonthBalance() {
    // Clear all cache to ensure fresh calculation
    monthlyDataCache.removeAll()
    cachedAllTransactions = nil
    lastCacheUpdate = Date.distantPast

    // Force recalculate current month (offset 0 = current month)
    _ = calculateMonthlyData(for: 0...0)
  }

  /// Force refresh all balance calculations (useful after fixing date comparison issues)
  func forceRefreshAllBalances() {
    // Clear all cache
    monthlyDataCache.removeAll()
    cachedAllTransactions = nil
    lastCacheUpdate = Date.distantPast

    // Force recalculate a range of months to ensure fresh data
    // Use offsets: -2 (2 months ago) to +1 (next month)
    _ = calculateMonthlyData(for: -2...1)
  }

  // MARK: - Daily Balance Calculations

  /// Calculate balance for a specific day within a month.
  /// Uses previousMonthBalance + net of this month's cash transactions up to the target day.
  /// This matches the same accumulation logic used by calculateMonthlyData.
  func calculateBalanceForDay(day: Int, monthAnchor: Int, previousMonthBalance: Int, transactions: [Transaction]? = nil) -> Int {
    let allTransactions = transactions ?? fetchAllTransactionsIncludingStatements()
    return computeDayBalance(
      day: day, monthAnchor: monthAnchor, previousMonthBalance: previousMonthBalance,
      transactions: allTransactions)
  }

  /// Calculate balance for a specific day within a month — group context.
  /// Uses previousMonthBalance + net of this month's cash transactions up to the target day.
  func calculateBalanceForDayForGroup(day: Int, monthAnchor: Int, previousMonthBalance: Int, transactions: [Transaction]? = nil, groupId: String) -> Int {
    let allTransactions = transactions ?? fetchGroupTransactionsIncludingStatements(groupId: groupId)
    return computeDayBalance(
      day: day, monthAnchor: monthAnchor, previousMonthBalance: previousMonthBalance,
      transactions: allTransactions)
  }

  /// Shared logic: previousMonthBalance + net of cash transactions in the target month up to the target day.
  private func computeDayBalance(day: Int, monthAnchor: Int, previousMonthBalance: Int, transactions: [Transaction]) -> Int {
    let monthDate = Date(timeIntervalSince1970: TimeInterval(monthAnchor))

    var calendar = Calendar.current
    calendar.timeZone = TimeZone.current

    // Build target date from explicit components (safer than date(bySetting:))
    var targetComponents = calendar.dateComponents([.year, .month], from: monthDate)
    targetComponents.day = day
    guard let targetDate = calendar.date(from: targetComponents) else {
      return previousMonthBalance
    }

    let targetDateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
    let targetDateOnly = calendar.date(from: targetDateComponents) ?? targetDate

    // Filter to only this month's transactions, then to cash transactions up to the target day
    let cashTransactionsUpToDay = transactions.filter { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      guard transactionDate.monthAnchor == monthAnchor else { return false }

      let transactionComponents = calendar.dateComponents(
        [.year, .month, .day], from: transactionDate)
      let transactionDateOnly = calendar.date(from: transactionComponents) ?? transactionDate

      return transactionDateOnly <= targetDateOnly
        && (transaction.creditCardId == nil || transaction.isCreditCardStatement == true)
    }

    let net = cashTransactionsUpToDay.reduce(0) { result, transaction in
      transaction.type == .income ? result + transaction.amount : result - transaction.amount
    }

    return previousMonthBalance + net
  }


  // MARK: - Cache Management

  func invalidateCache() {
    monthlyDataCache.removeAll()
    cachedAllTransactions = nil
    lastCacheUpdate = Date.distantPast
  }

  /// Invalidate cache for specific month (useful for targeted updates)
  func invalidateCacheForMonth(_ monthAnchor: Int) {
    monthlyDataCache.removeValue(forKey: monthAnchor)
  }

  func clearCache() {
    monthlyDataCache.removeAll()
    cachedAllTransactions = nil
    lastCacheUpdate = Date.distantPast
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
        do {
          // Create new budget with new month anchor
          let newBudget = BudgetModel(monthDate: newMonthAnchor, amount: budget.amount)

          // Delete old budget
          try budgetRepo.delete(monthDate: budget.monthDate)

          // Insert new budget
          try budgetRepo.insert(budget: newBudget)

          migratedCount += 1
        } catch {
          logError("Failed to migrate budget for \(oldDate): \(error)")
        }
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
        // Since we can't directly update transactions, we'll need to recreate them
        // The actual migration will happen when transactions are recreated
        migratedCount += 1
      }
    }

    // Clear cache to ensure fresh data
    invalidateCache()
  }

  /// Clean up any duplicate transactions that might exist from before the fix
  func cleanupDuplicateTransactions() {
    let allTransactions = transactionRepo.fetchAllTransactions()

    // Group transactions by month for easier processing
    let transactionsByMonth = Dictionary(grouping: allTransactions) { transaction in
      let transactionDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
      return transactionDate.monthAnchor
    }

    for (monthAnchor, transactions) in transactionsByMonth {
      if transactions.count > 1 {
        // Find exact duplicates based on name, date, amount, and category
        _ = removeExactDuplicates(from: transactions, monthAnchor: monthAnchor)
      }
    }
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
        // Remove all instances for the same month (keep the parent)
        for instance in duplicateInstances {
          if let instanceId = instance.id {
            do {
              try transactionRepo.delete(id: instanceId)
              duplicatesRemoved += 1
            } catch {
              logError("Failed to delete recurring duplicate: \(error)")
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
        let duplicatesToRemove = Array(sortedGroup.dropFirst())

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
                } catch {
                  logError("Failed to delete instance: \(error)")
                }
              }
            }

            // Then remove the duplicate parent
            do {
              try transactionRepo.delete(id: duplicateParentId)
              duplicatesRemoved += 1
            } catch {
              logError("Failed to delete duplicate parent: \(error)")
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
        let duplicatesToRemove = Array(sortedGroup.dropFirst())

        // Remove duplicates
        for duplicate in duplicatesToRemove {
          if let duplicateId = duplicate.id {
            do {
              try transactionRepo.delete(id: duplicateId)
              duplicatesRemoved += 1
            } catch {
              logError("Failed to delete duplicate: \(error)")
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

}
