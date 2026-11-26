//
//  FxRateProvider.swift
//  Finova
//
//  Rates come from Frankfurter (European Central Bank reference rates): no API key, HTTPS,
//  historical rates by date. Only currency codes and dates are sent. See docs/fx-salary-plan.md §4.
//

import Foundation

/// One rate as the provider answered it. `date` is the provider's own date ("yyyy-MM-dd"), which can
/// be earlier than the date asked for (weekends, holidays, or before the day's publication).
struct FxQuote: Equatable {
  let base: String
  let quote: String
  let date: String
  let rateMicros: Int
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
    return FxQuote(base: base, quote: quote, date: date, rateMicros: FxMath.micros(fromRate: rate))
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
    /// Payday's own rate is not published yet. Keep the row live and try again later.
    case wait
    /// Freeze with this rate, forever.
    case lock(FxQuote)
  }

  /// - Parameters:
  ///   - payday: the row's date ("yyyy-MM-dd", local).
  ///   - today: the local day now.
  ///   - answer: the provider's answer to "rate dated payday" (nil before payday).
  static func decide(payday: String, today: String, answer: FxQuote?) -> Decision {
    guard payday <= today else { return .live }
    guard let answer = answer else { return .wait }
    // On payday itself, a weekday answer dated earlier means ECB has not published today's rate
    // yet (~16:00 CET, ~12:00 in Brasília). Waiting makes the locked rate "the official rate for
    // payday" no matter when the phone opens the app.
    if answer.date < payday, payday == today, FxDay.isWeekday(payday) {
      return .wait
    }
    return .lock(answer)
  }
}
