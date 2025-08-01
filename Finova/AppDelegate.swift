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
        
        // 🔔 Setup monthly notification system
        setupMonthlyNotificationSystem()
        
        // 🔔 Check if this is first time opening app in new month and schedule notifications
        checkAndScheduleMonthlyNotificationsOnFirstLaunch()
        
#if DEBUG
        // 🧪 Debug: Show data status on app launch
        DebugDataManager.shared.showDataStatus()
#endif
        
        return true
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
        print("🔄 App will enter foreground")
        
        // Reagendar notificações para transações próximas
        rescheduleNearbyNotifications()
        
        // Monitorar saldo negativo quando o app voltar ao foreground
        monitorNegativeBalance()
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
                return
            }
            
            // Schedule notifications for all future transactions
            // This will be called once on app launch to ensure notifications are set up
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {  // Delay to ensure data is loaded
                self.scheduleAllTransactionNotifications()
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
        
        // Authenticate SecureLocalDataManager
        SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)
        
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
        
        // Limitar a 50 notificações para evitar problemas com limite do iOS
        let limitedTxs = Array(futureTxs.prefix(50))
        if limitedTxs.count < futureTxs.count {
            print("🔔 ⚠️ Limited notifications to 50 (iOS limit). \(futureTxs.count - limitedTxs.count) transactions will not have notifications")
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
            let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
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
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm"
                    print("🔔 ✅ Scheduled notification for \(tx.title) at \(formatter.string(from: notificationDate))")
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
            
            SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)
            
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
            
            // Check if this is a monthly notification that should trigger success alert
            if let notificationType = userInfo["type"] as? String {
                switch notificationType {
                case "monthly_reminder", "monthly_fallback":
                    print("🔔 📅 Monthly notification tapped - scheduling notifications with success alert")
                    
                    // Schedule monthly notifications without showing alert immediately
                    // The alert will be shown when the dashboard appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { // Delay to ensure app is fully loaded
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
                    print("🔔 📅 Recurring/installment reminder tapped - scheduling notifications with success alert")
                    
                    // Schedule monthly notifications without showing alert immediately
                    // The alert will be shown when the dashboard appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { // Delay to ensure app is fully loaded
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
            
            // Authenticate SecureLocalDataManager
            SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)
            
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
            
            // Authenticate SecureLocalDataManager
            SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)
            
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
            
            // Authenticate SecureLocalDataManager
            SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)
            
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { // Delay to ensure app is fully loaded
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
