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

      // 🔔 Refresh credit card statement reminders.
      // `scheduleNotificationsOnLaunch()`, which used to be the only thing that scheduled them, is
      // not reachable from the real launch path — it is called only from NotificationDebugManager
      // and the tests. So on any launch that was not the first of the month, statement reminders
      // were never (re)created: new statements got none, and paid or re-dated ones kept stale
      // reminders. Statements close monthly, so this has to run on every launch, not once a month.
      self?.refreshStatementNotifications()

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

    // Reagendar lembretes de fatura — `applicationWillEnterForeground` is not called on a cold
    // launch, so this and the launch-time call are both needed to cover every way the app comes up.
    refreshStatementNotifications()

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
    // Mark that app is terminating gracefully
    UserDefaults.standard.set(false, forKey: "appWasTerminatedGracefully")
  }

  private func configureFirebase() {
    guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") else {
      // A shipped app without this file cannot work: the first `Auth.auth()` traps inside
      // FirebaseAuth, on whatever background thread happened to touch a singleton first, roughly a
      // second after launch. Logging a warning and carrying on turned a missing build input into a
      // crash with no visible connection to its cause — the plist is gitignored, so an archive
      // built anywhere other than a machine that already has it produced exactly that.
      //
      // Tests legitimately run without it, so they stay on the warning path. Anything else stops
      // here, where the message names the actual problem.
      #if DEBUG
        logWarning("GoogleService-Info.plist not found - skipping Firebase (test environment)")
        return
      #else
        fatalError(
          "GoogleService-Info.plist is missing from the app bundle. It is gitignored, so a CI build "
            + "must provide it — see ci_scripts/ci_post_clone.sh and the GOOGLE_SERVICE_INFO_PLIST_BASE64 "
            + "environment variable in the Xcode Cloud workflow.")
      #endif
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
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized else { return }

      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        guard UserDefaultsManager.getUser()?.firebaseUID != nil else { return }

        let transactionRepo = TransactionRepository()
        let allTxs = transactionRepo.fetchAllTransactions()
        TransactionNotificationManager.shared.scheduleAllTransactionNotifications(transactions: allTxs)
        // Statement-total recalculation and budget-month repair moved to the explicit
        // "Repair data" action (DataRepairService) — both rewrite rows and mark them pending,
        // which on launch meant every cold start queued a push the other device had to absorb.
        StatementNotificationManager.shared.scheduleAllStatementNotifications()
        self.monitorNegativeBalance()
      }
    }
  }

  /// Rebuilds every `statement_due_*` / `statement_pay_*` reminder from the current DB state.
  private func refreshStatementNotifications() {
    guard UserDefaultsManager.getUser()?.firebaseUID != nil else { return }
    StatementNotificationManager.shared.rescheduleAllNotifications()
  }

  private func rescheduleNearbyNotifications() {
    guard UserDefaultsManager.getUser()?.firebaseUID != nil else { return }

    let transactionRepo = TransactionRepository()
    let allTxs = transactionRepo.fetchAllTransactions()
    TransactionNotificationManager.shared.rescheduleNearbyTransactions(transactions: allTxs)
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
        // `scheduleAllMonthlyNotifications` blocks its caller on the notification centre and reads
        // the whole ledger, so it must not run on the main queue. It records the scheduled month
        // itself — see MonthlyNotificationManager.markCurrentMonthAsScheduled.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
          Self.rescheduleMonthlyNotificationsAndFlagAlert()
        }

      case "recurring_reminder", "installment_reminder":
        print(
          "🔔 📅 Recurring/installment reminder tapped - scheduling notifications with success alert")

        // Schedule monthly notifications without showing alert immediately
        // The alert will be shown when the dashboard appears
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
          Self.rescheduleMonthlyNotificationsAndFlagAlert()
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
    BalanceMonitorManager.shared.forceTriggerBalanceMonitoring()
  }

  // MARK: - Monthly Notification System

  /// Configura o sistema de notificações mensais
  private func setupMonthlyNotificationSystem() {
    // Check if user is authenticated first
    guard let user = UserDefaultsManager.getUser(),
      user.firebaseUID != nil
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
      user.firebaseUID != nil
    else {
      print("🔔 ❌ Cannot check monthly notifications: User not authenticated")
      return
    }

    let monthlyManager = MonthlyNotificationManager()
    let currentMonthKey = MonthlyNotificationManager.monthKey(for: Date())

    guard !monthlyManager.areNotificationsScheduledForCurrentMonth() else {
      print("🔔 📅 Already scheduled notifications for month \(currentMonthKey)")
      return
    }

    print("🔔 📅 First time opening app in month \(currentMonthKey) - scheduling notifications")

    // Schedule monthly notifications without showing alert immediately.
    // The alert will be shown when the dashboard appears.
    // Runs off the main queue: the call blocks on the notification centre and reads the ledger.
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
      Self.rescheduleMonthlyNotificationsAndFlagAlert(successAlertType: "success")
    }
  }

  /// Reschedules this month's notifications and leaves a flag for the dashboard to surface the
  /// resulting alert. `MonthlyNotificationManager` records the month itself on success, which is
  /// what retires the "notifications not configured" prompt for the same month.
  /// The month the "notifications are off" notice was last shown for.
  private static let permissionNoticeMonthKey = "notificationPermissionNoticeMonth"

  private static func rescheduleMonthlyNotificationsAndFlagAlert(
    successAlertType: String = "rescheduled"
  ) {
    let monthlyManager = MonthlyNotificationManager()
    let success = monthlyManager.scheduleAllMonthlyNotifications(showAlert: false)

    // Notifications switched off is the user's choice, not a failure. Reporting it as "Notification
    // Setup Failed" came back on every launch, because a month without permission is never recorded
    // as scheduled. Say why instead, once a month; the month stays unrecorded so scheduling runs as
    // soon as permission is granted.
    if !success && !monthlyManager.hasNotificationPermission() {
      let monthKey = MonthlyNotificationManager.monthKey(for: Date())
      guard UserDefaults.standard.string(forKey: permissionNoticeMonthKey) != monthKey else { return }
      UserDefaults.standard.set(monthKey, forKey: permissionNoticeMonthKey)
      UserDefaults.standard.set(true, forKey: "shouldShowNotificationSuccessAlert")
      UserDefaults.standard.set("permission", forKey: "notificationAlertType")
      return
    }

    UserDefaults.standard.set(true, forKey: "shouldShowNotificationSuccessAlert")
    UserDefaults.standard.set(
      success ? successAlertType : "failure", forKey: "notificationAlertType")

    if success {
      print("🔔 ✅ Monthly notifications scheduled for \(MonthlyNotificationManager.monthKey(for: Date()))")
    } else {
      print("🔔 ❌ Failed to schedule monthly notifications")
    }
  }
}
