//
//  NotificationHistoryViewModel.swift
//  Finova
//
//  Created by Claude on 29/01/2026.
//

import Foundation

protocol NotificationHistoryViewModelDelegate: AnyObject {
  func didUpdateNotifications(_ notifications: [NotificationHistoryItem])
  func didMarkNotificationAsRead(at index: Int)
}

final class NotificationHistoryViewModel {
  weak var delegate: NotificationHistoryViewModelDelegate?

  private let historyManager = NotificationHistoryManager.shared
  private var notifications: [NotificationHistoryItem] = []
  private var visibleIndices: Set<Int> = []

  // MARK: - Public Methods

  func loadNotifications() {
    notifications = historyManager.allNotifications
    delegate?.didUpdateNotifications(notifications)
  }

  func numberOfNotifications() -> Int {
    return notifications.count
  }

  func notification(at index: Int) -> NotificationHistoryItem? {
    guard index >= 0 && index < notifications.count else { return nil }
    return notifications[index]
  }

  /// Called when a notification cell becomes visible
  func notificationBecameVisible(at index: Int) {
    guard index >= 0 && index < notifications.count else { return }

    // Mark as visible for tracking
    visibleIndices.insert(index)

    // Mark as read if unread
    let notification = notifications[index]
    if !notification.isRead {
      historyManager.markAsRead(id: notification.id)
      notifications[index].isRead = true
      delegate?.didMarkNotificationAsRead(at: index)
    }
  }

  /// Called when user taps on a notification
  func didSelectNotification(at index: Int) {
    guard index >= 0 && index < notifications.count else { return }

    // Mark as read
    let notification = notifications[index]
    if !notification.isRead {
      historyManager.markAsRead(id: notification.id)
      notifications[index].isRead = true
      delegate?.didMarkNotificationAsRead(at: index)
    }
  }

  /// Called when view disappears - marks all visible notifications as read
  func viewWillDisappear() {
    // All visible notifications should already be marked as read
    // This ensures any edge cases are handled
    let unreadVisibleIds = visibleIndices.compactMap { index -> String? in
      guard index < notifications.count && !notifications[index].isRead else { return nil }
      return notifications[index].id
    }

    if !unreadVisibleIds.isEmpty {
      historyManager.markAsRead(ids: unreadVisibleIds)
    }
  }
}
