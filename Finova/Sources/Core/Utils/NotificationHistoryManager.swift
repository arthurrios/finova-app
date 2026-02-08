//
//  NotificationHistoryManager.swift
//  Finova
//
//  Created by Claude on 29/01/2026.
//

import Foundation
import UIKit
import UserNotifications

/// Represents a notification item in the history
struct NotificationHistoryItem: Codable, Identifiable {
  let id: String
  let title: String
  let body: String
  let date: Date
  let type: NotificationType
  var isRead: Bool

  enum NotificationType: String, Codable {
    case transaction
    case negativeBalance
    case appUpdate
    case installment
    case recurring
    case monthly
    case creditCardStatement
    case other
  }
}

/// Manages notification history and read states
final class NotificationHistoryManager {
  static let shared = NotificationHistoryManager()

  private let userDefaultsKey = "notification_history"
  private let unreadCountKey = "unread_notification_count"
  private let maxHistoryItems = 50

  private var history: [NotificationHistoryItem] = []

  /// Callback when unread count changes
  var onUnreadCountChanged: ((Int) -> Void)?

  private init() {
    loadHistory()
  }

  // MARK: - Public Methods

  /// Returns the current unread count
  var unreadCount: Int {
    return history.filter { !$0.isRead }.count
  }

  /// Returns all notification history items sorted by date (newest first)
  var allNotifications: [NotificationHistoryItem] {
    return history.sorted { $0.date > $1.date }
  }

  /// Adds a notification to history
  func addNotification(
    id: String,
    title: String,
    body: String,
    type: NotificationHistoryItem.NotificationType
  ) {
    let item = NotificationHistoryItem(
      id: id,
      title: title,
      body: body,
      date: Date(),
      type: type,
      isRead: false
    )

    // Remove duplicate if exists
    history.removeAll { $0.id == id }

    // Add new item
    history.insert(item, at: 0)

    // Trim old items
    if history.count > maxHistoryItems {
      history = Array(history.prefix(maxHistoryItems))
    }

    saveHistory()
    notifyUnreadCountChanged()
  }

  /// Marks a specific notification as read
  func markAsRead(id: String) {
    guard let index = history.firstIndex(where: { $0.id == id }) else { return }
    history[index].isRead = true
    saveHistory()
    notifyUnreadCountChanged()
  }

  /// Marks all visible notifications as read (when user views the list)
  func markAllVisibleAsRead() {
    var changed = false
    for index in history.indices {
      if !history[index].isRead {
        history[index].isRead = true
        changed = true
      }
    }
    if changed {
      saveHistory()
      notifyUnreadCountChanged()
    }
  }

  /// Marks notifications as read by their IDs
  func markAsRead(ids: [String]) {
    var changed = false
    for id in ids {
      if let index = history.firstIndex(where: { $0.id == id && !$0.isRead }) {
        history[index].isRead = true
        changed = true
      }
    }
    if changed {
      saveHistory()
      notifyUnreadCountChanged()
    }
  }

  /// Clears all notification history
  func clearHistory() {
    history.removeAll()
    saveHistory()
    notifyUnreadCountChanged()
  }

  /// Deletes a specific notification from history
  func deleteNotification(id: String) {
    history.removeAll { $0.id == id }
    saveHistory()
    notifyUnreadCountChanged()
  }

  /// Deletes notification at specific index
  func deleteNotification(at index: Int) {
    guard index >= 0 && index < history.count else { return }
    // History is sorted by date (newest first), so we need to find the right item
    let sortedHistory = history.sorted { $0.date > $1.date }
    let itemToDelete = sortedHistory[index]
    history.removeAll { $0.id == itemToDelete.id }
    saveHistory()
    notifyUnreadCountChanged()
  }

  /// Handles a received notification and adds it to history
  func handleReceivedNotification(userInfo: [AnyHashable: Any]) {
    guard let aps = userInfo["aps"] as? [String: Any],
          let alert = aps["alert"] as? [String: Any],
          let title = alert["title"] as? String,
          let body = alert["body"] as? String else {
      return
    }

    let id = UUID().uuidString
    let type = determineNotificationType(from: userInfo)

    addNotification(id: id, title: title, body: body, type: type)
  }

