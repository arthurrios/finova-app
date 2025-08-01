//
//  MonthlyNotificationManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 17/01/25.
//

import Foundation
import UserNotifications
import UIKit

final class MonthlyNotificationManager {
    private let transactionRepo: TransactionRepository
    private let budgetRepo: BudgetRepository
    private let balanceMonitor: BalanceMonitorManager
    private let notificationCenter = UNUserNotificationCenter.current()
    private let calendar = Calendar.current
    
    init(
        transactionRepo: TransactionRepository = TransactionRepository(),
        budgetRepo: BudgetRepository = BudgetRepository()
    ) {
        self.transactionRepo = transactionRepo
        self.budgetRepo = budgetRepo
        self.balanceMonitor = BalanceMonitorManager(transactionRepo: transactionRepo, budgetRepo: budgetRepo)
    }
    
    // MARK: - Public Methods
    
    /// Configura o sistema de notificações mensais
    func setupMonthlyNotificationSystem() {
        scheduleMonthlyReminderNotification()
        scheduleMonthlyFallbackNotification()
    }
    
    /// Agenda todas as notificações do mês atual
    func scheduleAllMonthlyNotifications(showAlert: Bool = true) -> Bool {
        print("🔔 📅 Scheduling all monthly notifications...")
        
        // Verificar permissões
        var hasPermission = false
        let semaphore = DispatchSemaphore(value: 0)
        
        notificationCenter.getNotificationSettings { settings in
            hasPermission = settings.authorizationStatus == .authorized
            semaphore.signal()
        }
        
        semaphore.wait()
        
        guard hasPermission else {
            print("🔔 ❌ Notification permission not granted")
            if showAlert {
                showPermissionDeniedAlert()
            }
            return false
        }
        
        // Verificar se já foram agendadas para este mês
        let alreadyScheduled = areNotificationsScheduledForCurrentMonth()
        
        // Limpar notificações existentes
        clearExistingMonthlyNotifications()
        
        // Agendar notificações de transações
        let transactionSuccess = scheduleTransactionNotifications()
        
        // Agendar notificações de saldo negativo
        let balanceSuccess = scheduleBalanceNotifications()
        
        // Agendar notificações de parcelas/recorrentes
        let recurringSuccess = scheduleRecurringNotifications()
        
        let overallSuccess = transactionSuccess && balanceSuccess && recurringSuccess
        
        if overallSuccess {
            print("🔔 ✅ All monthly notifications scheduled successfully")
            if showAlert {
                if alreadyScheduled {
                    showRescheduledAlert()
                } else {
                    showSuccessAlert()
                }
            }
        } else {
            print("🔔 ⚠️ Some notifications failed to schedule")
            if showAlert {
                showFailureAlert()
            }
        }
        
        return overallSuccess
    }
    
