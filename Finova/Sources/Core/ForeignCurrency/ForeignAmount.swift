//
//  ForeignAmount.swift
//  Finova
//
//  Foreign-currency income (1.7.0). See docs/fx-salary-plan.md.
//

import Foundation

/// Where a transaction's `amount` came from when it was received in another currency.
///
/// `Transaction.amount` stays in the app currency, always, so every ledger, budget and balance reader
/// is untouched. This value only describes the conversion: the money as received, the rate used, and
/// whether that rate is still live (follows the market) or locked (frozen on payday, forever).
struct ForeignAmount: Codable, Equatable {
  /// ISO 4217 code of the money received, e.g. "USD".
  var currency: String
  /// Amount in that currency, minor units (US$ 5,000.00 → 500000).
  var amount: Int
  /// Locked rate × 1,000,000. `nil` while live.
  var rateMicros: Int?
  /// Provider date of the locked rate, epoch seconds at local midnight. `nil` while live.
  var rateDate: Int?
  /// When the rate was frozen, epoch seconds. Not nil = locked forever.
  var lockedAt: Int?
  /// Rate when the income was added (the % badge baseline), × 1,000,000.
  var entryRateMicros: Int?
  /// Provider date of the entry rate, epoch seconds at local midnight.
  var entryRateDate: Int?
  /// The user typed the R$ actually received after the lock ("Enter amount received").
  /// Then `rateMicros` holds the implied rate and Details says "Amount received".
  var isReceivedAmount: Bool = false
  /// "market" or "ecb": where the locked rate came from (`FxSource.rawValue`). For a market rate
  /// `rateDate` is the exact quote time, not midnight.
  var rateSource: String? = nil
  /// Optional fee the user expects on the conversion, in basis points (20 = 0.20%). Lowers the
  /// converted amount; never touches the rates, so the % badge ignores it. Ignored once the user
  /// types the amount received (that number already includes every fee).
  var feeBps: Int? = nil

  var isLocked: Bool { lockedAt != nil }

  init(
    currency: String, amount: Int, rateMicros: Int? = nil, rateDate: Int? = nil,
    lockedAt: Int? = nil, entryRateMicros: Int? = nil, entryRateDate: Int? = nil,
    isReceivedAmount: Bool = false, rateSource: String? = nil, feeBps: Int? = nil
  ) {
    self.currency = currency
    self.amount = amount
    self.rateMicros = rateMicros
    self.rateDate = rateDate
    self.lockedAt = lockedAt
    self.entryRateMicros = entryRateMicros
    self.entryRateDate = entryRateDate
    self.isReceivedAmount = isReceivedAmount
    self.rateSource = rateSource
    self.feeBps = feeBps
  }

  /// A copy for a NEW occurrence of a recurring series: same money and the series' entry rate,
  /// but never the template's lock. Copying a lock would freeze future months at an old rate.
  func unlockedCopy() -> ForeignAmount {
    ForeignAmount(
      currency: currency, amount: amount,
      entryRateMicros: entryRateMicros, entryRateDate: entryRateDate, feeBps: feeBps)
  }
}

/// The conversion and % badge math. Pure, integer/Decimal only, the same on iOS and Android.
enum FxMath {
  static let microsPerUnit: Int = 1_000_000

  /// `amount = round_half_even(fxAmount × rate × (1 − fee) × 10^(baseDigits − fxDigits))`, rate in
  /// micros, fee in basis points (20 = 0.20%).
  static func convert(
    fxAmount: Int, rateMicros: Int, fxDigits: Int, baseDigits: Int, feeBps: Int = 0
  ) -> Int {
    var value = Decimal(fxAmount) * Decimal(rateMicros) / Decimal(microsPerUnit)
    value *= pow10(baseDigits - fxDigits)
    let fee = min(max(feeBps, 0), 9_999)
    if fee > 0 { value = value * Decimal(10_000 - fee) / Decimal(10_000) }
    return roundHalfEven(value)
  }

