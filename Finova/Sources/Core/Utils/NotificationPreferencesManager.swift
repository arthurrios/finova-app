//
//  NotificationPreferencesManager.swift
//  Finova
//
//  Created by Claude on 29/01/2026.
//

import Foundation
import UserNotifications
import FirebaseMessaging

/// Manages user preferences for all notification types in the app
final class NotificationPreferencesManager {
  static let shared = NotificationPreferencesManager()

  // MARK: - UserDefaults Keys

  private let transactionNotificationsKey = "notificationPref_transactions"
  private let appUpdateNotificationsKey = "notificationPref_appUpdates"
  private let negativeBalanceNotificationsKey = "notificationPref_negativeBalance"
  private let creditCardStatementNotificationsKey = "notificationPref_creditCardStatement"
  private let allNotificationsDisabledKey = "notificationPref_allDisabled"

  private init() {}

  // MARK: - All Notifications

  /// Whether all notifications are disabled by the user
  var allNotificationsDisabled: Bool {
    get { UserDefaults.standard.bool(forKey: allNotificationsDisabledKey) }
    set {
      UserDefaults.standard.set(newValue, forKey: allNotificationsDisabledKey)
      if newValue {
        // Unsubscribe from push notification topics
        unsubscribeFromAllTopics()
        // Remove pending local notifications
        removeAllPendingNotifications()
      } else {
        // Re-subscribe to push notification topics if individual settings allow
        if appUpdateNotificationsEnabled {
          subscribeToAppUpdatesTopic()
        }
      }
    }
  }

  // MARK: - Transaction Notifications (Local)

  /// Whether transaction reminders (credits/debits) are enabled
  /// Default: true
  var transactionNotificationsEnabled: Bool {
    get {
      // Default to true if not set
      if UserDefaults.standard.object(forKey: transactionNotificationsKey) == nil {
        return true
      }
      return UserDefaults.standard.bool(forKey: transactionNotificationsKey)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: transactionNotificationsKey)
      if !newValue {
        removeTransactionNotifications()
      }
    }
  }

  // MARK: - App Update Notifications (Push)

  /// Whether app update notifications are enabled
  /// Default: true
  var appUpdateNotificationsEnabled: Bool {
    get {
      // Default to true if not set
      if UserDefaults.standard.object(forKey: appUpdateNotificationsKey) == nil {
        return true
      }
      return UserDefaults.standard.bool(forKey: appUpdateNotificationsKey)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: appUpdateNotificationsKey)
      if newValue && !allNotificationsDisabled {
        subscribeToAppUpdatesTopic()
      } else {
        unsubscribeFromAppUpdatesTopic()
      }
    }
  }

  // MARK: - Negative Balance Notifications (Local)

  /// Whether negative balance warning notifications are enabled
  /// Default: true
  var negativeBalanceNotificationsEnabled: Bool {
    get {
      // Default to true if not set
      if UserDefaults.standard.object(forKey: negativeBalanceNotificationsKey) == nil {
        return true
      }
      return UserDefaults.standard.bool(forKey: negativeBalanceNotificationsKey)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: negativeBalanceNotificationsKey)
      if !newValue {
        removeNegativeBalanceNotifications()
      }
    }
  }

  // MARK: - Credit Card Statement Notifications (Local)

  /// Whether credit card statement reminder notifications are enabled
  /// Default: true
  var creditCardStatementNotificationsEnabled: Bool {
    get {
      // Default to true if not set
      if UserDefaults.standard.object(forKey: creditCardStatementNotificationsKey) == nil {
        return true
      }
      return UserDefaults.standard.bool(forKey: creditCardStatementNotificationsKey)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: creditCardStatementNotificationsKey)
      if !newValue {
        removeCreditCardStatementNotifications()
      }
    }
  }

  // MARK: - Helper Methods

  /// Check if a specific notification type should be shown
  func shouldShowNotification(type: NotificationType) -> Bool {
    if allNotificationsDisabled {
      return false
    }

    switch type {
    case .transaction:
      return transactionNotificationsEnabled
    case .appUpdate:
      return appUpdateNotificationsEnabled
    case .negativeBalance:
      return negativeBalanceNotificationsEnabled
    case .creditCardStatement:
      return creditCardStatementNotificationsEnabled
    }
  }

  // MARK: - Push Notification Topics

  private func subscribeToAppUpdatesTopic() {
    Messaging.messaging().subscribe(toTopic: "app_updates") { error in
      if let error = error {
        logError("Failed to subscribe to app_updates: \(error.localizedDescription)")
      } else {
        logInfo("Subscribed to app_updates topic")
      }
    }
  }

  private func unsubscribeFromAppUpdatesTopic() {
    Messaging.messaging().unsubscribe(fromTopic: "app_updates") { error in
      if let error = error {
        logError("Failed to unsubscribe from app_updates: \(error.localizedDescription)")
      } else {
        logInfo("Unsubscribed from app_updates topic")
      }
    }
  }

  private func unsubscribeFromAllTopics() {
    unsubscribeFromAppUpdatesTopic()
  }

  // MARK: - Local Notification Management

  private func removeAllPendingNotifications() {
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    logInfo("Removed all pending notifications")
  }

  private func removeTransactionNotifications() {
    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      let transactionIds = requests
        .filter { $0.identifier.hasPrefix("transaction_") }
        .map { $0.identifier }

      UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: transactionIds)
      logInfo("Removed \(transactionIds.count) transaction notifications")
    }
  }

  private func removeNegativeBalanceNotifications() {
    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      let balanceIds = requests
        .filter { $0.identifier.hasPrefix("negative_balance_") || $0.identifier.hasPrefix("balance_") }
        .map { $0.identifier }

      UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: balanceIds)
      logInfo("Removed \(balanceIds.count) negative balance notifications")
    }
  }

  private func removeCreditCardStatementNotifications() {
    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      let statementIds = requests
        .filter { $0.identifier.hasPrefix("statement_due_") || $0.identifier.hasPrefix("statement_pay_") }
        .map { $0.identifier }

      UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: statementIds)
      logInfo("Removed \(statementIds.count) credit card statement notifications")
    }
  }

  // MARK: - Reset to Defaults

  func resetToDefaults() {
    UserDefaults.standard.removeObject(forKey: transactionNotificationsKey)
    UserDefaults.standard.removeObject(forKey: appUpdateNotificationsKey)
    UserDefaults.standard.removeObject(forKey: negativeBalanceNotificationsKey)
    UserDefaults.standard.removeObject(forKey: creditCardStatementNotificationsKey)
    UserDefaults.standard.removeObject(forKey: allNotificationsDisabledKey)

    // Re-subscribe to topics
    subscribeToAppUpdatesTopic()

    logInfo("Notification preferences reset to defaults")
  }
}

// MARK: - Notification Type Enum

enum NotificationType {
  case transaction
  case appUpdate
  case negativeBalance
  case creditCardStatement
}
