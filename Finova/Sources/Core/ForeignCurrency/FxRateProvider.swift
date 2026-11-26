//
//  FxRateProvider.swift
//  Finova
//
//  Live rates come from AwesomeAPI (market rate, the same number iOS Stocks shows), with
//  Frankfurter (European Central Bank reference rates) as the fallback. Neither needs an API key;
//  only currency codes and dates are sent. See docs/fx-salary-plan.md §4.
//

import Foundation

/// One rate as the provider answered it. `date` is the provider's own date ("yyyy-MM-dd"), which can
/// be earlier than the date asked for (weekends, holidays, or before the day's publication).
struct FxQuote: Equatable {
  let base: String
  let quote: String
  let date: String
  let rateMicros: Int
  /// Where it came from. The UI says "Market rate · 18:59" or "ECB, 26/11".
  var source: FxSource = .ecb
  /// When the market quoted it, epoch seconds. Nil for ECB reference rates (one per day).
  var quotedAt: Int? = nil
}

enum FxSource: String, Equatable {
  /// Live market rate: AwesomeAPI's mid price, (bid + ask) / 2.
  case market
  /// European Central Bank daily reference rate (Frankfurter), the fallback.
  case ecb
}

protocol FxRateProvider {
  /// The newest published rate.
  func latest(base: String, quote: String) async throws -> FxQuote
  /// The last published rate on or before `day` ("yyyy-MM-dd").
  func historical(base: String, quote: String, day: String) async throws -> FxQuote
}

enum FxProviderError: Error, Equatable {
  case badResponse
  case missingRate
}

final class FrankfurterRateProvider: FxRateProvider {
  private let session: URLSession
  private let baseURL: URL

  init(
    session: URLSession = FrankfurterRateProvider.defaultSession,
    baseURL: URL = URL(string: "https://api.frankfurter.dev/v1/")!
  ) {
    self.session = session
    self.baseURL = baseURL
  }

  static let defaultSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 15
    return URLSession(configuration: config)
  }()

  func latest(base: String, quote: String) async throws -> FxQuote {
    try await fetch(path: "latest", base: base, quote: quote)
  }

  func historical(base: String, quote: String, day: String) async throws -> FxQuote {
    try await fetch(path: day, base: base, quote: quote)
  }

  private func fetch(path: String, base: String, quote: String) async throws -> FxQuote {
    var components = URLComponents(
      url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "base", value: base),
      URLQueryItem(name: "symbols", value: quote),
    ]
    let (data, response) = try await session.data(from: components.url!)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw FxProviderError.badResponse
    }
    return try Self.parse(data, base: base, quote: quote)
  }

  /// `{"amount":1.0,"base":"USD","date":"2026-11-20","rates":{"BRL":5.938}}`
  /// Parsed with `Decimal` from the raw text so 5.7651 never becomes 5.76509999.
  static func parse(_ data: Data, base: String, quote: String) throws -> FxQuote {
    guard let text = String(data: data, encoding: .utf8),
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let date = object["date"] as? String
    else { throw FxProviderError.badResponse }
    guard let rate = rawNumber(after: "\"\(quote)\"", in: text) else {
      throw FxProviderError.missingRate
    }
    return FxQuote(
      base: base, quote: quote, date: date, rateMicros: FxMath.micros(fromRate: rate), source: .ecb)
  }

  private static func rawNumber(after key: String, in text: String) -> Decimal? {
    guard let keyRange = text.range(of: key),
      let colon = text[keyRange.upperBound...].firstIndex(of: ":")
    else { return nil }
    let tail = text[text.index(after: colon)...].drop(while: { $0 == " " })
    let number = tail.prefix(while: { "0123456789.eE+-".contains($0) })
    return Decimal(string: String(number), locale: Locale(identifier: "en_US_POSIX"))
  }
}

/// The live market rate (AwesomeAPI): `bid` of the pair, updated every few minutes.
final class AwesomeRateProvider: FxRateProvider {
  private let session: URLSession
  private let baseURL: URL
  private let calendar: Calendar

  init(
    session: URLSession = FrankfurterRateProvider.defaultSession,
    baseURL: URL = URL(string: "https://economia.awesomeapi.com.br/json/")!,
    calendar: Calendar = .current
  ) {
    self.session = session
    self.baseURL = baseURL
    self.calendar = calendar
  }

