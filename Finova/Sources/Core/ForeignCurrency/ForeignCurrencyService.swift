//
//  ForeignCurrencyService.swift
//  Finova
//
//  Keeps foreign-currency income converted: live before payday, locked on payday.
//  See docs/fx-salary-plan.md §3.
//

import Foundation

extension Notification.Name {
  /// Posted on the main thread when a refresh moved the converted value of live foreign income.
  /// `userInfo["message"]` is the one-line hint the dashboard shows.
  static let fxRateUpdated = Notification.Name("fxRateUpdated")
}

/// What the lock/refresh pass decided for one row. Pure: no database, no network.
enum FxRowPlanner {
  struct Row: Equatable {
    let id: Int
    let dateTimestamp: Int
    let amount: Int
    let foreign: ForeignAmount
  }

  struct Change: Equatable {
    let id: Int
    let foreign: ForeignAmount?
    let amount: Int
    /// True when this change only follows a new live rate (drives the "rate updated" hint).
    let isLiveMove: Bool
  }

  static func plan(
    row: Row, appCurrency: String, today: String, latest: FxQuote?, historical: FxQuote?,
    now: Int, calendar: Calendar = .current
  ) -> Change? {
    let fx = row.foreign
    // The app currency changed to the income's own currency: it is an ordinary row now.
    if fx.currency == appCurrency {
      return Change(id: row.id, foreign: nil, amount: fx.amount, isLiveMove: false)
    }
    guard !fx.isLocked else { return nil }  // Frozen forever.

    let payday = FxDay.string(
      from: Date(timeIntervalSince1970: TimeInterval(row.dateTimestamp)), calendar: calendar)
    switch FxLockRule.decide(payday: payday, today: today, answer: historical) {
    case .lock(let quote):
      var locked = fx
      locked.rateMicros = quote.rateMicros
      // A market quote keeps its exact time ("20/11/2026 15:18"); an ECB rate is a whole day.
      locked.rateDate = quote.quotedAt ?? FxDay.epoch(of: quote.date, calendar: calendar)
      locked.rateSource = quote.source.rawValue
      locked.lockedAt = now
      let amount = FxConversion.convert(
        fxAmount: fx.amount, currency: fx.currency, rateMicros: quote.rateMicros,
        appCurrency: appCurrency, feeBps: fx.feeBps, spreadMicros: fx.spreadMicros)
      return Change(id: row.id, foreign: locked, amount: amount, isLiveMove: false)
    case .live, .wait:
      guard let latest = latest else { return nil }  // Offline: keep the last known amount.
      let amount = FxConversion.convert(
        fxAmount: fx.amount, currency: fx.currency, rateMicros: latest.rateMicros,
        appCurrency: appCurrency, feeBps: fx.feeBps, spreadMicros: fx.spreadMicros)
      guard amount != row.amount else { return nil }  // Write only rows that really change.
      return Change(id: row.id, foreign: fx, amount: amount, isLiveMove: true)
    }
  }
}

/// Editing a foreign income (docs/fx-salary-plan.md §3, "Editing a locked income"). Pure.
enum FxEditPlanner {
  struct Result: Equatable {
    let foreign: ForeignAmount?
    let amount: Int
  }

