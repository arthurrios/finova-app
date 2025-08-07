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
    
    /// Calcula a projeção de saldo para cada dia do mês
    private func calculateDailyBalanceProjectionInternal(for monthInterval: DateInterval) -> [Date: Int] {
        let allTransactions = transactionRepo.fetchAllTransactions()
        let budgets = budgetRepo.fetchBudgets()
        
        // Encontrar o saldo inicial do mês (saldo do mês anterior)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: monthInterval.start)!
        let previousMonthAnchor = previousMonth.monthAnchor
        let previousMonthTransactions = allTransactions.filter { transaction in
            let txDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
            return calendar.isDate(txDate, equalTo: previousMonth, toGranularity: .month)
        }
        
        let previousMonthNet = previousMonthTransactions.reduce(0) { result, tx in
            tx.type == .income ? result + tx.amount : result + tx.amount
        }
        
        // Saldo inicial (assumindo que o usuário começa com saldo positivo)
        let initialBalance = max(0, previousMonthNet)
        
        // Filtrar transações do mês atual (incluindo transações projetadas)
        let currentMonthTransactions = allTransactions.filter { transaction in
            let txDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
            return calendar.isDate(txDate, equalTo: monthInterval.start, toGranularity: .month)
        }
        
        // Calcular saldo para cada dia do mês
        var dailyBalance: [Date: Int] = [:]
        var runningBalance = initialBalance
        
        // Gerar todos os dias do mês
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthInterval.start)!
        
        for day in daysInMonth {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) else {
                continue
            }
            
            // Normalizar a data para o início do dia
            let normalizedDate = calendar.startOfDay(for: date)
            
            // Calcular transações até este dia (incluindo transações projetadas)
            let transactionsUpToDate = currentMonthTransactions.filter { transaction in
                let txDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
                return txDate <= date
            }
            
            let netUpToDate = transactionsUpToDate.reduce(0) { result, tx in
                tx.type == .income ? result + tx.amount : result + tx.amount
            }
            
            let balanceForDate = initialBalance + netUpToDate
            dailyBalance[normalizedDate] = balanceForDate
            runningBalance = balanceForDate
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
            guard date >= todayStart else { continue } // Apenas dias futuros (incluindo hoje)
            
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
        
        // Primeiro, remover notificações existentes para evitar duplicatas
        removeNegativeBalanceNotifications()
        
        for negativeDay in negativeDays {
            // Calcular quantos dias faltam até o saldo ficar negativo
            let daysUntilNegative = calendar.dateComponents([.day], from: today, to: negativeDay).day ?? 0
            
            // Só notificar se faltam entre 1 e 30 dias
            guard daysUntilNegative >= 1 && daysUntilNegative <= 30 else { continue }
            
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
            content.body = String(format: "notification.negative.balance.body".localized, daysUntilNegative, formattedDate)
            content.sound = .default
            content.categoryIdentifier = "NEGATIVE_BALANCE"
            content.userInfo = [
                "type": "negative_balance",
                "negativeDate": negativeDay.timeIntervalSince1970,
                "daysUntilNegative": daysUntilNegative,
                "formattedDate": formattedDate
            ]
            
            // Agendar para 8h da manhã do dia atual
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: today)
            dateComponents.hour = 8
            dateComponents.minute = 0
            dateComponents.second = 0
            
            guard let notificationDate = calendar.date(from: dateComponents) else { continue }
            
            // Se já passou das 8h hoje, agendar para amanhã
            let finalNotificationDate = notificationDate < today 
                ? calendar.date(byAdding: .day, value: 1, to: notificationDate) ?? notificationDate
                : notificationDate
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: finalNotificationDate), repeats: false)
            
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
} 