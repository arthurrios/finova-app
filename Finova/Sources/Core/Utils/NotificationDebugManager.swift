import Foundation
import UIKit
import UserNotifications

final class NotificationDebugManager {
  static let shared = NotificationDebugManager()

  private init() {}

  /// Comprehensive notification debugging that checks all aspects of the notification system
  func performFullNotificationDebug() {
    print("🔔 ==================== NOTIFICATION DEBUG REPORT ====================")

    checkNotificationPermissions()
    checkAppLaunchHistory()
    checkPendingNotifications()
    checkUserAuthentication()
    checkTransactionData()
    checkSystemSettings()

    print("🔔 ================================================================")
  }

  /// Check when the app was last launched (affects notification scheduling)
  private func checkAppLaunchHistory() {
    print("🔔 1.5️⃣ CHECKING APP LAUNCH HISTORY...")

    let currentLaunchTime = Date()
    let lastLaunchKey = "lastAppLaunchTime"

    if let lastLaunchTime = UserDefaults.standard.object(forKey: lastLaunchKey) as? Date {
      print("🔔    Last app launch: \(lastLaunchTime)")
      print("🔔    Current launch: \(currentLaunchTime)")

      let timeSinceLastLaunch = currentLaunchTime.timeIntervalSince(lastLaunchTime)
      let hoursSinceLastLaunch = timeSinceLastLaunch / 3600

      print("🔔    Time since last launch: \(String(format: "%.1f", hoursSinceLastLaunch)) hours")

      if hoursSinceLastLaunch > 24 {
        print("🔔 ⚠️  App hasn't been launched in over 24 hours!")
        print("🔔    💡 Notifications are only scheduled when app launches.")
        print("🔔       This could explain missing notifications.")
      }
    } else {
      print("🔔    No previous launch time recorded")
    }

    // Update the launch time for next check
    UserDefaults.standard.set(currentLaunchTime, forKey: lastLaunchKey)

    // Check if app was force-closed recently
    let terminationKey = "appWasTerminatedGracefully"
    let wasTerminatedGracefully = UserDefaults.standard.bool(forKey: terminationKey)

    if !wasTerminatedGracefully {
      print("🔔 ⚠️  App may have been force-closed or crashed last time!")
      print("🔔    💡 This can prevent notifications from being scheduled properly.")
    }

    // Mark that we're launching gracefully
    UserDefaults.standard.set(true, forKey: terminationKey)
  }

