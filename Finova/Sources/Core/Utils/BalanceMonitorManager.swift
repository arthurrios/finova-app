//
//  BalanceMonitorManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 17/01/25.
//

import Foundation
import UserNotifications

final class BalanceMonitorManager {
    private let transactionRepo: TransactionRepository
    private let budgetRepo: BudgetRepository
    private let notificationCenter = UNUserNotificationCenter.current()
    private let calendar = Calendar.current
    
    // Controle para evitar execuções muito frequentes
    private var lastMonitoringTime: Date?
    private let minimumMonitoringInterval: TimeInterval = 300 // 5 minutos
    
    init(
        transactionRepo: TransactionRepository = TransactionRepository(),
        budgetRepo: BudgetRepository = BudgetRepository()
    ) {
        self.transactionRepo = transactionRepo
        self.budgetRepo = budgetRepo
    }
    
    // MARK: - Public Methods
    
    /// Monitora o saldo do mês atual e agenda notificações se necessário
    func monitorCurrentMonthBalance() {
        // Verificar se já foi executado recentemente
        if let lastTime = lastMonitoringTime {
            let timeSinceLastMonitoring = Date().timeIntervalSince(lastTime)
            if timeSinceLastMonitoring < minimumMonitoringInterval {
                print("🔔 ⏰ Balance monitoring skipped - executed recently (\(Int(timeSinceLastMonitoring))s ago)")
                return
            }
        }
        
        // Atualizar tempo da última execução
        lastMonitoringTime = Date()
        
        let today = Date()
        let currentMonth = calendar.dateInterval(of: .month, for: today)!
        
        // Limpar notificações antigas primeiro
        removeOldNegativeBalanceNotifications()
        
        // Calcular saldo projetado para cada dia do mês
        let dailyBalanceProjection = calculateDailyBalanceProjectionInternal(for: currentMonth)
        
        // Verificar se há dias com saldo negativo
        let negativeBalanceDays = findNegativeBalanceDaysInternal(from: dailyBalanceProjection)
        
        if !negativeBalanceDays.isEmpty {
            scheduleNegativeBalanceNotifications(for: negativeBalanceDays)
        } else {
            // Remover notificações de saldo negativo se não há mais risco
            removeNegativeBalanceNotifications()
        }
    }
    
    /// Monitora o saldo usando dados do dashboard (método preferido)
    func monitorCurrentMonthBalance(with currentMonthData: MonthBudgetCardType) {
        // Verificar se já foi executado recentemente
        if let lastTime = lastMonitoringTime {
            let timeSinceLastMonitoring = Date().timeIntervalSince(lastTime)
            if timeSinceLastMonitoring < minimumMonitoringInterval {
                print("🔔 ⏰ Balance monitoring skipped - executed recently (\(Int(timeSinceLastMonitoring))s ago)")
                return
            }
        }
        
        // Atualizar tempo da última execução
        lastMonitoringTime = Date()
        
        // Limpar notificações antigas primeiro
        removeOldNegativeBalanceNotifications()
        
        // Usar o saldo atual do dashboard como ponto de partida
        // Preferir currentBalance (saldo atual) sobre finalBalance (saldo final do mês)
        let currentBalance = currentMonthData.currentBalance ?? currentMonthData.finalBalance ?? 0
        
        // Calcular projeção baseada no saldo atual do dashboard
        let dailyBalanceProjection = calculateDailyBalanceProjectionFromCurrentBalance(currentBalance: currentBalance)
        
        // Verificar se há dias com saldo negativo
        let negativeBalanceDays = findNegativeBalanceDaysInternal(from: dailyBalanceProjection)
        
        print("🔔 📊 Found \(negativeBalanceDays.count) negative balance days")
        for (index, date) in negativeBalanceDays.enumerated() {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM dd, yyyy"
            print("🔔    \(index + 1). \(dateFormatter.string(from: date))")
        }
        
        if !negativeBalanceDays.isEmpty {
            print("🔔 📅 Scheduling notifications for negative balance days...")
            scheduleNegativeBalanceNotifications(for: negativeBalanceDays)
        } else {
            print("🔔 ✅ No negative balance days found, removing notifications...")
            // Remover notificações de saldo negativo se não há mais risco
            removeNegativeBalanceNotifications()
        }
    }
    