  /// "0,20" / "0.2" / "" → basis points (20). Nil for text that is not a percent from 0 to 99.99.
  static func feeBps(fromText text: String) -> Int? {
    let cleaned = text.trimmingCharacters(in: .whitespaces)
      .replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: ".")
    if cleaned.isEmpty { return 0 }
    guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
      value >= 0, value < 100
    else { return nil }
    return roundHalfEven(value * 100)
  }

  /// 20 → "0.20" (no % sign), always a point, like the badge.
  static func feeText(bps: Int) -> String {
    String(format: "%d.%02d", bps / 100, bps % 100)
  }

  /// The rate implied by an amount typed by hand: `typed / fxAmount`, in micros.
  static func impliedRateMicros(
    typedAmount: Int, fxAmount: Int, fxDigits: Int, baseDigits: Int
  ) -> Int? {
    guard fxAmount > 0, typedAmount > 0 else { return nil }
    var value = Decimal(typedAmount) / Decimal(fxAmount) * Decimal(microsPerUnit)
    value *= pow10(fxDigits - baseDigits)
    return roundHalfEven(value)
  }

  /// A decimal rate (as the provider sends it, e.g. 5.7651) to micros.
  static func micros(fromRate rate: Decimal) -> Int {
    roundHalfEven(rate * Decimal(microsPerUnit))
  }

  /// Change from `baseline` to `current` in tenths of a percent, rounded half away from zero.
  /// 5.0000 → 5.4000 = 80 (+8.0%). Integers only, so both platforms agree to the digit.
  static func changeTenths(baselineMicros: Int, currentMicros: Int) -> Int? {
    guard baselineMicros > 0, currentMicros > 0 else { return nil }
    let n = (currentMicros - baselineMicros) * 1000
    let d = baselineMicros
    return n >= 0 ? (2 * n + d) / (2 * d) : -((-2 * n + d) / (2 * d))
  }

  /// `+8.0%`, `−2.3%`, `0.0%` (never `−0.0%`), with a real minus. Always a point, like the
  /// Stocks app and like compact amounts in this app ("R$28.3k"), whatever the phone's format.
  static func formatChange(tenths: Int) -> String {
    let magnitude = abs(tenths)
    let body = "\(magnitude / 10).\(magnitude % 10)%"
    if tenths > 0 { return "+" + body }
    if tenths < 0 { return "\u{2212}" + body }
    return body
  }

  private static func pow10(_ exponent: Int) -> Decimal {
    exponent >= 0 ? pow(Decimal(10), exponent) : 1 / pow(Decimal(10), -exponent)
  }

  static func roundHalfEven(_ value: Decimal) -> Int {
    var input = value
    var result = Decimal()
    NSDecimalRound(&result, &input, 0, .bankers)
    return NSDecimalNumber(decimal: result).intValue
  }
}

/// Good or bad for the user, not up or down. Income going up is good; an expense going up is bad.
/// v1 only has income; the expense side is here so the rule needs no change later.
enum FxBadgeTone: Equatable {
  case good, bad, neutral

  static func tone(isIncome: Bool, changeTenths: Int) -> FxBadgeTone {
    if changeTenths == 0 { return .neutral }
    let up = changeTenths > 0
    return up == isIncome ? .good : .bad
  }
}

extension ForeignAmount {
  /// The rate the badge compares against the entry rate: the locked (or implied) rate after
  /// payday, the live rate before.
  func currentRateMicros(liveRateMicros: Int?) -> Int? {
    isLocked ? rateMicros : liveRateMicros
  }

  /// Badge value in tenths of a percent, or nil when there is no baseline or no rate.
  func changeTenths(liveRateMicros: Int?) -> Int? {
    guard let entry = entryRateMicros, let current = currentRateMicros(liveRateMicros: liveRateMicros)
    else { return nil }
    return FxMath.changeTenths(baselineMicros: entry, currentMicros: current)
  }
}