  /// - Parameters:
  ///   - old: the row's conversion before the edit (nil for an ordinary row).
  ///   - oldDate / newDate: epoch seconds of the row's date before and after.
  ///   - currency: the currency picked in the form (the app currency means "no conversion").
  ///   - typedAmount: the amount typed in the form, in `currency`'s minor units.
  ///   - liveRateMicros: newest cached rate for `currency`, or a rate typed by hand.
  ///   - feeBps: an old row's fee, kept as it was (new rows use the provider difference instead).
  ///   - spreadMicros: the provider difference typed in the form (nil or 0 = none).
  /// - Returns: nil when a foreign currency has no rate at all (the caller must ask for one).
  static func apply(
    old: ForeignAmount?, oldDate: Int, newDate: Int, currency: String, typedAmount: Int,
    appCurrency: String, liveRateMicros: Int?, liveRateDate: Int?, feeBps: Int? = nil,
    spreadMicros: Int? = nil, calendar: Calendar = .current
  ) -> Result? {
    let fee = (feeBps ?? 0) > 0 ? feeBps : nil
    let spread = (spreadMicros ?? 0) > 0 ? spreadMicros : nil
    // Set back to the app currency: an ordinary row; `amount` is what was typed.
    if currency == appCurrency { return Result(foreign: nil, amount: typedAmount) }

    if let old = old, old.currency == currency, old.isLocked {
      let sameDay =
        FxDay.string(from: Date(timeIntervalSince1970: TimeInterval(oldDate)), calendar: calendar)
        == FxDay.string(from: Date(timeIntervalSince1970: TimeInterval(newDate)), calendar: calendar)
      if sameDay, let locked = old.rateMicros {
        // New foreign amount × the LOCKED rate. The rate stays. An "amount received" row's rate is
        // already what arrived (every fee and difference inside), so nothing is taken off again.
        let keptFee = old.isReceivedAmount ? nil : fee
        let keptSpread = old.isReceivedAmount ? nil : spread
        var kept = old
        kept.amount = typedAmount
        kept.feeBps = keptFee
        kept.spreadMicros = keptSpread
        return Result(
          foreign: kept,
          amount: FxConversion.convert(
            fxAmount: typedAmount, currency: currency, rateMicros: locked, appCurrency: appCurrency,
            feeBps: keptFee, spreadMicros: keptSpread))
      }
      // Moved to another day: unlock. The next pass locks it again with that day's rate (past)
      // or keeps it live (future). The entry rate stays: only a new currency resets it.
      guard let live = liveRateMicros ?? old.rateMicros else { return nil }
      let unlocked = ForeignAmount(
        currency: currency, amount: typedAmount,
        entryRateMicros: old.entryRateMicros, entryRateDate: old.entryRateDate, feeBps: fee,
        spreadMicros: spread)
      return Result(
        foreign: unlocked,
        amount: FxConversion.convert(
          fxAmount: typedAmount, currency: currency, rateMicros: live, appCurrency: appCurrency,
          feeBps: fee, spreadMicros: spread))
    }

    guard let live = liveRateMicros else { return nil }
    let keepsEntry = old?.currency == currency
    let foreign = ForeignAmount(
      currency: currency, amount: typedAmount,
      entryRateMicros: keepsEntry ? (old?.entryRateMicros ?? live) : live,
      entryRateDate: keepsEntry ? (old?.entryRateDate ?? liveRateDate) : liveRateDate,
      feeBps: fee, spreadMicros: spread)
    return Result(
      foreign: foreign,
      amount: FxConversion.convert(
        fxAmount: typedAmount, currency: currency, rateMicros: live, appCurrency: appCurrency,
        feeBps: fee, spreadMicros: spread))
  }

  /// "Enter amount received": allowed only after the lock. Stores the implied rate; the badge then
  /// compares the entry rate with it, so it includes the bank's spread, IOF and fees.
  static func received(old: ForeignAmount, typedAmount: Int, appCurrency: String) -> Result? {
    guard old.isLocked, typedAmount > 0,
      let implied = FxMath.impliedRateMicros(
        typedAmount: typedAmount, fxAmount: old.amount,
        fxDigits: CurrencyUtils.fractionDigits(for: old.currency),
        baseDigits: CurrencyUtils.fractionDigits(for: appCurrency))
    else { return nil }
    var updated = old
    updated.rateMicros = implied
    updated.isReceivedAmount = true
    return Result(foreign: updated, amount: typedAmount)
  }
}

enum FxConversion {
  static func convert(
    fxAmount: Int, currency: String, rateMicros: Int, appCurrency: String, feeBps: Int? = nil,
    spreadMicros: Int? = nil
  ) -> Int {
    FxMath.convert(
      fxAmount: fxAmount, rateMicros: rateMicros,
      fxDigits: CurrencyUtils.fractionDigits(for: currency),
      baseDigits: CurrencyUtils.fractionDigits(for: appCurrency), feeBps: feeBps ?? 0,
      spreadMicros: spreadMicros ?? 0)
  }
}

