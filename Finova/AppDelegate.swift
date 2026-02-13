//
//  AppDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Firebase
import FirebaseMessaging
import GoogleSignIn
import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate,
  MessagingDelegate
{

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Only perform essential synchronous operations on main thread
    configureFirebase()
    registerForNotifications()

    // Move heavy operations to background thread for better performance
    DispatchQueue.global(qos: .background).async { [weak self] in
      // 🧹 Perform one-time cleanup of global SQLite data
      DataCleanupManager.shared.performGlobalDataCleanup()

      // 🔄 Perform one-time migrations (including global profile image cleanup)
      OneTimeMigrations.shared.performAllMigrations()

      // 🔔 Setup monthly notification system
      self?.setupMonthlyNotificationSystem()

      // 🔔 Check if this is first time opening app in new month and schedule notifications
      self?.checkAndScheduleMonthlyNotificationsOnFirstLaunch()

      #if DEBUG
        // 🧪 Debug: Show data status on app launch (only in debug mode)
        DebugDataManager.shared.showDataStatus()
      #endif
    }

    return true
  }

  func applicationWillEnterForeground(_ application: UIApplication) {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    logInfo("App will enter foreground")

    // Reagendar notificações para transações próximas
    rescheduleNearbyNotifications()

    // Monitorar saldo negativo quando o app voltar ao foreground
    monitorNegativeBalance()

    // Note: SceneDelegate will handle the appDidEnterForeground notification posting
    // to avoid duplicate notifications and ensure proper timing
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

  func applicationWillTerminate(_ application: UIApplication) {
    // Called when the application is about to terminate.
    // Save data if appropriate.

    // Mark that app is terminating gracefully
    UserDefaults.standard.set(false, forKey: "appWasTerminatedGracefully")
  }

  private func configureFirebase() {
    guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") else {
      logWarning(
        "GoogleService-Info.plist not found - Firebase configuration skipped (likely in test environment)"
      )
      return
    }

    if FileManager.default.fileExists(atPath: path) {
      logInfo("Configuring Firebase...")
      FirebaseApp.configure()
      logInfo("Firebase configured successfully")

      // Verify Firebase is working
      if let app = FirebaseApp.app() {
        logDebug("Firebase app instance: \(app)")
        logDebug("Firebase project ID: \(app.options.projectID ?? "Unknown")")
      } else {
        logError("Firebase app instance is nil!")
      }

      // Test Auth instance
      let auth = Auth.auth()
      logDebug("Firebase Auth instance: \(auth)")

      // Configure Google Sign-In
      guard let plist = NSDictionary(contentsOfFile: path),
        let clientId = plist["CLIENT_ID"] as? String
      else {
        logWarning("CLIENT_ID not found in GoogleService-Info.plist")
        return
      }

      logDebug("CLIENT_ID: \(clientId)")
      GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
      logInfo("Google Sign-In configured successfully")

      #if DEBUG
        // AuthTestHelper.testAuthenticationFlow()
      #endif
    } else {
      logWarning("GoogleService-Info.plist file not accessible - Firebase configuration skipped")
    }
  }

  func registerForNotifications() {
    let center = UNUserNotificationCenter.current()
    center.delegate = self  // Set the delegate
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      DispatchQueue.main.async {
        if granted {
          print("✅ User granted permission for notifications")
          // Register for remote notifications (required for FCM)
          UIApplication.shared.registerForRemoteNotifications()
        } else if let error = error {
          print("❌ \(error) - User did not grant permission for notifications")
        } else {
          print("❌ User denied permission for notifications")
        }
      }
    }

    // Set FCM messaging delegate
    Messaging.messaging().delegate = self
  }

  // MARK: - APNs Token Handling

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Pass device token to Firebase
    Messaging.messaging().apnsToken = deviceToken
    let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("📱 APNs device token: \(tokenString)")

    // Now that we have APNs token, subscribe to topics
    // This ensures the subscription happens after APNs token is available
    subscribeToAppUpdatesTopic()
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
  }

  // MARK: - CloudKit Remote Notifications

  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    CloudKitManager.shared.handleRemoteNotification(userInfo: userInfo) {
      completionHandler(.newData)
    }
  }

  // MARK: - MessagingDelegate

  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    guard let fcmToken = fcmToken else { return }
    print("📱 FCM registration token: \(fcmToken)")

    // Note: Topic subscription is now done in didRegisterForRemoteNotificationsWithDeviceToken
    // to ensure APNs token is available before subscribing
    // If APNs token is already available, subscribe now (handles token refresh scenarios)
    if Messaging.messaging().apnsToken != nil {
      subscribeToAppUpdatesTopic()
    }
  }

  /// Subscribe to the app_updates topic for push notifications about new versions
  private func subscribeToAppUpdatesTopic() {
    Messaging.messaging().subscribe(toTopic: "app_updates") { error in
      if let error = error {
        print("❌ Failed to subscribe to app_updates topic: \(error.localizedDescription)")
      } else {
        print("✅ Subscribed to app_updates topic for version notifications")
      }
    }
  }

  // MARK: - Notification Scheduling on Launch

  func scheduleNotificationsOnLaunch() {
    // Only schedule notifications if we have permission
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized else {
        return
      }

      // Schedule notifications for all future transactions
      // This will be called once on app launch to ensure notifications are set up
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {  // Delay to ensure data is loaded
        self.scheduleAllTransactionNotifications()
        self.scheduleCreditCardStatementNotifications()
        self.monitorNegativeBalance()
      }
    }
  }

  private func scheduleAllTransactionNotifications() {
    // Check if user is authenticated first
    guard let user = UserDefaultsManager.getUser(),
      let firebaseUID = user.firebaseUID
    else {
      print("🔔 ❌ Cannot schedule notifications: User not authenticated")
      print("🔔 ❌ Cannot schedule notifications: User not authenticated")
      return
    }

    let transactionRepo = TransactionRepository()
    let allTxs = transactionRepo.fetchAllTransactions()
    let now = Date()
    var calendar = Calendar.current
    calendar.timeZone = TimeZone.current

    print("🔔 📡 Scheduling notifications for \(allTxs.count) transactions")

    // Clear existing notifications first
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    print("🔔 🧹 Cleared existing notifications")

    // Schedule notifications for all future transactions (excluding hidden parent transactions)
    let futureTxs = allTxs.filter { tx in
      // Skip parent transactions that are not visible in UI
      if tx.hasInstallments == true && tx.amount == 0 {
        return false
      }

      if tx.isRecurring == true && tx.parentTransactionId == nil && tx.amount == 0 {
        return false
      }

      // Create notification time (8 AM) in local timezone
      var notificationDate = calendar.startOfDay(for: tx.date)
      notificationDate =
        calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

      return notificationDate > now
    }

    print("🔔 📅 Found \(futureTxs.count) future transactions to schedule")

    // Sort by date to prioritize closest transactions first
    let sortedTxs = futureTxs.sorted { tx1, tx2 in
      tx1.date < tx2.date
    }

    // Prioritize transactions in the next 30 days
    let thirtyDaysFromNow = calendar.date(byAdding: .day, value: 30, to: now) ?? now
    let next30DaysTxs = sortedTxs.filter { tx in
      tx.date <= thirtyDaysFromNow
    }
    let remainingTxs = sortedTxs.filter { tx in
      tx.date > thirtyDaysFromNow
    }

    print("🔔 📅 Next 30 days: \(next30DaysTxs.count) transactions")
    print("🔔 📅 Beyond 30 days: \(remainingTxs.count) transactions")

    // Combine arrays: prioritize next 30 days, then remaining sorted by date
    let prioritizedTxs = next30DaysTxs + remainingTxs

    // Limitar a 50 notificações para evitar problemas com limite do iOS
    let limitedTxs = Array(prioritizedTxs.prefix(50))
    if limitedTxs.count < prioritizedTxs.count {
      let skippedInNext30Days = max(0, next30DaysTxs.count - min(50, next30DaysTxs.count))
      print(
        "🔔 ⚠️ Limited notifications to 50 (iOS limit). \(prioritizedTxs.count - limitedTxs.count) transactions will not have notifications"
      )
      if skippedInNext30Days > 0 {
        print(
          "🔔 ⚠️ WARNING: \(skippedInNext30Days) transactions in the next 30 days will NOT have notifications!"
        )
      } else {
        print(
          "🔔 ✅ All \(next30DaysTxs.count) transactions in the next 30 days will have notifications")
      }
    } else {
      print(
        "🔔 ✅ All \(next30DaysTxs.count) transactions in the next 30 days will have notifications")
    }

    limitedTxs.forEach { tx in
      scheduleNotification(for: tx, calendar: calendar)
    }
  }

  private func scheduleNotification(for tx: Transaction, calendar: Calendar) {
    guard let transactionId = tx.id else {
      return
    }

    let id = "transaction_\(transactionId)"

    // Create notification time (8 AM) in local timezone
    var notificationDate = calendar.startOfDay(for: tx.date)
    notificationDate =
      calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    // Only schedule if notification time is in the future
    guard notificationDate > Date() else {
      return
    }

    // Verificar se a data é muito no futuro (mais de 1 ano)
    let oneYearFromNow = calendar.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    if tx.date > oneYearFromNow {
      print("🔔 ⚠️ Skipping notification for \(tx.title) - date too far in future")
      return
    }

    // Calculate time interval from now to notification date
    let timeInterval = notificationDate.timeIntervalSinceNow

    // Verificar se o intervalo é muito grande (mais de 30 dias)
    let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
    if timeInterval > thirtyDaysInSeconds {
      print("🔔 ⚠️ Skipping notification for \(tx.title) - more than 30 days away")
      return
    }

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

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
    let body = String(format: bodyKey.localized, amountString, tx.title)

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = ["transactionId": transactionId, "date": tx.date.timeIntervalSince1970]

    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        print("🔔 ❌ Error scheduling notification for \(tx.title): \(error)")
      } else {
        print(
          "🔔 ✅ Scheduled notification for \(tx.title) at \(DateFormatter.debugTimestampFormatter.string(from: notificationDate))"
        )
      }
    }
  }

  // MARK: - Notification Management

  /// Reagenda notificações para transações que estão próximas (dentro de 30 dias)
  private func rescheduleNearbyNotifications() {
    guard let user = UserDefaultsManager.getUser(),
      let firebaseUID = user.firebaseUID
    else {
      return
    }

    let transactionRepo = TransactionRepository()
    let allTxs = transactionRepo.fetchAllTransactions()
    let now = Date()
    var calendar = Calendar.current
    calendar.timeZone = TimeZone.current

    // Encontrar transações que estão entre 30 e 60 dias no futuro
    let thirtyDaysFromNow = calendar.date(byAdding: .day, value: 30, to: now) ?? now
    let sixtyDaysFromNow = calendar.date(byAdding: .day, value: 60, to: now) ?? now

    let nearbyTxs = allTxs.filter { tx in
      // Skip parent transactions that are not visible in UI
      if tx.hasInstallments == true && tx.amount == 0 {
        return false
      }

      if tx.isRecurring == true && tx.parentTransactionId == nil && tx.amount == 0 {
        return false
      }

      return tx.date >= thirtyDaysFromNow && tx.date <= sixtyDaysFromNow
    }

    if !nearbyTxs.isEmpty {
      print("🔔 🔄 Rescheduling notifications for \(nearbyTxs.count) nearby transactions")
      nearbyTxs.forEach { tx in
        scheduleNotification(for: tx, calendar: calendar)
      }
    }
  }

  // MARK: - Credit Card Statement Notifications

  private func scheduleCreditCardStatementNotifications() {
    guard NotificationPreferencesManager.shared.shouldShowNotification(type: .creditCardStatement) else {
      print("🔔 💳 Credit card statement notifications disabled - skipping")
      return
    }

    guard let user = UserDefaultsManager.getUser(),
          let firebaseUID = user.firebaseUID else {
      print("🔔 ❌ Cannot schedule statement notifications: User not authenticated")
      return
    }

    let cardRepo = CreditCardRepository()
    let statementRepo = StatementRepository()
    let cards = cardRepo.fetchAllCards(userId: firebaseUID)

    let now = Date()
    var calendar = Calendar.current
    calendar.timeZone = TimeZone.current

    // Remove old statement notifications first
    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      let statementIds = requests
        .filter { $0.identifier.hasPrefix("statement_due_") || $0.identifier.hasPrefix("statement_pay_") }
        .map { $0.identifier }
      UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: statementIds)
      print("🔔 🧹 Cleared \(statementIds.count) existing statement notifications")
    }

    var scheduledCount = 0

    for card in cards where !card.isDeleted {
      guard let cardId = card.id else { continue }
      let statements = statementRepo.fetchStatements(forCardId: cardId)

      for statement in statements {
        guard !statement.isPaid, let statementId = statement.id else { continue }

        let dueDate = statement.dueDate
        guard dueDate > now else { continue }

        let amountString = statement.totalAmount.currencyString

        // Due-soon notification (3 days before due date, at 9 AM)
        if let threeDaysBefore = calendar.date(byAdding: .day, value: -3, to: dueDate) {
          var dueSoonDate = calendar.startOfDay(for: threeDaysBefore)
          dueSoonDate = calendar.date(byAdding: .hour, value: 9, to: dueSoonDate) ?? dueSoonDate

          if dueSoonDate > now {
            let timeInterval = dueSoonDate.timeIntervalSinceNow
            let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
            if timeInterval <= thirtyDaysInSeconds {
              let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

              let content = UNMutableNotificationContent()
              content.title = "notification.statement.dueSoon.title".localized
              content.body = String(format: "notification.statement.dueSoon.body".localized, card.name, amountString)
              content.sound = .default
              content.userInfo = [
                "type": "credit_card_statement",
                "statementId": statementId,
                "cardId": cardId
              ]

              let id = "statement_due_\(statementId)"
              let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
              UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                  print("🔔 ❌ Error scheduling due-soon notification: \(error)")
                } else {
                  print("🔔 ✅ Scheduled due-soon notification for \(card.name) statement \(statementId)")
                }
              }
              scheduledCount += 1
            }
          }
        }

        // Payment reminder (on due date, at 9 AM)
        var paymentDate = calendar.startOfDay(for: dueDate)
        paymentDate = calendar.date(byAdding: .hour, value: 9, to: paymentDate) ?? paymentDate

        if paymentDate > now {
          let timeInterval = paymentDate.timeIntervalSinceNow
          let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
          if timeInterval <= thirtyDaysInSeconds {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

            let content = UNMutableNotificationContent()
            content.title = "notification.statement.paymentDue.title".localized
            content.body = String(format: "notification.statement.paymentDue.body".localized, card.name, amountString)
            content.sound = .default
            content.userInfo = [
              "type": "credit_card_statement",
              "statementId": statementId,
              "cardId": cardId
            ]

            let id = "statement_pay_\(statementId)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
              if let error = error {
                print("🔔 ❌ Error scheduling payment-due notification: \(error)")
              } else {
                print("🔔 ✅ Scheduled payment-due notification for \(card.name) statement \(statementId)")
              }
            }
            scheduledCount += 1
          }
        }
      }
    }

    print("🔔 💳 Scheduled \(scheduledCount) credit card statement notifications")
  }

  // MARK: - UNUserNotificationCenterDelegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Track notification in history
    NotificationHistoryManager.shared.handleDeliveredLocalNotification(notification)

    // Show notification even when app is in foreground
    completionHandler([.alert, .sound, .badge])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    // Handle notification tap
    let notification = response.notification
    let userInfo = notification.request.content.userInfo
    print("📱 User tapped notification: \(userInfo)")

    // Add notification to history if it's not already there (handles background/killed app cases)
    // This ensures push notifications that bypassed willPresent are tracked
    NotificationHistoryManager.shared.handleDeliveredLocalNotification(notification)

    // Mark notification as read when tapped
    let notificationId = notification.request.identifier
    NotificationHistoryManager.shared.markAsRead(id: notificationId)

    // Check if this is a transaction notification (has transactionId in userInfo)
    if let transactionId = userInfo["transactionId"] as? Int {
      print("🔔 📱 Transaction notification tapped - navigating to transaction \(transactionId)")
      // Post notification to navigate to transaction details
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        NotificationCenter.default.post(
          name: .navigateToTransactionDetails,
          object: nil,
          userInfo: ["transactionId": transactionId]
        )
      }
      completionHandler()
      return
    }

    // Check if this is a credit card statement notification
    if let notificationType = userInfo["type"] as? String,
       notificationType == "credit_card_statement",
       let statementId = userInfo["statementId"] as? Int,
       let cardId = userInfo["cardId"] as? Int {
      print("🔔 💳 Statement notification tapped - navigating to statement \(statementId)")
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        NotificationCenter.default.post(
          name: .navigateToStatementDetails,
          object: nil,
          userInfo: ["statementId": statementId, "cardId": cardId]
        )
      }
      completionHandler()
      return
    }

    // Check if this is a monthly notification that should trigger success alert
    if let notificationType = userInfo["type"] as? String {
      switch notificationType {
      case "monthly_reminder", "monthly_fallback":
        print("🔔 📅 Monthly notification tapped - scheduling notifications with success alert")

        // Schedule monthly notifications without showing alert immediately
        // The alert will be shown when the dashboard appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {  // Delay to ensure app is fully loaded
          let monthlyManager = MonthlyNotificationManager()
          let success = monthlyManager.scheduleAllMonthlyNotifications(showAlert: false)

          if success {
            // Update the last scheduled month key since we just scheduled notifications
            let currentDate = Date()
            let calendar = Calendar.current
            let currentMonth = calendar.component(.month, from: currentDate)
            let currentYear = calendar.component(.year, from: currentDate)
            let currentMonthKey = "\(currentYear)-\(currentMonth)"
            UserDefaults.standard.set(currentMonthKey, forKey: "lastScheduledMonthKey")
            // Mark that we should show the rescheduled alert on dashboard
            UserDefaults.standard.set(true, forKey: "shouldShowNotificationSuccessAlert")
            UserDefaults.standard.set("rescheduled", forKey: "notificationAlertType")
          } else {
            // Mark that we should show the failure alert on dashboard
            UserDefaults.standard.set(true, forKey: "shouldShowNotificationSuccessAlert")
            UserDefaults.standard.set("failure", forKey: "notificationAlertType")
          }
        }

      case "recurring_reminder", "installment_reminder":
        print(
          "🔔 📅 Recurring/installment reminder tapped - scheduling notifications with success alert")

        // Schedule monthly notifications without showing alert immediately
        // The alert will be shown when the dashboard appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {  // Delay to ensure app is fully loaded
          let monthlyManager = MonthlyNotificationManager()
          let success = monthlyManager.scheduleAllMonthlyNotifications(showAlert: false)

          if success {
            // Mark that we should show the rescheduled alert on dashboard
            UserDefaults.standard.set(true, forKey: "shouldShowNotificationSuccessAlert")
            UserDefaults.standard.set("rescheduled", forKey: "notificationAlertType")
          } else {
            // Mark that we should show the failure alert on dashboard
            UserDefaults.standard.set(true, forKey: "shouldShowNotificationSuccessAlert")
            UserDefaults.standard.set("failure", forKey: "notificationAlertType")
          }
        }

      case "app_update":
        print("🔔 📲 App update notification tapped - opening App Store")
        // Open App Store to update the app
        UpdateToastManager.shared.openAppStore()

      default:
        print("🔔 📱 Other notification type tapped: \(notificationType)")
      }
    }

    completionHandler()
  }

  // MARK: - Balance Monitoring

  /// Monitora o saldo negativo do mês atual
  private func monitorNegativeBalance() {
    // Check if user is authenticated first
    guard let user = UserDefaultsManager.getUser(),
      let firebaseUID = user.firebaseUID
    else {
      print("🔔 ❌ Cannot monitor balance: User not authenticated")
      return
    }

    // Create balance monitor and check current month
    let balanceMonitor = BalanceMonitorManager()
    balanceMonitor.monitorCurrentMonthBalance()

    print("🔔 💰 Balance monitoring completed")
  }

  // MARK: - Monthly Notification System

  /// Configura o sistema de notificações mensais
  private func setupMonthlyNotificationSystem() {
    // Check if user is authenticated first
    guard let user = UserDefaultsManager.getUser(),
      let firebaseUID = user.firebaseUID
    else {
      print("🔔 ❌ Cannot setup monthly notifications: User not authenticated")
      return
    }

    // Create monthly notification manager and setup system
    let monthlyManager = MonthlyNotificationManager()
    monthlyManager.setupMonthlyNotificationSystem()

    print("🔔 📅 Monthly notification system setup completed")
  }

  /// Verifica se é a primeira vez abrindo o app no mês e agenda notificações se necessário
  private func checkAndScheduleMonthlyNotificationsOnFirstLaunch() {
    // Check if user is authenticated first
    guard let user = UserDefaultsManager.getUser(),
      let firebaseUID = user.firebaseUID
    else {
      print("🔔 ❌ Cannot check monthly notifications: User not authenticated")
      return
    }

    let currentDate = Date()
    let calendar = Calendar.current
    let currentMonth = calendar.component(.month, from: currentDate)
    let currentYear = calendar.component(.year, from: currentDate)

    // Create a key for the current month
    let currentMonthKey = "\(currentYear)-\(currentMonth)"

    // Check if we've already scheduled notifications for this month
    let lastScheduledMonthKey = UserDefaults.standard.string(forKey: "lastScheduledMonthKey")

    if lastScheduledMonthKey != currentMonthKey {
      print("🔔 📅 First time opening app in month \(currentMonthKey) - scheduling notifications")

      // Schedule monthly notifications without showing alert immediately
      // The alert will be shown when the dashboard appears
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {  // Delay to ensure app is fully loaded
        let monthlyManager = MonthlyNotificationManager()
        let success = monthlyManager.scheduleAllMonthlyNotifications(showAlert: false)

        if success {
          // Save that we've scheduled notifications for this month
          UserDefaults.standard.set(currentMonthKey, forKey: "lastScheduledMonthKey")
          // Mark that we should show the success alert on dashboard
          UserDefaults.standard.set(true, forKey: "shouldShowNotificationSuccessAlert")
          UserDefaults.standard.set("success", forKey: "notificationAlertType")
          print("🔔 ✅ Monthly notifications scheduled for \(currentMonthKey)")
        } else {
          // Mark that we should show the failure alert on dashboard
          UserDefaults.standard.set(true, forKey: "shouldShowNotificationSuccessAlert")
          UserDefaults.standard.set("failure", forKey: "notificationAlertType")
          print("🔔 ❌ Failed to schedule monthly notifications for \(currentMonthKey)")
        }
      }
    } else {
      print("🔔 📅 Already scheduled notifications for month \(currentMonthKey)")
    }
  }
}