    /// Verifica se as notificações do mês foram configuradas
    func checkMonthlyNotificationsStatus() -> MonthlyNotificationStatus {
        var status = MonthlyNotificationStatus.notConfigured
        let semaphore = DispatchSemaphore(value: 0)
        
        notificationCenter.getPendingNotificationRequests { requests in
            let monthlyRequests = requests.filter { request in
                request.identifier.hasPrefix("monthly_") ||
                request.identifier.hasPrefix("transaction_") ||
                request.identifier.hasPrefix("negative_balance_") ||
                request.identifier.hasPrefix("recurring_") ||
                request.identifier.hasPrefix("installment_")
            }
            
            if monthlyRequests.isEmpty {
                status = .notConfigured
            } else {
                let currentMonth = self.calendar.component(.month, from: Date())
                let currentYear = self.calendar.component(.year, from: Date())
                
                let hasCurrentMonthNotifications = monthlyRequests.contains { request in
                    if let trigger = request.trigger as? UNCalendarNotificationTrigger,
                       let nextTriggerDate = trigger.nextTriggerDate() {
                        let triggerMonth = self.calendar.component(.month, from: nextTriggerDate)
                        let triggerYear = self.calendar.component(.year, from: nextTriggerDate)
                        return triggerMonth == currentMonth && triggerYear == currentYear
                    }
                    return false
                }
                
                status = hasCurrentMonthNotifications ? .configured : .outdated
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return status
    }
    
    /// Verifica se as notificações já foram agendadas para o mês atual
    func areNotificationsScheduledForCurrentMonth() -> Bool {
        let currentDate = Date()
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: currentDate)
        let currentYear = calendar.component(.year, from: currentDate)
        let currentMonthKey = "\(currentYear)-\(currentMonth)"
        
        let lastScheduledMonthKey = UserDefaults.standard.string(forKey: "lastScheduledMonthKey")
        return lastScheduledMonthKey == currentMonthKey
    }
    
    // MARK: - Private Methods
    
    /// Agenda notificação de lembrete mensal
    private func scheduleMonthlyReminderNotification() {
        let today = Date()
        let firstDayOfMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        
        // Se já passou do primeiro dia, agendar para o próximo mês
        let targetDate = firstDayOfMonth > today ? firstDayOfMonth : calendar.date(byAdding: .month, value: 1, to: firstDayOfMonth) ?? firstDayOfMonth
        
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
        dateComponents.hour = 8
        dateComponents.minute = 0
        dateComponents.second = 0
        
        guard let notificationDate = calendar.date(from: dateComponents) else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "notification.monthly.reminder.title".localized
        content.body = "notification.monthly.reminder.body".localized
        content.sound = .default
        content.categoryIdentifier = "MONTHLY_REMINDER"
        content.userInfo = ["type": "monthly_reminder"]
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: "monthly_reminder_\(targetDate.timeIntervalSince1970)", content: content, trigger: trigger)
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("🔔 ❌ Error scheduling monthly reminder: \(error)")
            } else {
                print("🔔 ✅ Monthly reminder scheduled for \(notificationDate)")
            }
        }
    }
    
    /// Agenda notificação de fallback (3º dia do mês)
    private func scheduleMonthlyFallbackNotification() {
        let today = Date()
        let firstDayOfMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        
        // 3º dia do mês atual ou próximo mês
        let thirdDayOfMonth = calendar.date(byAdding: .day, value: 2, to: firstDayOfMonth) ?? firstDayOfMonth
        let targetDate = thirdDayOfMonth > today ? thirdDayOfMonth : calendar.date(byAdding: .month, value: 1, to: thirdDayOfMonth) ?? thirdDayOfMonth
        
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
        dateComponents.hour = 10 // 10h para não conflitar com a de 8h
        dateComponents.minute = 0
        dateComponents.second = 0
        
        guard let notificationDate = calendar.date(from: dateComponents) else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "notification.monthly.fallback.title".localized
        content.body = "notification.monthly.fallback.body".localized
        content.sound = .default
        content.categoryIdentifier = "MONTHLY_FALLBACK"
        content.userInfo = ["type": "monthly_fallback"]
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: "monthly_fallback_\(targetDate.timeIntervalSince1970)", content: content, trigger: trigger)
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("🔔 ❌ Error scheduling monthly fallback: \(error)")
            } else {
                print("🔔 ✅ Monthly fallback scheduled for \(notificationDate)")
            }
        }
    }
    
    /// Limpa notificações mensais existentes
    private func clearExistingMonthlyNotifications() {
        notificationCenter.getPendingNotificationRequests { requests in
            let monthlyIds = requests
                .filter { request in
                    request.identifier.hasPrefix("transaction_") ||
                    request.identifier.hasPrefix("negative_balance_") ||
                    request.identifier.hasPrefix("recurring_") ||
                    request.identifier.hasPrefix("installment_")
                }
                .map { $0.identifier }
            
            if !monthlyIds.isEmpty {
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: monthlyIds)
                print("🔔 🧹 Cleared \(monthlyIds.count) existing monthly notifications")
            }
        }
    }
    
    /// Agenda notificações de transações
    private func scheduleTransactionNotifications() -> Bool {
        // Usar lógica existente do AppDelegate
        let allTxs = transactionRepo.fetchAllTransactions()
        let now = Date()
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        
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
            notificationDate = calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate
            
            return notificationDate > now
        }
        
        let limitedTxs = Array(futureTxs.prefix(30)) // Limitar a 30 para o mês
        
        limitedTxs.forEach { tx in
            scheduleTransactionNotification(for: tx, calendar: calendar)
        }
        
        print("🔔 📊 Scheduled \(limitedTxs.count) transaction notifications")
        return true
    }
    
    /// Agenda notificação individual de transação
    private func scheduleTransactionNotification(for tx: Transaction, calendar: Calendar) {
        guard let transactionId = tx.id else { return }
        
        let id = "transaction_\(transactionId)"
        
        // Create notification time (8 AM) in local timezone
        var notificationDate = calendar.startOfDay(for: tx.date)
        notificationDate = calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate
        
        // Only schedule if notification time is in the future
        guard notificationDate > Date() else { return }
        
        // Verificar se a data é muito no futuro (mais de 1 ano)
        let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        if tx.date > oneYearFromNow {
            return
        }
        
        // Calculate time interval from now to notification date
        let timeInterval = notificationDate.timeIntervalSinceNow
        
        // Verificar se o intervalo é muito grande (mais de 30 dias)
        let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60
        if timeInterval > thirtyDaysInSeconds {
            return
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        
        let titleKey = tx.type == .income ? "notification.transaction.title.income" : "notification.transaction.title.expense"
        let bodyKey = tx.type == .income ? "notification.transaction.body.income" : "notification.transaction.body.expense"
        
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
        notificationCenter.add(request) { error in
            if let error = error {
                print("🔔 ❌ Error scheduling transaction notification: \(error)")
            }
        }
    }
    
    /// Agenda notificações de saldo negativo
    private func scheduleBalanceNotifications() -> Bool {
        balanceMonitor.monitorCurrentMonthBalance()
        return true
    }
    
    /// Agenda notificações de transações recorrentes/parceladas
    private func scheduleRecurringNotifications() -> Bool {
        // Esta lógica seria implementada aqui
        // Por enquanto, retorna true
        return true
    }
    
    /// Mostra alerta de sucesso
    func showSuccessAlert() {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "notification.monthly.success.title".localized,
                message: "notification.monthly.success.body".localized,
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            // Encontrar o view controller ativo para apresentar o alerta
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                
                var topViewController = rootViewController
                while let presentedViewController = topViewController.presentedViewController {
                    topViewController = presentedViewController
                }
                
                topViewController.present(alert, animated: true)
            }
        }
    }
    
    /// Mostra alerta de reagendamento
    func showRescheduledAlert() {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "notification.monthly.rescheduled.title".localized,
                message: "notification.monthly.rescheduled.body".localized,
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            // Encontrar o view controller ativo para apresentar o alerta
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                
                var topViewController = rootViewController
                while let presentedViewController = topViewController.presentedViewController {
                    topViewController = presentedViewController
                }
                
                topViewController.present(alert, animated: true)
            }
        }
    }
    
    /// Mostra alerta de falha
    func showFailureAlert() {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "notification.monthly.failure.title".localized,
                message: "notification.monthly.failure.body".localized,
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            // Encontrar o view controller ativo para apresentar o alerta
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                
                var topViewController = rootViewController
                while let presentedViewController = topViewController.presentedViewController {
                    topViewController = presentedViewController
                }
                
                topViewController.present(alert, animated: true)
            }
        }
    }
    
    /// Mostra alerta de permissão negada
    func showPermissionDeniedAlert() {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "notification.monthly.permission.title".localized,
                message: "notification.monthly.permission.body".localized,
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            // Encontrar o view controller ativo para apresentar o alerta
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                
                var topViewController = rootViewController
                while let presentedViewController = topViewController.presentedViewController {
                    topViewController = presentedViewController
                }
                
                topViewController.present(alert, animated: true)
            }
        }
    }
}

// MARK: - Supporting Types

enum MonthlyNotificationStatus {
    case notConfigured
    case configured
    case outdated
} 