    /// Remove todas as notificações de saldo negativo
    func removeNegativeBalanceNotifications() {
        notificationCenter.getPendingNotificationRequests { requests in
            let negativeBalanceIds = requests
                .filter { $0.identifier.hasPrefix("negative_balance_") }
                .map { $0.identifier }
            
            if !negativeBalanceIds.isEmpty {
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: negativeBalanceIds)
                print("🔔 🧹 Removed \(negativeBalanceIds.count) negative balance notifications")
            }
        }
    }
    
    /// Remove notificações de saldo negativo antigas (para datas que já passaram)
    func removeOldNegativeBalanceNotifications() {
        let today = Date()
        
        notificationCenter.getPendingNotificationRequests { requests in
            let oldNegativeBalanceIds = requests
                .filter { request in
                    guard request.identifier.hasPrefix("negative_balance_") else { return false }
                    
                    // Extrair a data da notificação do userInfo
                    if let userInfo = request.content.userInfo as? [String: Any],
                       let negativeDateTimestamp = userInfo["negativeDate"] as? TimeInterval {
                        let negativeDate = Date(timeIntervalSince1970: negativeDateTimestamp)
                        return negativeDate < today
                    }
                    return false
                }
                .map { $0.identifier }
            
            if !oldNegativeBalanceIds.isEmpty {
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: oldNegativeBalanceIds)
                print("🔔 🧹 Removed \(oldNegativeBalanceIds.count) old negative balance notifications")
            }
        }
    }
    
    // MARK: - Internal Methods (for testing)
    
    /// Método interno para testes - calcula projeção de saldo
    func calculateDailyBalanceProjection(for monthInterval: DateInterval) -> [Date: Int] {
        return calculateDailyBalanceProjectionInternal(for: monthInterval)
    }
    
    /// Método interno para testes - encontra dias com saldo negativo
    func findNegativeBalanceDays(from dailyBalance: [Date: Int]) -> [Date] {
        return findNegativeBalanceDaysInternal(from: dailyBalance)
    }
    
    // MARK: - Private Methods
    
    /// Calcula a projeção de saldo para cada dia do mês usando a mesma lógica do dashboard
    private func calculateDailyBalanceProjectionInternal(for monthInterval: DateInterval) -> [Date: Int] {
        let allTransactions = transactionRepo.fetchAllTransactions()
        
        // Usar a mesma lógica do dashboard para calcular o saldo atual
        let currentBalance = calculateCurrentBalanceLikeDashboard(allTransactions: allTransactions)
        
        // Filtrar transações futuras do mês atual
        let today = Date()
        let todayStart = calendar.startOfDay(for: today)
        
        let futureTransactions = allTransactions.filter { transaction in
            let txDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
            let txDateStart = calendar.startOfDay(for: txDate)
            return txDateStart > todayStart && calendar.isDate(txDate, equalTo: monthInterval.start, toGranularity: .month)
        }
        
        // Calcular projeção para os próximos 30 dias
        var dailyBalance: [Date: Int] = [:]
        var runningBalance = currentBalance
        
        // Adicionar o saldo atual para hoje
        dailyBalance[todayStart] = currentBalance
        
        // Calcular para os próximos 30 dias
        for dayOffset in 1...30 {
            guard let futureDate = calendar.date(byAdding: .day, value: dayOffset, to: todayStart) else {
                continue
            }
            
            let normalizedDate = calendar.startOfDay(for: futureDate)
            
            // Encontrar transações para este dia específico
            let transactionsForThisDay = futureTransactions.filter { transaction in
                let txDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
                let txDateStart = calendar.startOfDay(for: txDate)
                return calendar.isDate(txDateStart, inSameDayAs: normalizedDate)
            }
            
            let netForThisDay = transactionsForThisDay.reduce(0) { result, tx in
                tx.type == .income ? result + tx.amount : result - tx.amount
            }
            
            runningBalance += netForThisDay
            dailyBalance[normalizedDate] = runningBalance
        }
        
        return dailyBalance
    }
    
    /// Calcula a projeção de saldo a partir do saldo atual do dashboard
    private func calculateDailyBalanceProjectionFromCurrentBalance(currentBalance: Int) -> [Date: Int] {
        let allTransactions = transactionRepo.fetchAllTransactions()
        
        // Filtrar transações futuras
        let today = Date()
        let todayStart = calendar.startOfDay(for: today)
        
        let futureTransactions = allTransactions.filter { transaction in
            let txDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
            let txDateStart = calendar.startOfDay(for: txDate)
            return txDateStart > todayStart
        }
        
        // Calcular projeção para os próximos 30 dias
        var dailyBalance: [Date: Int] = [:]
        var runningBalance = currentBalance
        
        // Adicionar o saldo atual para hoje
        dailyBalance[todayStart] = currentBalance
        
        // Calcular para os próximos 30 dias
        for dayOffset in 1...30 {
            guard let futureDate = calendar.date(byAdding: .day, value: dayOffset, to: todayStart) else {
                continue
            }
            
            let normalizedDate = calendar.startOfDay(for: futureDate)
            
            // Encontrar transações para este dia específico
            let transactionsForThisDay = futureTransactions.filter { transaction in
                let txDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
                let txDateStart = calendar.startOfDay(for: txDate)
                return calendar.isDate(txDateStart, inSameDayAs: normalizedDate)
            }
            
            let netForThisDay = transactionsForThisDay.reduce(0) { result, tx in
                tx.type == .income ? result + tx.amount : result - tx.amount
            }
            
            runningBalance += netForThisDay
            dailyBalance[normalizedDate] = runningBalance
        }
        
        return dailyBalance
    }
    
    /// Encontra o primeiro dia com saldo negativo
    private func findNegativeBalanceDaysInternal(from dailyBalance: [Date: Int]) -> [Date] {
        let today = Date()
        let todayStart = calendar.startOfDay(for: today)
        
        // Ordenar os dias cronologicamente
        let sortedDays = dailyBalance.keys.sorted()
        
        // Encontrar o primeiro dia futuro com saldo negativo
        for date in sortedDays {
            guard date > todayStart else { continue } // Apenas dias futuros (excluindo hoje)
            
            if let balance = dailyBalance[date], balance < 0 {
                // Retornar apenas o primeiro dia negativo
                return [date]
            }
        }
        
        return []
    }
    
    /// Agenda notificações para dias com saldo negativo
    private func scheduleNegativeBalanceNotifications(for negativeDays: [Date]) {
        let today = Date()
        
        print("🔔 📅 Starting to schedule notifications for \(negativeDays.count) negative balance days...")
        
        // Primeiro, remover notificações existentes para evitar duplicatas
        removeNegativeBalanceNotifications()
        
        for negativeDay in negativeDays {
            // Calcular quantos dias faltam até o saldo ficar negativo
            // Usar startOfDay para normalizar as datas e obter o cálculo correto
            let todayStart = calendar.startOfDay(for: today)
            let negativeDayStart = calendar.startOfDay(for: negativeDay)
            let daysUntilNegative = calendar.dateComponents([.day], from: todayStart, to: negativeDayStart).day ?? 0
            
            print("🔔 📊 Processing negative day: \(negativeDay), days until negative: \(daysUntilNegative)")
            
            // Notificar apenas para dias futuros (amanhã em diante)
            guard daysUntilNegative >= 1 && daysUntilNegative <= 30 else { 
                print("🔔 ⏭️ Skipping notification - days until negative (\(daysUntilNegative)) not in range [1-30]")
                continue 
            }
            
            let notificationId = "negative_balance_\(negativeDay.timeIntervalSince1970)"
            
            // Criar conteúdo da notificação
            let content = UNMutableNotificationContent()
            content.title = "notification.negative.balance.title".localized
            
            // Formatar a data de acordo com o idioma
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd/MM" // Formato padrão DD/MM
            
            // Verificar se é inglês e ajustar formato
            if let languageCode = Locale.current.languageCode, languageCode == "en" {
                dateFormatter.dateFormat = "MM/dd" // Formato MM/DD para inglês
            }
            
            let formattedDate = dateFormatter.string(from: negativeDay)
            
            // Mensagem para dias futuros
            let bodyMessage = String(format: "notification.negative.balance.body".localized, daysUntilNegative, formattedDate)
            content.body = bodyMessage
            content.sound = .default
            content.categoryIdentifier = "NEGATIVE_BALANCE"
            content.userInfo = [
                "type": "negative_balance",
                "negativeDate": negativeDay.timeIntervalSince1970,
                "daysUntilNegative": daysUntilNegative,
                "formattedDate": formattedDate
            ]
            
            // Agendar para 8h da manhã do dia que o saldo ficará negativo
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: negativeDay)
            dateComponents.hour = 8
            dateComponents.minute = 0
            dateComponents.second = 0
            
            guard let notificationDate = calendar.date(from: dateComponents) else { continue }
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate), repeats: false)
            
            let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)
            
            notificationCenter.add(request) { error in
                if let error = error {
                    print("🔔 ❌ Error scheduling negative balance notification: \(error)")
                } else {
                    print("🔔 ✅ Scheduled negative balance notification for \(negativeDay) (in \(daysUntilNegative) days)")
                }
            }
        }
    }
    
    /// Verifica se há notificações de saldo negativo agendadas
    func hasNegativeBalanceNotifications() -> Bool {
        var hasNotifications = false
        let semaphore = DispatchSemaphore(value: 0)
        
        notificationCenter.getPendingNotificationRequests { requests in
            hasNotifications = requests.contains { $0.identifier.hasPrefix("negative_balance_") }
            semaphore.signal()
        }
        
        semaphore.wait()
        return hasNotifications
    }
    
    /// Debug: Lista todas as notificações de saldo negativo
    func debugNegativeBalanceNotifications() {
        notificationCenter.getPendingNotificationRequests { requests in
            let negativeBalanceRequests = requests.filter { $0.identifier.hasPrefix("negative_balance_") }
            
            print("🔔 Negative balance notifications: \(negativeBalanceRequests.count)")
            for request in negativeBalanceRequests {
                if let trigger = request.trigger as? UNCalendarNotificationTrigger,
                   let nextTriggerDate = trigger.nextTriggerDate() {
                    print("   \(request.identifier): \(nextTriggerDate)")
                    if let userInfo = request.content.userInfo as? [String: Any] {
                        print("      Days until negative: \(userInfo["daysUntilNegative"] ?? "unknown")")
                        print("      Formatted date: \(userInfo["formattedDate"] ?? "unknown")")
                    }
                }
            }
        }
    }
    
    /// Debug: Testa formatação de data para diferentes idiomas
    func debugDateFormatting() {
        // Use a specific date that works regardless of timezone
        var dateComponents = DateComponents()
        dateComponents.year = 2022
        dateComponents.month = 3
        dateComponents.day = 15
        dateComponents.hour = 12 // Use noon to avoid timezone issues
        dateComponents.minute = 0
        dateComponents.second = 0
        
        let calendar = Calendar.current
        guard let testDate = calendar.date(from: dateComponents) else {
            print("❌ Failed to create test date")
            return
        }
        
        // Test Portuguese format
        let ptFormatter = DateFormatter()
        ptFormatter.dateFormat = "dd/MM"
        let ptFormatted = ptFormatter.string(from: testDate)
        print("🇧🇷 Portuguese format (DD/MM): \(ptFormatted)")
        
        // Test English format
        let enFormatter = DateFormatter()
        enFormatter.dateFormat = "MM/dd"
        let enFormatted = enFormatter.string(from: testDate)
        print("🇺🇸 English format (MM/DD): \(enFormatted)")
        
        // Test current locale
        let currentLanguageCode = Locale.current.languageCode ?? "unknown"
        print("🌍 Current language code: \(currentLanguageCode)")
        
        let currentFormatter = DateFormatter()
        currentFormatter.dateFormat = currentLanguageCode == "en" ? "MM/dd" : "dd/MM"
        let currentFormatted = currentFormatter.string(from: testDate)
        print("📅 Current locale format: \(currentFormatted)")
    }
    
    /// Force trigger balance monitoring (bypasses time restrictions)
    func forceTriggerBalanceMonitoring() {
        print("🔍 ==================== FORCE TRIGGERING BALANCE MONITORING ====================")
        
        // Reset the last monitoring time to force execution
        lastMonitoringTime = nil
        
        // Run the monitoring
        monitorCurrentMonthBalance()
        
        print("🔍 ================================================================")
    }
    
    /// Clear all negative balance notifications (for cleanup)
    func clearAllNegativeBalanceNotifications() {
        print("🔔 🧹 Clearing all negative balance notifications...")
        removeNegativeBalanceNotifications()
    }
    
    /// Test method: Schedule immediate notification for tomorrow's negative balance
    func testTomorrowNegativeBalanceNotification() {
        print("🔔 🧪 Testing tomorrow's negative balance notification...")
        
        // Clear existing notifications first
        removeNegativeBalanceNotifications()
        
        // Get tomorrow's date
        let today = Date()
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }
        
        // Create test notification for tomorrow
        let notificationId = "test_negative_balance_tomorrow"
        let content = UNMutableNotificationContent()
        content.title = "🧪 Test: Negative Balance Alert"
        content.body = "This is a test notification for tomorrow's negative balance (Aug 13)"
        content.sound = .default
        content.categoryIdentifier = "NEGATIVE_BALANCE"
        content.userInfo = [
            "type": "test_negative_balance",
            "negativeDate": tomorrow.timeIntervalSince1970,
            "daysUntilNegative": 1,
            "formattedDate": "13/08"
        ]
        
        // Schedule for 5 seconds from now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("🔔 ❌ Error scheduling test notification: \(error)")
            } else {
                print("🔔 ✅ Test notification scheduled! You should receive it in 5 seconds.")
            }
        }
    }
    
    /// Test method: Schedule notification for 1 minute from now
    func testNegativeBalanceNotificationIn1Minute() {
        print("🔔 🧪 Testing negative balance notification in 1 minute...")
        
        // Clear existing notifications first
        removeNegativeBalanceNotifications()
        
        // Create test notification
        let notificationId = "test_negative_balance_1min"
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Negative Balance Alert"
        content.body = "Your balance will be negative tomorrow (Aug 13). Check your transactions and adjust your budget."
        content.sound = .default
        content.categoryIdentifier = "NEGATIVE_BALANCE"
        content.userInfo = [
            "type": "negative_balance",
            "negativeDate": Date().timeIntervalSince1970,
            "daysUntilNegative": 1,
            "formattedDate": "13/08"
        ]
        
        // Schedule for 1 minute from now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("🔔 ❌ Error scheduling 1-minute test notification: \(error)")
            } else {
                print("🔔 ✅ 1-minute test notification scheduled! You should receive it in 1 minute.")
            }
        }
    }
    
    /// Comprehensive debug method to identify balance monitoring issues
    func debugBalanceMonitoring() {
        print("🔍 ==================== BALANCE MONITORING DEBUG ====================")
        
        // 1. Check notification permissions
        debugNotificationPermissions()
        
        // 2. Check current balance projection
        debugCurrentBalanceProjection()
        
        // 3. Check pending notifications
        debugPendingNotifications()
        
        // 4. Check transaction data
        debugTransactionData()
        
        print("🔍 ================================================================")
    }
    
    /// Debug method using dashboard data for accurate balance
    func debugBalanceMonitoring(with currentMonthData: MonthBudgetCardType) {
        print("🔍 ==================== BALANCE MONITORING DEBUG (DASHBOARD DATA) ====================")
        
        // 1. Check notification permissions
        debugNotificationPermissions()
        
        // 2. Check current balance projection using dashboard data
        debugCurrentBalanceProjection(with: currentMonthData)
        
        // 3. Check pending notifications
        debugPendingNotifications()
        
        // 4. Check transaction data using dashboard data
        debugTransactionData(with: currentMonthData)
        
        print("🔍 ================================================================")
    }
    
    private func debugNotificationPermissions() {
        print("🔍 1️⃣ CHECKING NOTIFICATION PERMISSIONS...")
        
        notificationCenter.getNotificationSettings { settings in
            DispatchQueue.main.async {
                print("🔍    Authorization Status: \(self.authorizationStatusString(settings.authorizationStatus))")
                print("🔍    Alert Setting: \(self.settingString(settings.alertSetting))")
                print("🔍    Sound Setting: \(self.settingString(settings.soundSetting))")
                print("🔍    Badge Setting: \(self.settingString(settings.badgeSetting))")
                print("🔍    Lock Screen Setting: \(self.settingString(settings.lockScreenSetting))")
                
                if settings.authorizationStatus != .authorized {
                    print("🔍 ❌ ISSUE: Notification permissions not granted!")
                    print("🔍    💡 Solution: Go to Settings > Finova > Notifications and enable them")
                }
            }
        }
    }
    
    private func debugCurrentBalanceProjection() {
        print("🔍 2️⃣ CHECKING CURRENT BALANCE PROJECTION...")
        
        let today = Date()
        let currentMonth = calendar.dateInterval(of: .month, for: today)!
        
        let dailyBalanceProjection = calculateDailyBalanceProjectionInternal(for: currentMonth)
        let negativeBalanceDays = findNegativeBalanceDaysInternal(from: dailyBalanceProjection)
        
        print("🔍    Current date: \(today)")
        print("🔍    Current month interval: \(currentMonth.start) to \(currentMonth.end)")
        print("🔍    Days with projected balance: \(dailyBalanceProjection.count)")
        print("🔍    Days with negative balance: \(negativeBalanceDays.count)")
        
        if !negativeBalanceDays.isEmpty {
            print("🔍    📅 Negative balance days found:")
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM dd, yyyy"
            
            for (index, date) in negativeBalanceDays.enumerated() {
                let balance = dailyBalanceProjection[date] ?? 0
                let daysUntilNegative = calendar.dateComponents([.day], from: today, to: date).day ?? 0
                let formattedDate = dateFormatter.string(from: date)
                print("🔍       \(index + 1). \(formattedDate) - Balance: \(balance.currencyString) (in \(daysUntilNegative) days)")
            }
        } else {
            print("🔍    ✅ No negative balance days found in current projection")
        }
        
        // Show next 7 days of balance projection
        print("🔍    📊 Next 7 days balance projection:")
        let sortedDays = dailyBalanceProjection.keys.sorted()
        let next7Days = sortedDays.prefix(7)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd" // e.g., "Aug 12", "Aug 13"
        
        for date in next7Days {
            let balance = dailyBalanceProjection[date] ?? 0
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let dayLabel = isToday ? "TODAY" : dateFormatter.string(from: date)
            print("🔍       \(dayLabel): \(balance.currencyString)")
        }
    }
    
    private func debugCurrentBalanceProjection(with currentMonthData: MonthBudgetCardType) {
        print("🔍 2️⃣ CHECKING CURRENT BALANCE PROJECTION (DASHBOARD DATA)...")
        
        let today = Date()
        // Preferir currentBalance (saldo atual) sobre finalBalance (saldo final do mês)
        let currentBalance = currentMonthData.currentBalance ?? currentMonthData.finalBalance ?? 0
        
        print("🔍    Current date: \(today)")
        print("🔍    Dashboard final balance: \(currentMonthData.finalBalance?.currencyString ?? "nil")")
        print("🔍    Dashboard current balance: \(currentMonthData.currentBalance?.currencyString ?? "nil")")
        print("🔍    Using balance for projection: \(currentBalance.currencyString)")
        
        let dailyBalanceProjection = calculateDailyBalanceProjectionFromCurrentBalance(currentBalance: currentBalance)
        let negativeBalanceDays = findNegativeBalanceDaysInternal(from: dailyBalanceProjection)
        
        print("🔍    Days with projected balance: \(dailyBalanceProjection.count)")
        print("🔍    Days with negative balance: \(negativeBalanceDays.count)")
        
        if !negativeBalanceDays.isEmpty {
            print("🔍    📅 Negative balance days found:")
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM dd, yyyy"
            
            for (index, date) in negativeBalanceDays.enumerated() {
                let balance = dailyBalanceProjection[date] ?? 0
                let daysUntilNegative = calendar.dateComponents([.day], from: today, to: date).day ?? 0
                let formattedDate = dateFormatter.string(from: date)
                print("🔍       \(index + 1). \(formattedDate) - Balance: \(balance.currencyString) (in \(daysUntilNegative) days)")
            }
        } else {
            print("🔍    ✅ No negative balance days found in current projection")
        }
        
        // Show next 7 days of balance projection
        print("🔍    📊 Next 7 days balance projection:")
        let sortedDays = dailyBalanceProjection.keys.sorted()
        let next7Days = sortedDays.prefix(7)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd" // e.g., "Aug 12", "Aug 13"
        
        for date in next7Days {
            let balance = dailyBalanceProjection[date] ?? 0
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let dayLabel = isToday ? "TODAY" : dateFormatter.string(from: date)
            print("🔍       \(dayLabel): \(balance.currencyString)")
        }
    }
    
    private func debugPendingNotifications() {
        print("🔍 3️⃣ CHECKING PENDING NOTIFICATIONS...")
        
        notificationCenter.getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                let negativeBalanceRequests = requests.filter { $0.identifier.hasPrefix("negative_balance_") }
                let allRequests = requests.count
                
                print("🔍    Total pending notifications: \(allRequests)")
                print("🔍    Negative balance notifications: \(negativeBalanceRequests.count)")
                
                if negativeBalanceRequests.isEmpty {
                    print("🔍 ❌ ISSUE: No negative balance notifications pending!")
                } else {
                    print("🔍    📅 Pending negative balance notifications:")
                    for request in negativeBalanceRequests {
                        if let trigger = request.trigger as? UNCalendarNotificationTrigger,
                           let nextTriggerDate = trigger.nextTriggerDate() {
                            print("🔍       ID: \(request.identifier)")
                            print("🔍       Title: \(request.content.title)")
                            print("🔍       Body: \(request.content.body)")
                            print("🔍       Next trigger: \(nextTriggerDate)")
                            
                            if let userInfo = request.content.userInfo as? [String: Any] {
                                print("🔍       Days until negative: \(userInfo["daysUntilNegative"] ?? "unknown")")
                                print("🔍       Formatted date: \(userInfo["formattedDate"] ?? "unknown")")
                            }
                            print("🔍       ---")
                        }
                    }
                }
            }
        }
    }
    
    private func debugTransactionData() {
        print("🔍 4️⃣ CHECKING TRANSACTION DATA...")
        
        let allTransactions = transactionRepo.fetchAllTransactions()
        let today = Date()
        let currentMonth = calendar.dateInterval(of: .month, for: today)!
        
        // Filter transactions for current month
        let currentMonthTransactions = allTransactions.filter { transaction in
            let txDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
            return calendar.isDate(txDate, equalTo: currentMonth.start, toGranularity: .month)
        }
        
        // Filter future transactions using normalized date comparison
        let todayStart = calendar.startOfDay(for: today)
        let futureTransactions = currentMonthTransactions.filter { transaction in
            let txDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
            let txDateStart = calendar.startOfDay(for: txDate)
            return txDateStart > todayStart
        }
        
        print("🔍    Total transactions: \(allTransactions.count)")
        print("🔍    Current month transactions: \(currentMonthTransactions.count)")
        print("🔍    Future transactions: \(futureTransactions.count)")
        
        if !futureTransactions.isEmpty {
            print("🔍    📅 Future transactions (next 7 days):")
            let next7Days = futureTransactions.prefix(7)
            for tx in next7Days {
                let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                let txDateStart = calendar.startOfDay(for: txDate)
                let daysUntil = calendar.dateComponents([.day], from: todayStart, to: txDateStart).day ?? 0
                let type = tx.type == .income ? "💰 Income" : "💸 Expense"
                print("🔍       \(tx.title): \(tx.amount.currencyString) (\(type)) - in \(daysUntil) days")
            }
        }
        
        // Calculate current balance
        let currentBalance = calculateCurrentBalance()
        print("🔍    💰 Current balance: \(currentBalance.currencyString)")
    }
    
    private func debugTransactionData(with currentMonthData: MonthBudgetCardType) {
        print("🔍 4️⃣ CHECKING TRANSACTION DATA (DASHBOARD DATA)...")
        
        let allTransactions = transactionRepo.fetchAllTransactions()
        let today = Date()
        let currentMonth = calendar.dateInterval(of: .month, for: today)!
        
        // Filter transactions for current month
        let currentMonthTransactions = allTransactions.filter { transaction in
            let txDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
            return calendar.isDate(txDate, equalTo: currentMonth.start, toGranularity: .month)
        }
        
        // Filter future transactions using normalized date comparison
        let todayStart = calendar.startOfDay(for: today)
        let futureTransactions = currentMonthTransactions.filter { transaction in
            let txDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
            let txDateStart = calendar.startOfDay(for: txDate)
            return txDateStart > todayStart
        }
        
        print("🔍    Total transactions: \(allTransactions.count)")
        print("🔍    Current month transactions: \(currentMonthTransactions.count)")
        print("🔍    Future transactions: \(futureTransactions.count)")
        
        if !futureTransactions.isEmpty {
            print("🔍    📅 Future transactions (next 7 days):")
            let next7Days = futureTransactions.prefix(7)
            for tx in next7Days {
                let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                let txDateStart = calendar.startOfDay(for: txDate)
                let daysUntil = calendar.dateComponents([.day], from: todayStart, to: txDateStart).day ?? 0
                let type = tx.type == .income ? "💰 Income" : "💸 Expense"
                print("🔍       \(tx.title): \(tx.amount.currencyString) (\(type)) - in \(daysUntil) days")
            }
        }
        
        // Use dashboard current balance instead of calculating
        let currentBalance = currentMonthData.currentBalance ?? currentMonthData.finalBalance ?? 0
        print("🔍    💰 Current balance (from dashboard): \(currentBalance.currencyString)")
    }
    
    private func calculateCurrentBalance() -> Int {
        let allTransactions = transactionRepo.fetchAllTransactions()
        let today = Date()
        
        // Get all transactions up to today
        let transactionsUpToToday = allTransactions.filter { transaction in
            let txDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
            return txDate <= today
        }
        
        let netBalance = transactionsUpToToday.reduce(0) { result, tx in
            tx.type == .income ? result + tx.amount : result - tx.amount
        }
        
        return netBalance
    }
    
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
    
    /// Calcula o saldo atual usando a mesma lógica do dashboard (finalBalance)
    private func calculateCurrentBalanceLikeDashboard(allTransactions: [Transaction]) -> Int {
        // Usar a mesma lógica do DashboardViewModel.loadMonthlyCards()
        let today = Date()
        
        // Calcular o saldo acumulado (running balance) como o dashboard faz
        let allTxs = allTransactions
        
        let expensesByAnchor = allTxs
            .filter { $0.type == .expense }
            .reduce(into: [:]) { acc, tx in
                acc[tx.budgetMonthDate, default: 0] += tx.amount
            }
        
        let incomesByAnchor = allTxs
            .filter { $0.type == .income }
            .reduce(into: [:]) { acc, tx in
                acc[tx.budgetMonthDate, default: 0] += tx.amount
            }
        
        // Calcular o running balance até o mês atual
        var previousAvailable = 0
        
        // Pegar todos os meses até o mês atual
        let currentMonth = calendar.dateInterval(of: .month, for: today)!
        let currentMonthAnchor = currentMonth.start.monthAnchor
        
        // Calcular o saldo acumulado até o mês anterior
        let allAnchors = allTxs.map { $0.budgetMonthDate }.sorted()
        let anchorsUpToCurrent = allAnchors.filter { $0 <= currentMonthAnchor }
        
        for anchor in anchorsUpToCurrent {
            let expense = expensesByAnchor[anchor] ?? 0
            let income = incomesByAnchor[anchor] ?? 0
            let net = income - expense
            previousAvailable += net
        }
        
        return previousAvailable
    }
} 