  /// Check current notification permission status
  private func checkNotificationPermissions() {
    print("🔔 1️⃣ CHECKING NOTIFICATION PERMISSIONS...")

    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        print(
          "🔔    Authorization Status: \(self.authorizationStatusString(settings.authorizationStatus))"
        )
        print("🔔    Alert Setting: \(self.settingString(settings.alertSetting))")
        print("🔔    Sound Setting: \(self.settingString(settings.soundSetting))")
        print("🔔    Badge Setting: \(self.settingString(settings.badgeSetting))")
        print(
          "🔔    Notification Center Setting: \(self.settingString(settings.notificationCenterSetting))"
        )
        print("🔔    Lock Screen Setting: \(self.settingString(settings.lockScreenSetting))")
        print("🔔    Car Play Setting: \(self.settingString(settings.carPlaySetting))")
        print("🔔    Announcement Setting: \(self.settingString(settings.announcementSetting))")

        if settings.authorizationStatus != .authorized {
          print("🔔 ❌ ISSUE: Notification permissions not granted!")
          print("🔔    💡 Solution: Go to Settings > Finova > Notifications and enable them")
        }
      }
    }
  }

  /// Check currently pending notifications
  private func checkPendingNotifications() {
    print("🔔 2️⃣ CHECKING PENDING NOTIFICATIONS...")

    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      DispatchQueue.main.async {
        print("🔔    Total pending notifications: \(requests.count)")

        if requests.isEmpty {
          print("🔔 ❌ ISSUE: No pending notifications found!")
          print("🔔    💡 This could mean:")
          print("🔔       - No future transactions exist")
          print("🔔       - Notifications were not scheduled properly")
          print("🔔       - App hasn't been launched recently to schedule them")
        } else {
          let now = Date()
          var todayNotifications = 0
          var futureNotifications = 0

          for request in requests {
            print("🔔    📅 Notification ID: \(request.identifier)")
            print("🔔       Title: \(request.content.title)")
            print("🔔       Body: \(request.content.body)")

            var nextTriggerDate: Date?

            if let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger {
              nextTriggerDate = calendarTrigger.nextTriggerDate()
              print("🔔       Trigger type: Calendar-based")
            } else if let intervalTrigger = request.trigger as? UNTimeIntervalNotificationTrigger {
              // For interval triggers, calculate when they will fire
              nextTriggerDate = Date().addingTimeInterval(intervalTrigger.timeInterval)
              print(
                "🔔       Trigger type: Interval-based (\(intervalTrigger.timeInterval) seconds)")
            }

            if let nextTriggerDate = nextTriggerDate {
              let formatter = DateFormatter()
              formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
              print("🔔       Scheduled for: \(formatter.string(from: nextTriggerDate))")

              let calendar = Calendar.current
              if calendar.isDate(nextTriggerDate, inSameDayAs: now) {
                todayNotifications += 1

                // Check if it's scheduled for 8 AM today
                let components = calendar.dateComponents([.hour], from: nextTriggerDate)
                if components.hour == 8 {
                  let currentHour = calendar.component(.hour, from: now)
                  if currentHour >= 8 {
                    print(
                      "🔔 ⚠️  This notification was scheduled for 8 AM today but it's already past 8 AM"
                    )
                  }
                }
              } else if nextTriggerDate > now {
                futureNotifications += 1
              }
            } else {
              print("🔔       Scheduled for: Unknown trigger type")
            }
            print("🔔       ---")
          }

          print("🔔    📊 Summary:")
          print("🔔       Today's notifications: \(todayNotifications)")
          print("🔔       Future notifications: \(futureNotifications)")
        }
      }
    }
  }

  /// Check user authentication status
  private func checkUserAuthentication() {
    print("🔔 3️⃣ CHECKING USER AUTHENTICATION...")

    if let user = UserDefaultsManager.getUser() {
      print("🔔    ✅ User authenticated: \(user.name)")
      print("🔔    Firebase UID: \(user.firebaseUID ?? "None")")

      if user.firebaseUID == nil {
        print("🔔 ❌ ISSUE: User has no Firebase UID!")
        print("🔔    💡 Solution: User needs to sign in again")
      }
    } else {
      print("🔔 ❌ ISSUE: No authenticated user found!")
      print("🔔    💡 Solution: User needs to sign in")
    }
  }

  /// Check transaction data that should trigger notifications
  private func checkTransactionData() {
    print("🔔 4️⃣ CHECKING TRANSACTION DATA...")

    guard let user = UserDefaultsManager.getUser(),
      let firebaseUID = user.firebaseUID
    else {
      print("🔔 ❌ Cannot check transactions: No authenticated user")
      return
    }

    // Authenticate SecureLocalDataManager
    SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)

    let transactionRepo = TransactionRepository()
    let allTransactions = transactionRepo.fetchAllTransactions()
    let now = Date()
    var calendar = Calendar.current
    calendar.timeZone = TimeZone.current  // Ensure we use local timezone

    print("🔔    Total transactions: \(allTransactions.count)")

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

    print("🔔    Future transactions (should have notifications): \(futureTransactions.count)")
    print("🔔    Today's transactions: \(todayTransactions.count)")

    if !todayTransactions.isEmpty {
      print("🔔    📅 Today's transactions (detailed analysis):")
      for tx in todayTransactions {
        print("🔔       - \(tx.title): \(tx.amount.currencyString)")
        print("🔔         Transaction date: \(tx.date)")
        print(
          "🔔         Transaction created: \(Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp)))"
        )

        // Calculate what the notification time would have been
        var notificationTime = calendar.startOfDay(for: tx.date)
        notificationTime =
          calendar.date(byAdding: .hour, value: 8, to: notificationTime) ?? notificationTime

        print("🔔         Notification should have been: \(notificationTime)")
        if notificationTime < now {
          print("🔔         ❌ Notification time was in the past - would NOT be scheduled")
        } else {
          print("🔔         ✅ Notification time was in the future - should have been scheduled")
        }

        // Check if notification is currently pending for this transaction
        if let txId = tx.id {
          checkIfNotificationPending(for: txId)
        }
        print("🔔         ---")
      }

      let currentHour = calendar.component(.hour, from: now)
      if currentHour >= 8 {
        print("🔔 ⚠️  It's already past 8 AM, so today's notifications should have fired")
        print("🔔    💡 Key insight: If transactions were created yesterday or earlier,")
        print("🔔       notifications should have been scheduled and should have fired.")
        print("🔔       If they were created today after 8 AM, no notifications would be scheduled.")
      }
    }

    if futureTransactions.isEmpty && todayTransactions.isEmpty {
      print("🔔 ❌ ISSUE: No transactions found that should trigger notifications!")
      print("🔔    💡 Solution: Add some future transactions to test notifications")
    }
  }

  /// Check if a specific transaction has a pending notification
  private func checkIfNotificationPending(for transactionId: Int) {
    let notificationId = "transaction_\(transactionId)"

    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      DispatchQueue.main.async {
        let hasNotification = requests.contains { $0.identifier == notificationId }
        if hasNotification {
          print("🔔         ✅ Notification IS pending for this transaction")
        } else {
          print("🔔         ❌ NO notification pending for this transaction")
        }
      }
    }
  }

  /// Check system-level settings that might affect notifications
  private func checkSystemSettings() {
    print("🔔 5️⃣ CHECKING SYSTEM SETTINGS...")

    // Check if Focus/Do Not Disturb might be active
    print("🔔    💡 Manual checks needed:")
    print("🔔       - Is Do Not Disturb/Focus mode active?")
    print("🔔       - Are app notifications enabled in iOS Settings?")
    print("🔔       - Is the device's date/time correct?")
    print("🔔       - Has the app been force-closed recently?")
    print("🔔       - Is Low Power Mode active? (can delay notifications)")
  }

  /// Trigger a test notification for immediate testing
  func scheduleTestNotification() {
    print("🔔 📡 SCHEDULING TEST NOTIFICATION...")

    UNUserNotificationCenter.current().getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized else {
        print("🔔 ❌ Cannot schedule test notification: No permission")
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
          print("🔔 ❌ Failed to schedule test notification: \(error)")
        } else {
          let formatter = DateFormatter()
          formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
          let willFireAt = Date().addingTimeInterval(5)
          print("🔔 ✅ Test notification scheduled for 5 seconds from now!")
          print("🔔    Will fire at: \(formatter.string(from: willFireAt))")
        }
      }
    }
  }

  /// Remove duplicate notifications based on content similarity
  func removeDuplicateNotifications() {
    print("🔔 🔍 CHECKING FOR DUPLICATE NOTIFICATIONS...")

    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      DispatchQueue.main.async {
        print("🔔 📊 Analyzing \(requests.count) pending notifications for duplicates...")

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
        var duplicatesFound = 0
        var idsToRemove: [String] = []

        for (contentKey, group) in notificationGroups {
          if group.count > 1 {
            print("🔔 🚨 Found \(group.count) notifications with same content: \(contentKey)")

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
              print("🔔 ✅ These are legitimate recurring notifications - keeping all \(group.count)")
              continue
            }

            // Only remove if they're not recurring notifications
            print("🔔 🚨 These appear to be actual duplicates - removing \(group.count - 1)")
            duplicatesFound += group.count - 1

            // Keep the first one, remove the rest
            let duplicatesToRemove = Array(group.dropFirst())
            for duplicate in duplicatesToRemove {
              idsToRemove.append(duplicate.identifier)
              print("🔔 ❌ Will remove duplicate: \(duplicate.identifier)")
            }
          }
        }

        if duplicatesFound > 0 {
          print("🔔 🧹 Removing \(duplicatesFound) duplicate notifications...")
          UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: idsToRemove)
          print("🔔 ✅ Removed duplicate notifications")

          // Show results after cleanup
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            UNUserNotificationCenter.current().getPendingNotificationRequests { updatedRequests in
              DispatchQueue.main.async {
                print("🔔 📊 After cleanup: \(updatedRequests.count) notifications remaining")
              }
            }
          }
        } else {
          print("🔔 ✅ No duplicate notifications found")
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

    // Authenticate SecureLocalDataManager
    SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)

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
    print("🔔 🔄 FORCE RESCHEDULING ALL NOTIFICATIONS...")

    // Clear all existing notifications
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    print("🔔 ✅ Cleared all pending notifications")

    // Add a delay to ensure clearing is complete, then reschedule
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      print("🔔 🔄 Starting rescheduling process...")

      // Check if user is authenticated
      guard let user = UserDefaultsManager.getUser(),
        let firebaseUID = user.firebaseUID
      else {
        print("🔔 ❌ No authenticated user - cannot reschedule")
        return
      }

      print("🔔 ✅ User authenticated: \(firebaseUID)")

      // Trigger the app delegate's scheduling method
      if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
        print("🔔 🔄 Calling scheduleNotificationsOnLaunch()...")
        appDelegate.scheduleNotificationsOnLaunch()
        print("🔔 ✅ Triggered notification rescheduling via AppDelegate")

        // Verify rescheduling worked after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
          UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
              print("🔔 📊 After rescheduling: \(requests.count) notifications pending")

              if let firstRequest = requests.first {
                print("🔔 📅 First rescheduled notification:")
                print("🔔    ID: \(firstRequest.identifier)")

                var nextTriggerDate: Date?

                if let calendarTrigger = firstRequest.trigger as? UNCalendarNotificationTrigger {
                  nextTriggerDate = calendarTrigger.nextTriggerDate()
                  print("🔔    Trigger type: Calendar-based")
                } else if let intervalTrigger = firstRequest.trigger
                  as? UNTimeIntervalNotificationTrigger
                {
                  nextTriggerDate = Date().addingTimeInterval(intervalTrigger.timeInterval)
                  print(
                    "🔔    Trigger type: Interval-based (\(intervalTrigger.timeInterval) seconds)")
                }

                if let nextTriggerDate = nextTriggerDate {
                  print("🔔    Scheduled for: \(nextTriggerDate)")

                  // Check if timezone is now correct
                  let formatter = DateFormatter()
                  formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
                  print("🔔    Timezone check: \(formatter.string(from: nextTriggerDate))")
                }
              }
            }
          }
        }
      } else {
        print("🔔 ❌ Could not access AppDelegate")
      }
    }
  }

  // MARK: - Helper Methods

  private func authorizationStatusString(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "Not Determined"
    case .denied: return "❌ DENIED"
    case .authorized: return "✅ AUTHORIZED"
    case .provisional: return "⚠️ PROVISIONAL"
    case .ephemeral: return "⏰ EPHEMERAL"
    @unknown default: return "Unknown"
    }
  }

  private func settingString(_ setting: UNNotificationSetting) -> String {
    switch setting {
    case .notSupported: return "Not Supported"
    case .disabled: return "❌ DISABLED"
    case .enabled: return "✅ ENABLED"
    @unknown default: return "Unknown"
    }
  }
}