/// The IO side: rate cache, network, database writes, notifications.
final class ForeignCurrencyService {
  static let shared = ForeignCurrencyService()

  /// The live market quote is refreshed at most this often (and on every return to the
  /// foreground). Before payday the converted value follows the market; the saved quote is the
  /// offline backup.
  static let latestMaxAge: TimeInterval = 5 * 60
  /// The "Rate updated" hint shows at most once an hour: the market moves all day.
  static let rateHintMinInterval: TimeInterval = 60 * 60
  private static let lastRateHintKey = "fxLastRateHintAt"

  /// Currencies offered first in the picker. The full list is the provider's (`allCurrencies`).
  static let commonCurrencies = ["USD", "EUR", "GBP"]
  /// Frankfurter's ECB set (the fallback must cover every offered pair). Built in, so the picker
  /// works offline.
  static let allCurrencies = [
    "AUD", "BGN", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD", "HUF", "IDR",
    "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK",
    "SGD", "THB", "TRY", "USD", "ZAR",
  ]

  private let provider: FxRateProvider
  private let db: DBHelper
  private let now: () -> Date
  private let calendar: Calendar
  private var isRunning = false

  init(
    provider: FxRateProvider = FallbackRateProvider(
      primary: AwesomeRateProvider(), fallback: FrankfurterRateProvider()),
    db: DBHelper = .shared,
    now: @escaping () -> Date = Date.init, calendar: Calendar = .current
  ) {
    self.provider = provider
    self.db = db
    self.now = now
    self.calendar = calendar
  }

  var appCurrency: String { AppConfig.currencyCode }

  /// Whether the app currency is one the provider can convert into.
  var isAvailable: Bool { Self.allCurrencies.contains(appCurrency) }

  // MARK: Cache (synchronous)

  func cachedLatest(for currency: String) -> FxQuote? {
    db.cachedFxRate(base: currency, quote: appCurrency, requested: "latest")?.quote
  }

  // MARK: Network

  /// Newest rate for `currency` → app currency. Uses the cache unless it is older than
  /// `latestMaxAge` (5 minutes). Offline, it returns the saved quote however old: good enough to
  /// show a live value, never good enough to lock (see `lockableLatest`).
  @discardableResult
  func latest(for currency: String, force: Bool = false) async -> FxQuote? {
    let base = currency, quote = appCurrency
    guard base != quote else { return nil }
    if !force, let cached = db.cachedFxRate(base: base, quote: quote, requested: "latest"),
      now().timeIntervalSince1970 - TimeInterval(cached.fetchedAt) < Self.latestMaxAge
    {
      return cached.quote
    }
    do {
      let fresh = try await provider.latest(base: base, quote: quote)
      db.storeFxRate(fresh, requested: "latest", fetchedAt: Int(now().timeIntervalSince1970))
      return fresh
    } catch {
      logWarning("[FX] latest \(base)->\(quote) failed: \(error)")
      return db.cachedFxRate(base: base, quote: quote, requested: "latest")?.quote
    }
  }

  /// A live quote that may freeze a payday row: fetched (or confirmed) within `latestMaxAge` and
  /// dated `payday` itself. A stale offline quote, or yesterday's ECB rate given by the fallback
  /// before the noon publication, returns nil, so the row stays live and locks on a later pass.
  func lockableLatest(for currency: String, payday: String) -> FxQuote? {
    guard let cached = db.cachedFxRate(base: currency, quote: appCurrency, requested: "latest"),
      now().timeIntervalSince1970 - TimeInterval(cached.fetchedAt) < Self.latestMaxAge,
      cached.quote.date == payday
    else { return nil }
    return cached.quote
  }

