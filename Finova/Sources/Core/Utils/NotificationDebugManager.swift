import Foundation
import UIKit
import UserNotifications

final class NotificationDebugManager {
  static let shared = NotificationDebugManager()

  private init() {}

  /// Comprehensive notification debugging that checks all aspects of the notification system
  func performFullNotificationDebug() {
    checkNotificationPermissions()
    checkAppLaunchHistory()
    checkPendingNotifications()
    checkUserAuthentication()
    checkTransactionData()
    checkSystemSettings()
  }

  /// Check when the app was last launched (affects notification scheduling)
  private func checkAppLaunchHistory() {
    let currentLaunchTime = Date()
    let lastLaunchKey = "lastAppLaunchTime"

    if UserDefaults.standard.object(forKey: lastLaunchKey) as? Date != nil {
      // Launch time recorded - no action needed
    }

    // Update the launch time for next check
    UserDefaults.standard.set(currentLaunchTime, forKey: lastLaunchKey)

    // Check if app was force-closed recently
    let terminationKey = "appWasTerminatedGracefully"

    // Mark that we're launching gracefully
    UserDefaults.standard.set(true, forKey: terminationKey)
  }

  /// Check current notification permission status
  private func checkNotificationPermissions() {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        if settings.authorizationStatus != .authorized {
          logError("Notification permissions not granted")
        }
      }
    }
  }

  /// Check currently pending notifications
  private func checkPendingNotifications() {
    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      DispatchQueue.main.async {
        if requests.isEmpty {
          logError("No pending notifications found")
        }
      }
    }
  }

  /// Check user authentication status
  private func checkUserAuthentication() {
    if let user = UserDefaultsManager.getUser() {
      if user.firebaseUID == nil {
        logError("User has no Firebase UID")
      }
    } else {
      logError("No authenticated user found")
    }
  }

  /// Check transaction data that should trigger notifications
  private func checkTransactionData() {
    guard let user = UserDefaultsManager.getUser(),
      let firebaseUID = user.firebaseUID
    else {
      logError("Cannot check transactions: No authenticated user")
      return
    }

    let transactionRepo = TransactionRepository()
    let allTransactions = transactionRepo.fetchAllTransactions()
    let now = Date()
    var calendar = Calendar.current
    calendar.timeZone = TimeZone.current  // Ensure we use local timezone

    // Check for future transactions (excluding hidden parent transactions)
    let futureTransactions = allTransactions.filter { tx in
      // Skip parent transactions that are not visible in UI (matching AppDelegate logic)
      if tx.hasInstallments == true && tx.amount == 0 {
        return false
      }

      if tx.isRecurring == true && tx.parentTransactionId == nil && tx.amount == 0 {
        return false
      }

      // Create notification time (8 AM) in local timezone using proper approach
      var notificationDate = calendar.startOfDay(for: tx.date)
      notificationDate =
        calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

      return notificationDate > now
    }

    // Check for today's transactions
    let todayTransactions = allTransactions.filter { tx in
      calendar.isDate(tx.date, inSameDayAs: now)
    }

    if !todayTransactions.isEmpty {
      for tx in todayTransactions {
        // Check if notification is currently pending for this transaction
        if let txId = tx.id {
          checkIfNotificationPending(for: txId)
        }
      }
    }

    if futureTransactions.isEmpty && todayTransactions.isEmpty {
      logError("No transactions found that should trigger notifications")
    }
  }

  /// Check if a specific transaction has a pending notification
  private func checkIfNotificationPending(for transactionId: Int) {
    let notificationId = "transaction_\(transactionId)"

    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      DispatchQueue.main.async {
        let hasNotification = requests.contains { $0.identifier == notificationId }
        if !hasNotification {
          logError("No notification pending for transaction \(transactionId)")
        }
      }
    }
  }

  /// Check system-level settings that might affect notifications
  private func checkSystemSettings() {
    // Manual checks needed for system settings
  }

  /// Trigger a test notification for immediate testing
  func scheduleTestNotification() {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized else {
        logError("Cannot schedule test notification: No permission")
        return
      }

      let content = UNMutableNotificationContent()
      content.title = "notification.test.title".localized
      content.body = "notification.test.body".localized
      content.sound = .default
      content.categoryIdentifier = "TEST_NOTIFICATION"

      // Schedule for 5 seconds from now using UNTimeIntervalNotificationTrigger
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
      let request = UNNotificationRequest(
        identifier: "test_notification_\(Date().timeIntervalSince1970)", content: content,
        trigger: trigger)

      UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
          logError("Failed to schedule test notification: \(error)")
        }
      }
    }
  }

  /// Remove duplicate notifications based on content similarity
  func removeDuplicateNotifications() {
    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      DispatchQueue.main.async {
        // Group notifications by content (title + body combination)
        var notificationGroups: [String: [UNNotificationRequest]] = [:]

        for request in requests {
          // Skip system notifications (monthly reminders, etc.)
          if request.identifier.contains("monthly_") || request.identifier.contains("test_")
            || request.identifier.contains("recurring_")
          {
            continue
          }

          // Create a key based on title and body content
          let contentKey = "\(request.content.title)_\(request.content.body)"

          if notificationGroups[contentKey] == nil {
            notificationGroups[contentKey] = []
          }
          notificationGroups[contentKey]?.append(request)
        }

        // Find and remove duplicates, but be more careful about recurring transactions
        var idsToRemove: [String] = []

        for (_, group) in notificationGroups {
          if group.count > 1 {
            // Check if these are legitimate recurring/installment notifications
            let areRecurringNotifications = group.allSatisfy { request in
              // Check if this is a recurring or installment notification by looking at the identifier
              // Recurring notifications have identifiers like "transaction_123" where 123 is the transaction ID
              if request.identifier.hasPrefix("transaction_") {
                let transactionIdString = String(request.identifier.dropFirst("transaction_".count))
                if let transactionId = Int(transactionIdString) {
                  // Check if this transaction is a recurring instance
                  return self.isRecurringTransactionInstance(transactionId: transactionId)
                }
              }
              return false
            }

            if areRecurringNotifications {
              continue
            }

            // Only remove if they're not recurring notifications
            // Keep the first one, remove the rest
            let duplicatesToRemove = Array(group.dropFirst())
            for duplicate in duplicatesToRemove {
              idsToRemove.append(duplicate.identifier)
            }
          }
        }

        if !idsToRemove.isEmpty {
          UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: idsToRemove)
        }
      }
    }
  }

  /// Check if a transaction ID corresponds to a recurring transaction instance
  private func isRecurringTransactionInstance(transactionId: Int) -> Bool {
    // Check if user is authenticated
    guard let user = UserDefaultsManager.getUser(),
      let firebaseUID = user.firebaseUID
    else {
      return false
    }

    let transactionRepo = TransactionRepository()
    let allTransactions = transactionRepo.fetchAllTransactions()

    // Find the transaction with this ID
    if let transaction = allTransactions.first(where: { $0.id == transactionId }) {
      // Check if it's a recurring instance (has a parent transaction ID)
      return transaction.parentTransactionId != nil
    }

    return false
  }

  /// Force reschedule all notifications
  func forceRescheduleAllNotifications() {
    // Clear all existing notifications
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

    // Add a delay to ensure clearing is complete, then reschedule
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      // Check if user is authenticated
      guard let user = UserDefaultsManager.getUser(),
        user.firebaseUID != nil
      else {
        logError("No authenticated user - cannot reschedule notifications")
        return
      }

      // Trigger the app delegate's scheduling method
      if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
        appDelegate.scheduleNotificationsOnLaunch()
      } else {
        logError("Could not access AppDelegate for notification rescheduling")
      }
    }
  }

  // MARK: - Helper Methods

  private func authorizationStatusString(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "Not Determined"
    case .denied: return "Denied"
    case .authorized: return "Authorized"
    case .provisional: return "Provisional"
    case .ephemeral: return "Ephemeral"
    @unknown default: return "Unknown"
    }
  }

  private func settingString(_ setting: UNNotificationSetting) -> String {
    switch setting {
    case .notSupported: return "Not Supported"
    case .disabled: return "Disabled"
    case .enabled: return "Enabled"
    @unknown default: return "Unknown"
    }
  }
}
