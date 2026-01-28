//
//  Logger.swift
//  FinanceApp
//
//  Created by Cursor on 27/01/25.
//

import Foundation

/// Centralized logging system for performance optimization
enum LogLevel: Int, CaseIterable {
  case debug = 0
  case info = 1
  case warning = 2
  case error = 3

  var emoji: String {
    switch self {
    case .debug: return "🔍"
    case .info: return "ℹ️"
    case .warning: return "⚠️"
    case .error: return "❌"
    }
  }
}

class Logger {
  static let shared = Logger()

  private let currentLogLevel: LogLevel

  private init() {
    #if DEBUG
      // In debug mode, show all logs
      self.currentLogLevel = .debug
    #else
      // In production, only show warnings and errors
      self.currentLogLevel = .warning
    #endif
  }

  func log(
    _ message: String, level: LogLevel = .info, file: String = #file, function: String = #function,
    line: Int = #line
  ) {
    guard level.rawValue >= currentLogLevel.rawValue else { return }

    let fileName = URL(fileURLWithPath: file).lastPathComponent
    let logMessage = "\(level.emoji) [\(fileName):\(line)] \(function): \(message)"

    #if DEBUG
      print(logMessage)
    #else
      // In production, only log warnings and errors
      if level.rawValue >= LogLevel.warning.rawValue {
        print(logMessage)
      }
    #endif
  }

  func debug(
    _ message: String, file: String = #file, function: String = #function, line: Int = #line
  ) {
    log(message, level: .debug, file: file, function: function, line: line)
  }

  func info(
    _ message: String, file: String = #file, function: String = #function, line: Int = #line
  ) {
    log(message, level: .info, file: file, function: function, line: line)
  }

  func warning(
    _ message: String, file: String = #file, function: String = #function, line: Int = #line
  ) {
    log(message, level: .warning, file: file, function: function, line: line)
  }

  func error(
    _ message: String, file: String = #file, function: String = #function, line: Int = #line
  ) {
    log(message, level: .error, file: file, function: function, line: line)
  }
}

// Convenience global functions for easier migration
func logDebug(
  _ message: String, file: String = #file, function: String = #function, line: Int = #line
) {
  Logger.shared.debug(message, file: file, function: function, line: line)
}

func logInfo(
  _ message: String, file: String = #file, function: String = #function, line: Int = #line
) {
  Logger.shared.info(message, file: file, function: function, line: line)
}

func logWarning(
  _ message: String, file: String = #file, function: String = #function, line: Int = #line
) {
  Logger.shared.warning(message, file: file, function: function, line: line)
}

func logError(
  _ message: String, file: String = #file, function: String = #function, line: Int = #line
) {
  Logger.shared.error(message, file: file, function: function, line: line)
}
