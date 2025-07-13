//
//  AppDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Firebase
import GoogleSignIn
import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureFirebase()
    registerForNotifications()

    // 🧹 Perform one-time cleanup of global SQLite data
    DataCleanupManager.shared.performGlobalDataCleanup()

    // 🔄 Perform one-time migrations (including global profile image cleanup)
    OneTimeMigrations.shared.performAllMigrations()

    // 🔔 Schedule notifications on app launch
    scheduleNotificationsOnLaunch()

    #if DEBUG
      // 🧪 Debug: Show data status on app launch
      DebugDataManager.shared.showDataStatus()
    #endif

    return true
  }

  // MARK: UISceneSession Lifecycle

  func application(
    _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return UISceneConfiguration(
      name: "Default Configuration", sessionRole: connectingSceneSession.role)
  }

  func application(
    _ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>
  ) {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
  }

  private func configureFirebase() {
    guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") else {
      print(
        "⚠️ GoogleService-Info.plist not found - Firebase configuration skipped (likely in test environment)"
      )
      return
    }

    if FileManager.default.fileExists(atPath: path) {
      print("🔥 Configuring Firebase...")
      FirebaseApp.configure()
      print("✅ Firebase configured successfully")

      // Verify Firebase is working
      if let app = FirebaseApp.app() {
        print("✅ Firebase app instance: \(app)")
        print("✅ Firebase project ID: \(app.options.projectID ?? "Unknown")")
      } else {
        print("❌ Firebase app instance is nil!")
      }

      // Test Auth instance
      let auth = Auth.auth()
      print("✅ Firebase Auth instance: \(auth)")

      // Configure Google Sign-In
      guard let plist = NSDictionary(contentsOfFile: path),
        let clientId = plist["CLIENT_ID"] as? String
      else {
        print("⚠️ CLIENT_ID not found in GoogleService-Info.plist")
        return
      }

      print("🔑 CLIENT_ID: \(clientId)")
      GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
      print("✅ Google Sign-In configured successfully")

      #if DEBUG
        // AuthTestHelper.testAuthenticationFlow()
      #endif
    } else {
      print("⚠️ GoogleService-Info.plist file not accessible - Firebase configuration skipped")
    }
  }

  func registerForNotifications() {
    let center = UNUserNotificationCenter.current()
    center.delegate = self  // Set the delegate
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      DispatchQueue.main.async {
        if granted {
          print("✅ User granted permission for notifications")
        } else if let error = error {
          print("❌ \(error) - User did not grant permission for notifications")
        } else {
          print("❌ User denied permission for notifications")
        }
      }
    }
  }

  // MARK: - Notification Scheduling on Launch

  func scheduleNotificationsOnLaunch() {
    // Only schedule notifications if we have permission
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized else {
        print("🔔 ❌ Notification permission not granted - skipping scheduling")
        return
      }

      // Schedule notifications for all future transactions
      // This will be called once on app launch to ensure notifications are set up
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {  // Delay to ensure data is loaded
        self.scheduleAllTransactionNotifications()
      }
    }
  }

  private func scheduleAllTransactionNotifications() {
    // Check if user is authenticated first
    guard let user = UserDefaultsManager.getUser(),
      let firebaseUID = user.firebaseUID
    else {
      print("🔔 ❌ No authenticated user - skipping notification scheduling")
      return
    }

    // Authenticate SecureLocalDataManager
    SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)

    let transactionRepo = TransactionRepository()
    let allTxs = transactionRepo.fetchAllTransactions()
    let now = Date()
    let calendar = Calendar.current

    print("🔔 📅 Scheduling notifications for \(allTxs.count) transactions on app launch")

    // Clear existing notifications first
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

    // Schedule notifications for all future transactions
    let futureTxs = allTxs.filter { tx in
      // Get the transaction date and create notification time (8 AM)
      var comps = calendar.dateComponents([.year, .month, .day], from: tx.date)
      comps.hour = 8
      comps.minute = 0

      guard let notificationDate = calendar.date(from: comps) else { return false }
      return notificationDate > now
    }

    print("🔔 📅 Found \(futureTxs.count) future transactions to schedule")

    futureTxs.forEach { tx in
      scheduleNotification(for: tx, calendar: calendar)
    }
  }

  private func scheduleNotification(for tx: Transaction, calendar: Calendar) {
    guard let transactionId = tx.id else {
      print("🔔 ❌ No transaction ID for: \(tx.title)")
      return
    }

    let id = "transaction_\(transactionId)"

    // Get the transaction date and create notification time (8 AM)
    var comps = calendar.dateComponents([.year, .month, .day], from: tx.date)
    comps.hour = 8
    comps.minute = 0

    guard let notificationDate = calendar.date(from: comps) else {
      print("🔔 ❌ Could not create notification date for: \(tx.title)")
      return
    }

    // Only schedule if notification time is in the future
    guard notificationDate > Date() else {
      print("🔔 ❌ Notification time (\(notificationDate)) is in the past for: \(tx.title)")
      return
    }

    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

    let titleKey =
      tx.type == .income
      ? "notification.transaction.title.income"
      : "notification.transaction.title.expense"
    let bodyKey =
      tx.type == .income
      ? "notification.transaction.body.income"
      : "notification.transaction.body.expense"

    let amountString = tx.amount.currencyString
    let title = titleKey.localized
    let body = bodyKey.localized(amountString, tx.title)

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"

    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        print("🔔 ❌ Error scheduling notification for \(tx.title): \(error)")
      } else {
        print("🔔 ✅ Successfully scheduled notification for \(tx.title) at \(notificationDate)")
      }
    }
  }

  // MARK: - UNUserNotificationCenterDelegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Show notification even when app is in foreground
    completionHandler([.alert, .sound, .badge])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    // Handle notification tap
    let userInfo = response.notification.request.content.userInfo
    print("📱 User tapped notification: \(userInfo)")
    // TODO: Navigate to specific transaction or screen if needed
    completionHandler()
  }
}