  /// The closing rate of `day` (the newest quote on or before it). Only past days are cached:
  /// today's "close" keeps moving. Cached under "close:<day>": the earlier build stored ECB
  /// answers under the bare day, and those must not be reused now that the market rate rules.
  func historical(for currency: String, day: String) async -> FxQuote? {
    let base = currency, quote = appCurrency
    let key = "close:" + day
    if let cached = db.cachedFxRate(base: base, quote: quote, requested: key) {
      return cached.quote
    }
    do {
      let answer = try await provider.historical(base: base, quote: quote, day: day)
      let today = FxDay.string(from: now(), calendar: calendar)
      if day < today {
        db.storeFxRate(answer, requested: key, fetchedAt: Int(now().timeIntervalSince1970))
      }
      return answer
    } catch {
      logWarning("[FX] historical \(base)->\(quote) \(day) failed: \(error)")
      return nil
    }
  }

  // MARK: The pass

  /// Locks every due row and moves every live row to the newest rate. Runs at launch, on return to
  /// the foreground, and after a foreign income is saved.
  func refresh(force: Bool = false) async {
    let rows: [FxRowPlanner.Row] = await MainActor.run {
      guard !isRunning else { return [] }
      isRunning = true
      return pendingRows()
    }
    guard !rows.isEmpty else {
      await MainActor.run { isRunning = false }
      return
    }
    defer { Task { @MainActor in self.isRunning = false } }

    let today = FxDay.string(from: now(), calendar: calendar)
    let app = appCurrency
    var latestByCurrency: [String: FxQuote] = [:]
    for currency in Set(rows.map { $0.foreign.currency }) where currency != app {
      if let quote = await latest(for: currency, force: force) { latestByCurrency[currency] = quote }
    }
    var historicalByKey: [String: FxQuote] = [:]
    for row in rows where row.foreign.currency != app {
      let payday = FxDay.string(
        from: Date(timeIntervalSince1970: TimeInterval(row.dateTimestamp)), calendar: calendar)
      guard payday <= today else { continue }
      let key = "\(row.foreign.currency)|\(payday)"
      guard historicalByKey[key] == nil else { continue }
      if payday == today {
        // Payday, app open: lock with the live market rate right now, but only a fresh one dated
        // today. Otherwise nil: the row stays live and locks on the next pass with a real rate.
        historicalByKey[key] = lockableLatest(for: row.foreign.currency, payday: payday)
      } else if let answer = await historical(for: row.foreign.currency, day: payday) {
        // The app was closed on payday: that day's closing rate.
        historicalByKey[key] = answer
      }
    }

    let stamp = Int(now().timeIntervalSince1970)
    let changes = rows.compactMap { row -> FxRowPlanner.Change? in
      let payday = FxDay.string(
        from: Date(timeIntervalSince1970: TimeInterval(row.dateTimestamp)), calendar: calendar)
      return FxRowPlanner.plan(
        row: row, appCurrency: app, today: today,
        latest: latestByCurrency[row.foreign.currency],
        historical: historicalByKey["\(row.foreign.currency)|\(payday)"],
        now: stamp, calendar: calendar)
    }
    guard !changes.isEmpty else { return }
    await MainActor.run { self.apply(changes, latest: latestByCurrency) }
  }

  /// Foreign rows the pass may still change: live ones, plus any whose currency now equals the app's.
  private func pendingRows() -> [FxRowPlanner.Row] {
    let app = appCurrency
    let transactions = TransactionRepository().fetchAllTransactions()
    return transactions.compactMap { tx in
      guard let id = tx.id, let fx = tx.foreign, !fx.isLocked || fx.currency == app else {
        return nil
      }
      return FxRowPlanner.Row(id: id, dateTimestamp: tx.dateTimestamp, amount: tx.amount, foreign: fx)
    }
  }

  @MainActor
  private func apply(_ changes: [FxRowPlanner.Change], latest: [String: FxQuote]) {
    var written: [Int] = []
    try? db.inTransaction {
      for change in changes
      where db.updateForeign(transactionId: change.id, foreign: change.foreign, amount: change.amount) {
        written.append(change.id)
      }
    }
    guard !written.isEmpty else { return }
    TransactionRepository.invalidateCache()
    reconcileNotifications(for: written)
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)