  /// `GET /json/last/USD-BRL` → `{"USDBRL":{"bid":"5.6513","ask":"5.6518","timestamp":"1795728610",...}}`
  func latest(base: String, quote: String) async throws -> FxQuote {
    let url = baseURL.appendingPathComponent("last/\(base)-\(quote)")
    let data = try await get(url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let entry = object["\(base)\(quote)"] as? [String: Any]
    else { throw FxProviderError.missingRate }
    return try Self.quote(from: entry, base: base, quote: quote, calendar: calendar)
  }

  /// The day's closing rate: the newest quote on or before `day`. Asks for the week up to `day`,
  /// because a weekend or holiday has no quote of its own.
  func historical(base: String, quote: String, day: String) async throws -> FxQuote {
    guard let dayEpoch = FxDay.epoch(of: day, calendar: calendar) else {
      throw FxProviderError.badResponse
    }
    let dayDate = Date(timeIntervalSince1970: TimeInterval(dayEpoch))
    let start = calendar.date(byAdding: .day, value: -6, to: dayDate) ?? dayDate
    func compact(_ date: Date) -> String { FxDay.string(from: date, calendar: calendar).replacingOccurrences(of: "-", with: "") }
    var components = URLComponents(
      url: baseURL.appendingPathComponent("daily/\(base)-\(quote)/10"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "start_date", value: compact(start)),
      URLQueryItem(name: "end_date", value: compact(dayDate)),
    ]
    let data = try await get(components.url!)
    guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      throw FxProviderError.badResponse
    }
    let quotes = entries.compactMap { try? Self.quote(from: $0, base: base, quote: quote, calendar: calendar) }
      .filter { $0.date <= day }
    guard let newest = quotes.max(by: { ($0.quotedAt ?? 0) < ($1.quotedAt ?? 0) }) else {
      throw FxProviderError.missingRate
    }
    return newest
  }

  private func get(_ url: URL) async throws -> Data {
    let (data, response) = try await session.data(from: url)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw FxProviderError.badResponse
    }
    return data
  }

  /// Numbers arrive as strings ("5.6513"), so `Decimal` reads them exactly. The rate is the mid
  /// price, (bid + ask) / 2, which sits closer to what iOS Stocks shows than `bid` alone. Without
  /// an `ask` (the daily history sometimes omits it) `bid` is used.
  static func quote(from entry: [String: Any], base: String, quote: String, calendar: Calendar) throws -> FxQuote {
    let posix = Locale(identifier: "en_US_POSIX")
    guard let bidText = entry["bid"] as? String,
      let bid = Decimal(string: bidText, locale: posix), bid > 0,
      let stampText = entry["timestamp"] as? String, let stamp = Int(stampText)
    else { throw FxProviderError.missingRate }
    let ask = (entry["ask"] as? String).flatMap { Decimal(string: $0, locale: posix) }.flatMap { $0 > 0 ? $0 : nil }
    let mid = ask.map { (bid + $0) / 2 } ?? bid
    let day = FxDay.string(from: Date(timeIntervalSince1970: TimeInterval(stamp)), calendar: calendar)
    return FxQuote(
      base: base, quote: quote, date: day, rateMicros: FxMath.micros(fromRate: mid),
      source: .market, quotedAt: stamp)
  }
}

/// Tries the market first and falls back to the ECB, so the app never shows nothing.
final class FallbackRateProvider: FxRateProvider {
  private let primary: FxRateProvider
  private let fallback: FxRateProvider

  init(primary: FxRateProvider, fallback: FxRateProvider) {
    self.primary = primary
    self.fallback = fallback
  }

  func latest(base: String, quote: String) async throws -> FxQuote {
    do { return try await primary.latest(base: base, quote: quote) } catch {
      return try await fallback.latest(base: base, quote: quote)
    }
  }

  func historical(base: String, quote: String, day: String) async throws -> FxQuote {
    do { return try await primary.historical(base: base, quote: quote, day: day) } catch {
      return try await fallback.historical(base: base, quote: quote, day: day)
    }
  }
}

/// Calendar days as "yyyy-MM-dd" in the device's time zone. Payday and "today" are local days.
enum FxDay {
  static func string(from date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  /// Local midnight of a "yyyy-MM-dd" day, as epoch seconds.
  static func epoch(of day: String, calendar: Calendar = .current) -> Int? {
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    var c = DateComponents()
    c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
    return calendar.date(from: c).map { Int($0.timeIntervalSince1970) }
  }

  /// ECB publishes on weekdays only.
  static func isWeekday(_ day: String, calendar: Calendar = .current) -> Bool {
    guard let epoch = epoch(of: day, calendar: calendar) else { return false }
    let weekday = calendar.component(.weekday, from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    return weekday != 1 && weekday != 7
  }
}

/// The lock rule (docs/fx-salary-plan.md §3), as a pure function.
enum FxLockRule {
  enum Decision: Equatable {
    /// Payday has not come yet: keep following the live rate.
    case live
    /// No rate could be fetched (offline). Keep the row live and try again later.
    case wait
    /// Freeze with this rate, forever.
    case lock(FxQuote)
  }

  /// - Parameters:
  ///   - payday: the row's date ("yyyy-MM-dd", local).
  ///   - today: the local day now.
  ///   - answer: on payday, the live market rate; after payday (the app was closed that day), that
  ///     day's closing rate. Nil before payday or when offline.
  ///
  /// The market rate always exists, so there is no "wait for the noon publication" step: the first
  /// pass on or after payday locks.
  static func decide(payday: String, today: String, answer: FxQuote?) -> Decision {
    guard payday <= today else { return .live }
    guard let answer = answer else { return .wait }
    return .lock(answer)
  }
}
