//
//  DemoSeedGenerator.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

#if DEBUG || DEMO
import Foundation
import UIKit
import UserNotifications

/// Wipes the local ledger and writes a showcase one: twelve months of history, so budget history
/// offers its longer range, an open month with spending on any date, the next three months planned, two credit cards with paid, closed and open statements, installment purchases (one paid
/// early, one cancelled), recurring bills, category allocations and monthly budgets. No family group
/// and no sync data: this version has neither. The content comes from `DemoDataset`: the Brazilian
/// ledger for BRL (the default), the American one for any other currency.
///
/// Everything is written through the paths the app itself uses (`AddTransactionModalViewModel`,
/// `StatementPaymentService`, `BudgetAllocationService`...), so statements, installment due dates
/// and totals agree the way they would after a user typed it all in.
///
/// Destructive by design: only ever run it in a sandbox whose data is disposable (Finova Demo, or a
/// DEBUG build with the seed switch on).
struct DemoSeedGenerator {

    // MARK: - State

    /// The dataset on disk ("BRL" or "USD" — `DemoDataset.currency`), not the app currency.
    private static let seededDatasetKey = "demoSeededDataset"
    private static let seededMonthKey = "demoSeededMonth"
    /// Bumped when the showcase itself changes, so an install seeded by an older build is redone.
    /// 2: no family group (this version has none).
    /// 3: twelve months of history, and an open month that has categories over and left so far.
    private static let seedVersionKey = "demoSeedVersion"
    private static let seedVersion = 3
    private static let seedQueue = DispatchQueue(label: "com.finova.demoseed", qos: .userInitiated)
    private static let lock = NSLock()
    private static var _isSeeding = false

    /// True while a seed is writing. Lets per-row observers (the balance monitor) sit it out instead
    /// of recomputing — and rescheduling notifications — once per inserted row.
    static var isSeeding: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isSeeding
    }

    private static func setSeeding(_ value: Bool) {
        lock.lock(); _isSeeding = value; lock.unlock()
    }

    // MARK: - Demo policy

    /// Finova Demo's first launch picks BRL, so the default showcase is the Brazilian one. After that
    /// the user's own choice in Settings (including "auto") is left alone.
    static func applyDemoDefaultsIfNeeded() {
        guard UserDefaults.standard.string(forKey: seededDatasetKey) == nil,
              UserDefaultsManager.isUsingAutoCurrency() else { return }
        UserDefaultsManager.setCurrencyCode("BRL")
    }

    /// Whether the ledger on disk is not the one for the current currency and month — i.e. first
    /// launch, a switch between BRL and anything else, a new month (so "this month" is never empty),
    /// or a seed written by an older showcase.
    static var needsSeed: Bool {
        UserDefaults.standard.string(forKey: seededDatasetKey)
            != DemoDataset.forCurrency(AppConfig.currencyCode).currency
            || UserDefaults.standard.integer(forKey: seededMonthKey) != Date().monthAnchor
            || UserDefaults.standard.integer(forKey: seedVersionKey) != seedVersion
    }

    #if DEMO
    private static var isWatchingCurrency = false

    /// In Finova Demo, switching the currency in Settings swaps in that currency's showcase. The
    /// reseed runs from a fresh splash so no data screen is alive while the rows are rewritten.
    static func startWatchingCurrencyChanges() {
        guard !isWatchingCurrency else { return }
        isWatchingCurrency = true
        NotificationCenter.default.addObserver(
            forName: .currencyDidChange, object: nil, queue: .main
        ) { _ in
            guard needsSeed else { return }
            logInfo("[DemoSeed] Currency is now \(AppConfig.currencyCode) — restarting to reseed")
            restartAppFlow()
        }
    }

    private static func restartAppFlow() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let sceneDelegate = scene.delegate as? SceneDelegate,
              let window = sceneDelegate.window
        else { return }
        let restart = {
            let flow = AppFlowController()
            sceneDelegate.flowController = flow
            window.rootViewController = flow.startFlow()
        }
        if let presented = window.rootViewController?.presentedViewController {
            presented.dismiss(animated: false, completion: restart)
        } else {
            restart()
        }
    }
    #endif

    // MARK: - Entry Point

    /// Seeds on a background queue and calls `completion` on the main queue when done. Background
    /// because creating a recurring card charge completes asynchronously on the main queue, and
    /// because a few thousand rows would otherwise freeze the splash.
    static func seed(for userUID: String, completion: @escaping () -> Void) {
        seedQueue.async {
            let started = Date()
            setSeeding(true)
            // On a fresh install this pass may still be queued at background priority. Left there, it
            // could land mid-seed and delete the rows written so far, which once took the salary.
            // After this call the queued pass finds it done (the manager locks it) and does nothing.
            DataCleanupManager.shared.performGlobalDataCleanup()
            let dataset = DemoDataset.forCurrency(AppConfig.currencyCode)
            logInfo("[DemoSeed] Seeding \(dataset.currency) for UID: \(userUID)")

            clearAll()
            Writer(dataset: dataset, userUID: userUID).run()

            UserDefaults.standard.set(dataset.currency, forKey: seededDatasetKey)
            UserDefaults.standard.set(Date().monthAnchor, forKey: seededMonthKey)
            UserDefaults.standard.set(seedVersion, forKey: seedVersionKey)
            setSeeding(false)
            TransactionRepository.invalidateCache()
            StatementNotificationManager.shared.rescheduleAllNotifications()
            logInfo("[DemoSeed] Seed complete in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")

            DispatchQueue.main.async {
                for name: Notification.Name in [
                    .transactionDataChanged, .budgetDataChanged, .creditCardDataChanged,
                    .allocationDataChanged,
                ] {
                    NotificationCenter.default.post(name: name, object: nil)
                }
                completion()
            }
        }
    }

    // MARK: - Clear Phase

    /// Hard-deletes the whole ledger in a handful of statements. Going row by row through the
    /// repositories cancelled each row's notifications with its own synchronous XPC round-trip —
    /// the ~90 s first-launch stall — so notifications are dropped in one call instead.
    private static func clearAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        let db = DBHelper.shared
        // The group tables are emptied too: an install seeded by a build that had family groups keeps
        // no group, member or invitation after a reseed.
        for table in [
            "Transactions", "Budgets", "BudgetAllocations", "CreditCardStatements", "CreditCards",
            "GroupMembers", "GroupInvitations", "BudgetGroups", "ImportBatchRows", "ImportBatches",
        ] {
            db.executeSyncUpdate("DELETE FROM \(table);")
        }
        UserDefaults.standard.removeObject(forKey: "budgetAllocations")
        ProfileImageManager.shared.removeProfileImage()
        UIDUserDefaultsManager.shared.setCurrentUserBalanceOffset(0)
        TransactionRepository.invalidateCache()
    }
}