    let moved = changes.filter { $0.isLiveMove && written.contains($0.id) }
    let lastHint = UserDefaults.standard.double(forKey: Self.lastRateHintKey)
    if let currency = moved.first?.foreign?.currency, let quote = latest[currency],
      now().timeIntervalSince1970 - lastHint >= Self.rateHintMinInterval
    {
      UserDefaults.standard.set(now().timeIntervalSince1970, forKey: Self.lastRateHintKey)
      NotificationCenter.default.post(
        name: .fxRateUpdated, object: nil,
        userInfo: ["message": Self.rateUpdatedMessage(quote)])
    }
  }

  /// One reconcile per series, not one per row: recurring reminders are month-bucketed per parent,
  /// and per-row cancel calls block bulk changes.
  func reconcileNotifications(for ids: [Int]) {
    let repo = TransactionRepository()
    var seenParents = Set<Int>()
    for id in ids {
      if let parent = repo.fetchTransaction(byId: id)?.parentTransactionId {
        guard seenParents.insert(parent).inserted else { continue }
      }
      repo.reconcileNotifications(forLocalId: id)
    }
  }

  // MARK: Writes from the UI

  /// Saves an edit's conversion on one row and reconciles its notification.
  @MainActor
  func save(_ result: FxEditPlanner.Result, transactionId: Int) {
    db.updateForeign(transactionId: transactionId, foreign: result.foreign, amount: result.amount)
    TransactionRepository.invalidateCache()
    reconcileNotifications(for: [transactionId])
    NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
  }

  // MARK: Text

  static func rateUpdatedMessage(_ quote: FxQuote) -> String {
    String(
      format: "fx.rateUpdated".localized,
      rateText(rateMicros: quote.rateMicros, currency: quote.base, appCurrency: quote.quote))
  }

  /// `US$ 1 = R$ 5,7651`
  static func rateText(rateMicros: Int, currency: String, appCurrency: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = .autoupdatingCurrent
    formatter.currencyCode = appCurrency
    formatter.minimumFractionDigits = 4
    formatter.maximumFractionDigits = 4
    let rate = Decimal(rateMicros) / Decimal(FxMath.microsPerUnit)
    let right = formatter.string(from: NSDecimalNumber(decimal: rate)) ?? "\(rate)"
    return "\(symbol(for: currency)) 1 = \(right)"
  }

  static func symbol(for currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = .autoupdatingCurrent
    formatter.currencyCode = currency
    return formatter.currencySymbol ?? currency
  }

  /// `US$ 5,000.00`: the phone's symbol for the currency, the digits in the money's own style
  /// (1,000.00), so a dollar amount never reads like a reais one next to it.
  static func format(amountMinor: Int, currency: String) -> String {
    let digits = CurrencyUtils.fractionDigits(for: currency)
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.usesGroupingSeparator = true
    formatter.groupingSeparator = ","
    formatter.decimalSeparator = "."
    formatter.groupingSize = 3
    formatter.minimumFractionDigits = digits
    formatter.maximumFractionDigits = digits
    let value = NSDecimalNumber(value: amountMinor).dividing(
      by: NSDecimalNumber(decimal: pow(10, digits)))
    return "\(symbol(for: currency)) " + (formatter.string(from: value) ?? "\(value)")
  }

  /// "Market rate · 18:59" for a live quote, "ECB, 26/11" for the fallback.
  static func sourceText(_ quote: FxQuote) -> String {
    if quote.source == .market, let at = quote.quotedAt {
      return "fx.source.market".localized(shortTime(epoch: at))
    }
    return "fx.hint.ecb".localized(FxDay.epoch(of: quote.date).map { shortDate(epoch: $0) } ?? quote.date)
  }

  static func shortTime(epoch: Int) -> String {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
  }

  /// Short date for rate labels: 26/11.
  static func shortDate(epoch: Int) -> String {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.setLocalizedDateFormatFromTemplate("ddMM")
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
  }
}
