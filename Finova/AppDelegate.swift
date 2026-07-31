//
//  AppDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import CloudKit
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

      // The dead-group-zone purge used to run here, eight seconds after launch, under #if DEBUG.
      // It DELETES CloudKit zones, and nothing that deletes cloud data should fire on its own — the
      // same rule Stage 4 applied to the local repair passes. It now lives behind an explicit
      // action in Sync Settings, which also means it is available in a Release build; being
      // DEBUG-only was what made it look as though the Release scheme were needed to reach the
      // production zones. It never was: `icloud-container-environment` is pinned to Production for
      // both configurations, so every build has always talked to the same CloudKit database.
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

    // Fetch any missed group activity notifications
    GroupNotificationManager.shared.fetchAndNotifyRecentActivities {}

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
    logWarning("[AppLifecycle] Application will terminate — attempting sync flush")

    // Mark that app is terminating gracefully
    UserDefaults.standard.set(false, forKey: "appWasTerminatedGracefully")

    var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    backgroundTaskID = application.beginBackgroundTask(withName: "com.finova.terminationSyncFlush") {
      logWarning("[AppLifecycle] Termination sync flush task expired")
      if backgroundTaskID != .invalid {
        application.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
      }
    }

    guard backgroundTaskID != .invalid else {
      logWarning("[AppLifecycle] Failed to begin background task on termination")
      return
    }

    // Block the main thread until push completes or times out,
    // since the process exits when this method returns.
    let semaphore = DispatchSemaphore(value: 0)

    SyncEngine.shared.flushPendingChanges { _ in
      semaphore.signal()
    }

    let result = semaphore.wait(timeout: .now() + 4.0)
    if result == .timedOut {
      logWarning("[AppLifecycle] Termination sync flush timed out after 4s")
    }

    if backgroundTaskID != .invalid {
      application.endBackgroundTask(backgroundTaskID)
      backgroundTaskID = .invalid
    }
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
    logWarning("AppDelegate: didReceiveRemoteNotification called")

    // Log raw payload structure for diagnosis
    if let ck = userInfo["ck"] as? [String: Any] {
      let hasQry = ck["qry"] != nil
      let hasDbs = ck["dbs"] != nil
      logWarning("AppDelegate: ck payload — hasQry=\(hasQry) hasDbs=\(hasDbs)")
      if let qry = ck["qry"] as? [String: Any] {
        logWarning("AppDelegate: qry keys=\(qry.keys.sorted()) sid=\(qry["sid"] ?? "nil")")
        if let af = qry["af"] as? [String: Any] {
          logWarning("AppDelegate: qry fields (af)=\(af)")
        }
      }
    }

    // Handle group activity notifications directly from push payload
    // before the system suspends the app (mirrors the invitation pattern).
    let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo)
    logWarning("AppDelegate: CKNotification type=\(ckNotification.map { "\(type(of: $0))" } ?? "nil") subID=\(ckNotification?.subscriptionID ?? "nil")")

    if let notification = ckNotification as? CKQueryNotification {
      logWarning("AppDelegate: CKQueryNotification — reason=\(notification.queryNotificationReason.rawValue) fields=\(notification.recordFields ?? [:]) recordID=\(notification.recordID?.recordName ?? "nil")")
      let fields = notification.recordFields
      let actorName = fields?["actorName"] as? String
      let action = fields?["action"] as? String
      let detail = fields?["detail"] as? String
      let actorId = fields?["actorId"] as? String
      let currentUID = AuthenticationManager.shared.currentUser?.uid
      logWarning("AppDelegate: field extraction — actorName=\(actorName ?? "nil") action=\(action ?? "nil") detail=\(detail ?? "nil") actorId=\(actorId ?? "nil") currentUID=\(currentUID ?? "nil") isOwnAction=\(actorId == currentUID)")

      if notification.queryNotificationReason == .recordCreated,
         let actorName = actorName,
         let action = action,
         let detail = detail,
         let actorId = actorId,
         actorId != currentUID {
        // Use logical key as notification identifier so iOS deduplicates
        // across all paths (push payload, public DB fetch, zone sync).
        let logicalKey = GroupNotificationManager.logicalDeduplicationKey(action: action, actorId: actorId, detail: detail)
        let recordName = notification.recordID?.recordName
        logWarning("AppDelegate: GroupActivity PUSH — action=\(action) actor=\(actorName) detail=\(detail) logicalKey=\(logicalKey)")

        // Mark as processed so fetchAndNotifyRecentActivities doesn't re-show it
        let processedKey = "GroupNotification_ProcessedRecordNames"
        var processed = UserDefaults.standard.stringArray(forKey: processedKey) ?? []
        if !processed.contains(logicalKey) {
          if let rn = recordName, !processed.contains(rn) { processed.append(rn) }
          processed.append(logicalKey)
          if processed.count > 200 { processed = Array(processed.suffix(200)) }
          UserDefaults.standard.set(processed, forKey: processedKey)

          let content = UNMutableNotificationContent()
          content.title = actorName
          content.body = GroupNotificationManager.shared.notificationBody(for: action, detail: detail)
          content.sound = .default
          content.categoryIdentifier = "GROUP_ACTIVITY"
          var notifUserInfo: [String: Any] = ["action": action]
          if let targetRecordName = fields?["targetRecordName"] as? String {
            notifUserInfo["targetRecordName"] = targetRecordName
          }
          content.userInfo = notifUserInfo
          let request = UNNotificationRequest(identifier: logicalKey, content: content, trigger: nil)
          UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
              logWarning("AppDelegate: UNNotification add FAILED — \(error.localizedDescription)")
            } else {
              logWarning("AppDelegate: UNNotification add SUCCEEDED — id=\(logicalKey)")
            }
          }
        } else {
          logWarning("AppDelegate: GroupActivity PUSH — already processed, skipping")
        }
      } else {
        logWarning("AppDelegate: CKQueryNotification SKIPPED — reason=\(notification.queryNotificationReason.rawValue) fieldsNil=\(fields == nil) isOwnAction=\(actorId == currentUID)")
      }
    } else {
      logWarning("AppDelegate: NOT CKQueryNotification — actual type: \(ckNotification.map { "\(type(of: $0))" } ?? "nil")")
    }

    // Always query public DB for recent GroupActivityNotification records.
    // CKQuerySubscription pushes are often coalesced/throttled by iOS when
    // a CKDatabaseNotification push arrives first, so we fetch directly.
    fetchPublicGroupActivityNotifications()

    // Process remote notification (zone changes, invitations, etc.)
    BudgetGroupService.shared.fetchRemoteInvitations {
      CloudKitManager.shared.handleRemoteNotification(userInfo: userInfo) {
        completionHandler(.newData)
      }
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
    let userInfo = notification.request.content.userInfo

    // Handle CloudKit invitation push — add to history with proper ID for tap navigation
    if let invitationId = extractInvitationIdFromCloudKitPush(userInfo) {
      let content = notification.request.content
      NotificationHistoryManager.shared.addNotification(
        id: "group_invitation_\(invitationId)",
        title: content.title,
        body: content.body,
        type: .groupInvitation
      )
      completionHandler([.alert, .sound, .badge])
      return
    }

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

    // Check if this is a group activity notification about a transaction
    if notification.request.content.categoryIdentifier == "GROUP_ACTIVITY",
       let targetRecordName = userInfo["targetRecordName"] as? String,
       let action = userInfo["action"] as? String {
      let transactionActions: Set<String> = ["transaction_created", "transaction_edited"]
      if transactionActions.contains(action) {
        let repo = TransactionRepository()
        if let transaction = repo.fetchTransaction(byCKRecordName: targetRecordName),
           let transactionId = transaction.id {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
              name: .navigateToTransactionDetails,
              object: nil,
              userInfo: ["transactionId": transactionId]
            )
          }
        }
      }
      completionHandler()
      return
    }

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

    // Check if this is a group invitation notification (local or CloudKit push)
    if let invitationId = extractInvitationIdFromCloudKitPush(userInfo) ??
        (userInfo["type"] as? String == "group_invitation" ? userInfo["invitationId"] as? String : nil) {
      // Add to history if from CloudKit push (background/killed app)
      let content = notification.request.content
      let historyId = "group_invitation_\(invitationId)"
      NotificationHistoryManager.shared.addNotification(
        id: historyId,
        title: content.title,
        body: content.body,
        type: .groupInvitation
      )
      NotificationHistoryManager.shared.markAsRead(id: historyId)

      // Fix 7a: If the invitation doesn't exist locally (app was killed),
      // fetch from the public DB first so the navigation handler finds it.
      let repo = BudgetGroupRepository()
      if repo.fetchInvitation(byId: invitationId) == nil {
        BudgetGroupService.shared.fetchRemoteInvitations {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
              name: .navigateToGroupInvitation,
              object: nil,
              userInfo: ["invitationId": invitationId]
            )
          }
        }
      } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          NotificationCenter.default.post(
            name: .navigateToGroupInvitation,
            object: nil,
            userInfo: ["invitationId": invitationId]
          )
        }
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

  // MARK: - CloudKit Push Helpers

  /// Extracts invitation ID from a CloudKit query notification push payload.
  /// CloudKit push userInfo contains a "ck" dictionary with "qry" > "rid" (record ID in format "invitation-<uuid>").
  private func extractInvitationIdFromCloudKitPush(_ userInfo: [AnyHashable: Any]) -> String? {
    guard let ck = userInfo["ck"] as? [String: Any],
          let qry = ck["qry"] as? [String: Any],
          let recordName = qry["rid"] as? String,
          recordName.hasPrefix("invitation-") else {
      return nil
    }
    return recordName.replacingOccurrences(of: "invitation-", with: "")
  }

  /// Directly queries the public DB for recent GroupActivityNotification records
  /// and shows local notifications for any that haven't been processed yet.
  /// This is the reliable fallback when CKQuerySubscription pushes are coalesced by iOS.
  private func fetchPublicGroupActivityNotifications() {
    guard let currentUID = AuthenticationManager.shared.currentUser?.uid else {
      logWarning("AppDelegate: fetchPublicGroupActivity — no current user")
      return
    }

    let groups = BudgetGroupService.shared.fetchAllGroups().filter { !$0.isDeleted }
    guard !groups.isEmpty else {
      logWarning("AppDelegate: fetchPublicGroupActivity — no groups")
      return
    }

    let groupIds = groups.map { $0.id }
    // Only fetch records from the last 5 minutes to avoid showing stale notifications
    let fiveMinutesAgo = Date().addingTimeInterval(-300) as NSDate
    let predicate = NSPredicate(format: "timestamp > %@", fiveMinutesAgo)
    let query = CKQuery(recordType: "GroupActivityNotification", predicate: predicate)

    let operation = CKQueryOperation(query: query)
    operation.resultsLimit = 20
    operation.desiredKeys = ["actorName", "action", "detail", "actorId", "targetRecordName", "groupId"]

    var fetchedRecords: [CKRecord] = []
    operation.recordMatchedBlock = { _, result in
      if case .success(let record) = result {
        fetchedRecords.append(record)
      }
    }
    operation.queryResultBlock = { result in
      DispatchQueue.main.async {
        logWarning("AppDelegate: fetchPublicGroupActivity — fetched \(fetchedRecords.count) records (result=\(result))")
        let processedKey = "GroupNotification_ProcessedRecordNames"
        var processed = UserDefaults.standard.stringArray(forKey: processedKey) ?? []

        for record in fetchedRecords {
          let recordName = record.recordID.recordName

          // Skip already-processed
          guard !processed.contains(recordName) else { continue }

          // Filter locally: only our groups, not our own actions
          guard let groupId = record["groupId"] as? String,
                groupIds.contains(groupId),
                let actorId = record["actorId"] as? String,
                actorId != currentUID,
                let actorName = record["actorName"] as? String,
                let action = record["action"] as? String,
                let detail = record["detail"] as? String else {
            continue
          }

          // Check logical key to avoid duplicating a notification already shown via push payload or zone sync
          let logicalKey = GroupNotificationManager.logicalDeduplicationKey(action: action, actorId: actorId, detail: detail)
          guard !processed.contains(logicalKey) else {
            processed.append(recordName)
            continue
          }

          processed.append(recordName)
          processed.append(logicalKey)
          logWarning("AppDelegate: fetchPublicGroupActivity — DELIVERING \(action) from \(actorName)")

          let content = UNMutableNotificationContent()
          content.title = actorName
          content.body = GroupNotificationManager.shared.notificationBody(for: action, detail: detail)
          content.sound = .default
          content.categoryIdentifier = "GROUP_ACTIVITY"
          var notifUserInfo: [String: Any] = ["action": action]
          if let targetRecordName = record["targetRecordName"] as? String {
            notifUserInfo["targetRecordName"] = targetRecordName
          }
          content.userInfo = notifUserInfo

          // Use logicalKey as identifier so iOS deduplicates across all paths
          let request = UNNotificationRequest(identifier: logicalKey, content: content, trigger: nil)
          UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
              logWarning("AppDelegate: fetchPublicGroupActivity — notification FAILED: \(error)")
            } else {
              logWarning("AppDelegate: fetchPublicGroupActivity — notification SUCCEEDED: \(logicalKey)")
            }
          }
        }

        if processed.count > 200 { processed = Array(processed.suffix(200)) }
        UserDefaults.standard.set(processed, forKey: processedKey)
      }
    }
    operation.qualityOfService = .userInitiated
    CloudKitManager.shared.publicDatabase.add(operation)
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