// MARK: - Writer

private struct Writer {
    let dataset: DemoDataset
    let userUID: String

    private let cal = Calendar.current
    private let now = Date()
    private let txRepo = TransactionRepository()
    private let cardRepo = CreditCardRepository()
    private let stmtRepo = StatementRepository()
    private let historyOffsets = Array(-11...0)
    private let seededOffsets = Array(-11...3)

    init(dataset: DemoDataset, userUID: String) {
        self.dataset = dataset
        self.userUID = userUID
    }

    func run() {
        let viewModel = AddTransactionModalViewModel(transactionRepo: txRepo)
        let cards = insertCards()

        for item in dataset.items {
            write(item, cards: cards, viewModel: viewModel)
        }
        payEarly()
        cancelPurchase()
        payPastStatements(cards: cards)
        insertAllocationsAndBudgets()
    }

    // MARK: Dates

    private var firstOfThisMonth: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
    }

    private func date(day: Int, monthOffset: Int) -> Date {
        let month = cal.date(byAdding: .month, value: monthOffset, to: firstOfThisMonth) ?? now
        let days = cal.range(of: .day, in: .month, for: month)?.count ?? 28
        var comps = cal.dateComponents([.year, .month], from: month)
        comps.day = min(max(day, 1), days)
        comps.hour = 12
        return cal.date(from: comps) ?? month
    }

    private func dateString(_ date: Date) -> String {
        DateFormatter.fullDateFormatter.string(from: date)
    }

    private func minor(_ amount: Double) -> Int {
        DemoAmounts.minor(amount, currency: dataset.currency)
    }

    /// Day-to-day spending: the base amount with a stable wobble.
    private func variedMinor(_ item: DemoDataset.Item, salt: Int) -> Int {
        minor(item.amount * DemoAmounts.jitter(item.title, salt))
    }

    // MARK: Cards

    /// Closing and due days are chosen from today, so on any date the `.open` card's current
    /// statement is still open and the `.closed` card's has closed but is not yet due.
    private func insertCards() -> [CreditCard] {
        let today = cal.component(.day, from: now)
        func wrap(_ day: Int) -> Int { ((day - 1) % 28 + 28) % 28 + 1 }

        return dataset.cards.enumerated().compactMap { index, def in
            let closing = def.role == .open ? wrap(today + 7) : wrap(today - 5)
            let due = wrap(closing + (def.role == .open ? 7 : 9))
            let card = CreditCard(
                id: nil, name: def.name, lastFourDigits: def.lastFour, cardBrand: def.brand,
                closingDay: closing, dueDay: due, creditLimit: minor(def.limit),
                cardColor: def.color, userId: userUID, isDeleted: false, isDefault: index == 0,
                createdAt: now, updatedAt: now)
            guard let id = cardRepo.insertCard(card) else {
                logError("[DemoSeed] Failed to insert card \(def.name)")
                return nil
            }
            return cardRepo.fetchCard(byId: id)
        }
    }

    private func cardId(_ index: Int?, _ cards: [CreditCard]) -> Int? {
        guard let index = index, cards.indices.contains(index) else { return nil }
        return cards[index].id
    }

    // MARK: Items

    private func write(_ item: DemoDataset.Item, cards: [CreditCard],
                       viewModel: AddTransactionModalViewModel) {
        let typeRaw = String(describing: item.type)
        let categoryKey = item.category.key

        func addOneOff(_ date: Date, amount: Int, card: Int?) {
            let result = viewModel.addTransaction(
                title: item.title, amount: amount, dateString: dateString(date),
                categoryKey: categoryKey, typeRaw: typeRaw, creditCardId: cardId(card, cards))
            if case .failure(let error) = result {
                logError("[DemoSeed] '\(item.title)' failed: \(error)")
            }
        }

        switch item.schedule {
        case .recurring(let day, let card):
            let start = dateString(date(day: day, monthOffset: historyOffsets[0]))
            if let id = cardId(card, cards) {
                // The only creation path that puts a recurring charge on a card. It finishes on the
                // main queue, which is free because the seed runs on its own queue.
                let done = DispatchSemaphore(value: 0)
                viewModel.addRecurringTransactionAsync(
                    title: item.title, amount: minor(item.amount), dateString: start,
                    categoryKey: categoryKey, typeRaw: typeRaw, creditCardId: id
                ) { result in
                    if case .failure(let error) = result {
                        logError("[DemoSeed] recurring '\(item.title)' failed: \(error)")
                    }
                    done.signal()
                }
                _ = done.wait(timeout: .now() + 60)
            } else {
                let result = viewModel.addTransaction(
                    title: item.title, amount: minor(item.amount), dateString: start,
                    categoryKey: categoryKey, typeRaw: typeRaw, isRecurring: true)
                if case .failure(let error) = result {
                    logError("[DemoSeed] recurring '\(item.title)' failed: \(error)")
                }
            }

        case .monthly(let days, let months, let card):
            for offset in historyOffsets where months?.contains(offset) ?? true {
                for (index, day) in days.enumerated() {
                    let when = date(day: day, monthOffset: offset)
                    guard when <= now else { continue }
                    addOneOff(when, amount: variedMinor(item, salt: offset * 31 + index), card: card)
                }
            }

        case .installments(let count, let monthOffset, let day, let card):
            let data = InstallmentTransactionData(
                title: item.title, totalAmount: minor(item.amount),
                date: dateString(date(day: day, monthOffset: monthOffset)),
                category: categoryKey, transactionType: typeRaw, installments: count,
                creditCardId: cardId(card, cards))
            if case .failure(let error) = viewModel.addTransactionWithInstallments(data) {
                logError("[DemoSeed] installments '\(item.title)' failed: \(error)")
            }

        case .today:
            addOneOff(now, amount: minor(item.amount), card: nil)

        case .yearly(let month, let day, let card):
            for offset in seededOffsets {
                let when = date(day: day, monthOffset: offset)
                guard cal.component(.month, from: when) == month else { continue }
                addOneOff(when, amount: minor(item.amount), card: card)
            }
        }
    }

    // MARK: Early payment & cancellation

    private func firstInstallment(titled title: String?) -> Transaction? {
        guard let title = title else { return nil }
        return txRepo.fetchAllTransactions()
            .filter { $0.title == title && $0.installmentNumber != nil }
            .min { ($0.installmentNumber ?? 0) < ($1.installmentNumber ?? 0) }
    }

    /// Pays the last two installments of one purchase ahead of time.
    private func payEarly() {
        guard let title = dataset.earlyPaidTitle, let installment = firstInstallment(titled: title)
        else { return }
        let service = EarlyPaymentService(transactionRepo: txRepo)
        let lastTwo = Array(service.payableInstallments(for: installment).suffix(2))
        guard !lastTwo.isEmpty else { return }
        let paidOn = cal.date(byAdding: .day, value: -3, to: now) ?? now
        do {
            try service.payEarly(installments: lastTwo, paymentDate: paidOn,
                                 destination: .standalone, seriesTitle: title)
        } catch {
            logError("[DemoSeed] Early payment of '\(title)' failed: \(error)")
        }
    }

    /// Cancels one purchase after its first installments, which books the estorno on the card.
    private func cancelPurchase() {
        guard let installment = firstInstallment(titled: dataset.cancelledTitle) else { return }
        do {
            try InstallmentCancellationService(transactionRepo: txRepo).cancelPurchase(for: installment)
        } catch {
            logError("[DemoSeed] Cancelling '\(installment.title)' failed: \(error)")
        }
    }

    // MARK: Statements

    /// Every statement already due is paid in full two days before its due date, through the same
    /// service the "Pay statement" screen uses. What remains: the `.closed` card's current statement
    /// (closed, awaiting payment) and every open or future one.
    private func payPastStatements(cards: [CreditCard]) {
        let service = StatementPaymentService(transactionRepo: txRepo, statementRepo: stmtRepo)
        for card in cards {
            guard let cardId = card.id else { continue }
            for statement in stmtRepo.fetchStatements(forCardId: cardId)
            where statement.dueDate < now && !statement.isPaid {
                guard let id = statement.id else { continue }
                let owed = service.remainingBalance(statementId: id)
                guard owed > 0 else { continue }
                let paidOn = min(cal.date(byAdding: .day, value: -2, to: statement.dueDate) ?? statement.dueDate, now)
                do {
                    try service.pay(statement: statement, card: card, amount: owed, paymentDate: paidOn)
                } catch {
                    logError("[DemoSeed] Paying statement \(id) failed: \(error)")
                }
            }
        }
    }

    // MARK: Allocations & budgets

    /// Allocations are sized from what the history actually spent in each category, then pulled
    /// tight on the everyday categories (so some months go over) and left roomy on the rest. The
    /// monthly budget sits a little above the average month, so most months land just under it.
    /// Closed months only: the open month's size depends on the day the seed runs.
    private func insertAllocationsAndBudgets() {
        let historyAnchors = Set(historyOffsets.filter { $0 < 0 }.map { date(day: 1, monthOffset: $0).monthAnchor })
        let spending = txRepo.fetchAllTransactions().filter {
            $0.type == .expense && $0.category != .creditCard && $0.isCreditCardStatement != true
                && historyAnchors.contains($0.budgetMonthDate) && $0.amount > 0
        }
        let months = Double(historyAnchors.count)
        // Averaged over the months a category was used: a yearly purchase spread over twelve months
        // would leave an allocation too small to read.
        let perCategory = Dictionary(grouping: spending, by: { $0.category })
            .mapValues { rows in
                Double(rows.reduce(0) { $0 + $1.amount }) / Double(Set(rows.map(\.budgetMonthDate)).count)
            }
        let digits = Double(CurrencyUtils.fractionDigits(for: dataset.currency))
        let scale = pow(10, digits)
        let tight: Set<TransactionCategory> = [.meals, .transportation, .entertainment, .clothing, .groceries]

        let service = BudgetAllocationService(transactionRepo: txRepo)
        let startAnchor = date(day: 1, monthOffset: historyOffsets[0]).monthAnchor
        for (category, average) in perCategory.sorted(by: { $0.key.key < $1.key.key }) {
            let major = DemoAmounts.round(average / scale * (tight.contains(category) ? 0.9 : 1.05))
            guard major > 0 else { continue }
            _ = try? service.createAllocation(
                category: category, amount: minor(major), monthAnchor: startAnchor, isRecurring: true)
        }

        // The dashboard's "used" also counts card-statement payments, so the budget has to as well.
        let allSpending = txRepo.fetchAllTransactions().filter {
            $0.type == .expense && $0.isCreditCardStatement != true
                && historyAnchors.contains($0.budgetMonthDate)
        }
        let averageMonth = Double(allSpending.reduce(0) { $0 + $1.amount }) / months / scale
        let budget = minor(DemoAmounts.round(averageMonth * 1.08))
        let budgetRepo = BudgetRepository()
        for offset in seededOffsets {
            try? budgetRepo.insert(budget: BudgetModel(
                monthDate: date(day: 1, monthOffset: offset).monthAnchor, amount: budget))
        }
    }
}
#endif