  /// Handles a delivered notification (local or push)
  func handleDeliveredLocalNotification(_ notification: UNNotification) {
    let content = notification.request.content
    let id = notification.request.identifier

    // Skip if already exists (avoid duplicates when called from both willPresent and didReceive)
    guard !history.contains(where: { $0.id == id }) else {
      return
    }

    // Determine type from userInfo first (for push notifications), then from identifier
    let userInfo = content.userInfo
    let type: NotificationHistoryItem.NotificationType
    if let typeString = userInfo["type"] as? String {
      type = determineNotificationType(from: userInfo)
    } else {
      type = determineNotificationType(fromIdentifier: id)
    }

    addNotification(id: id, title: content.title, body: content.body, type: type)
  }

  // MARK: - Private Methods

  private func loadHistory() {
    guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
          let decoded = try? JSONDecoder().decode([NotificationHistoryItem].self, from: data) else {
      return
    }
    history = decoded
  }

  private func saveHistory() {
    guard let data = try? JSONEncoder().encode(history) else { return }
    UserDefaults.standard.set(data, forKey: userDefaultsKey)
  }

  private func notifyUnreadCountChanged() {
    let count = unreadCount
    onUnreadCountChanged?(count)
    syncAppBadge(count: count)
  }

  /// Syncs the app badge with the current unread count
  func syncAppBadge(count: Int? = nil) {
    let badgeCount = count ?? unreadCount
    DispatchQueue.main.async {
      UIApplication.shared.applicationIconBadgeNumber = badgeCount
    }
  }

  /// Syncs delivered notifications from the notification center to history
  /// Call this when the app becomes active to capture notifications delivered while in background
  func syncDeliveredNotifications() {
    UNUserNotificationCenter.current().getDeliveredNotifications { [weak self] notifications in
      guard let self = self else { return }

      var hasNewNotifications = false

      for notification in notifications {
        let content = notification.request.content
        let id = notification.request.identifier

        // Skip if already in history
        guard !self.history.contains(where: { $0.id == id }) else {
          continue
        }

        // Determine type from userInfo first (for push notifications), then from identifier
        let userInfo = content.userInfo
        let type: NotificationHistoryItem.NotificationType
        if userInfo["type"] as? String != nil {
          type = self.determineNotificationType(from: userInfo)
        } else {
          type = self.determineNotificationType(fromIdentifier: id)
        }

        let item = NotificationHistoryItem(
          id: id,
          title: content.title,
          body: content.body,
          date: notification.date,
          type: type,
          isRead: false
        )

        self.history.insert(item, at: 0)
        hasNewNotifications = true
        logDebug("Synced notification from background: \(content.title)")
      }

      if hasNewNotifications {
        // Trim old items
        if self.history.count > self.maxHistoryItems {
          self.history = Array(self.history.prefix(self.maxHistoryItems))
        }

        // Sort by date (newest first)
        self.history.sort { $0.date > $1.date }

        self.saveHistory()
        DispatchQueue.main.async {
          self.notifyUnreadCountChanged()
        }
      }
    }
  }

  private func determineNotificationType(from userInfo: [AnyHashable: Any]) -> NotificationHistoryItem.NotificationType {
    if let type = userInfo["type"] as? String {
      switch type {
      case "app_update":
        return .appUpdate
      case "negative_balance":
        return .negativeBalance
      case "transaction":
        return .transaction
      case "installment":
        return .installment
      case "recurring":
        return .recurring
      case "credit_card_statement":
        return .creditCardStatement
      default:
        return .other
      }
    }
    return .other
  }

  private func determineNotificationType(fromIdentifier id: String) -> NotificationHistoryItem.NotificationType {
    if id.hasPrefix("transaction_") {
      return .transaction
    } else if id.hasPrefix("negative_balance_") {
      return .negativeBalance
    } else if id.hasPrefix("installment_") {
      return .installment
    } else if id.hasPrefix("recurring_") {
      return .recurring
    } else if id.hasPrefix("monthly_") {
      return .monthly
    } else if id.hasPrefix("statement_due_") || id.hasPrefix("statement_pay_") {
      return .creditCardStatement
    }
    return .other
  }
}
