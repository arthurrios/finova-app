//
//  BudgetFollowsIncomeService.swift
//  Finova
//
//  "Budget follows income": when on, a month's budget is that month's income × a percent.
//
//  The budgets it sets are ordinary rows in `Budgets`, so every reader (dashboard card, ledger,
//  budget history, balance warnings) sees them with no change. The service only keeps those rows
//  in step with income: it recomputes on every `.transactionDataChanged` (add, edit, delete,
//  recurring top-up, fx rate refresh and fx lock all post it) and when the dashboard refreshes.
//
//  Rules (Arthur, 2026-11-26):
//  - One global switch and one percent (default 100).
//  - It applies from the month it was turned on; past months only if the user picked that.
//  - A single month can opt out: it then keeps a fixed budget, typed as before.
//  - A month with no income gets a budget of 0.
//  - Turning it off leaves the rows as they are (they become fixed budgets).
//

import Foundation

final class BudgetFollowsIncomeService {
    static let shared = BudgetFollowsIncomeService()

    // MARK: - Settings (per signed-in user)

    struct Settings: Equatable {
        var isEnabled = false
        /// Whole percent of income, e.g. 80 for 80%.
        var percent = 100
        /// First month anchor it applies to.
        var startMonth = 0
        /// Months that keep a fixed budget while the switch is on.
        var optedOutMonths: Set<Int> = []
    }

    static let percentRange = 1...200

    private let defaults: UserDefaults
    private let budgetRepo: BudgetRepository
    private let transactionRepo: TransactionRepository
    /// Which user's settings to read; injectable for tests.
    private let userKey: () -> String

    init(
        defaults: UserDefaults = .standard,
        budgetRepo: BudgetRepository = BudgetRepository(),
        transactionRepo: TransactionRepository = TransactionRepository(),
        userKey: @escaping () -> String = { UIDUserDefaultsManager.shared.currentUserUID ?? "local" }
    ) {
        self.defaults = defaults
        self.budgetRepo = budgetRepo
        self.transactionRepo = transactionRepo
        self.userKey = userKey
    }

    private func key(_ name: String) -> String { "budgetFollowsIncome.\(name).\(userKey())" }

    var settings: Settings {
        get {
            var s = Settings()
            s.isEnabled = defaults.bool(forKey: key("enabled"))
            let percent = defaults.integer(forKey: key("percent"))
            s.percent = Self.percentRange.contains(percent) ? percent : 100
            s.startMonth = defaults.integer(forKey: key("startMonth"))
            s.optedOutMonths = Set((defaults.array(forKey: key("optedOut")) as? [Int]) ?? [])
            return s
        }
        set {
            defaults.set(newValue.isEnabled, forKey: key("enabled"))
            defaults.set(min(max(newValue.percent, Self.percentRange.lowerBound), Self.percentRange.upperBound),
                         forKey: key("percent"))
            defaults.set(newValue.startMonth, forKey: key("startMonth"))
            defaults.set(newValue.optedOutMonths.sorted(), forKey: key("optedOut"))
        }
    }

    // MARK: - Observing

    private var isObserving = false
    private var isRecomputing = false
    private let lock = NSRecursiveLock()

    /// Call once at launch. Recomputes on every transaction change, on the posting thread, so the
    /// new budgets are in place before the screens that react to the same notice reload.
    func start() {
        guard !isObserving else { return }
        isObserving = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(transactionsChanged), name: .transactionDataChanged, object: nil)
    }

    @objc private func transactionsChanged() {
        #if DEMO
        guard !DemoSeedGenerator.isSeeding else { return }
        #endif
        recomputeIfEnabled()
    }

    // MARK: - Public actions

    /// Turns the switch on. `includePastMonths` also applies it to every earlier month with income.
    func enable(percent: Int, includePastMonths: Bool, today: Date = Date()) {
        var s = settings
        s.isEnabled = true
        s.percent = percent
        let current = today.monthAnchor
        s.startMonth = includePastMonths
            ? min(current, countedIncome().map(\.budgetMonthDate).min() ?? current)
            : current
        // Months typed by hand before keep their opt-out only from here on.
        s.optedOutMonths = s.optedOutMonths.filter { $0 >= s.startMonth }
        settings = s
        recomputeIfEnabled(today: today)
    }

    /// Turns the switch off. The budgets already written stay, as fixed budgets.
    func disable() {
        var s = settings
        s.isEnabled = false
        settings = s
    }

    func setPercent(_ percent: Int) {
        var s = settings
        s.percent = percent
        settings = s
        recomputeIfEnabled()
    }

    /// The month keeps a fixed budget (the user typed one, or deleted its budget).
    func optOut(month: Int) {
        var s = settings
        guard s.isEnabled else { return }
        s.optedOutMonths.insert(month)
        settings = s
    }

    /// The month follows income again.
    func optIn(month: Int) {
        var s = settings
        s.optedOutMonths.remove(month)
        settings = s
        recomputeIfEnabled()
    }

    /// Whether this month's budget is set from income right now.
    func follows(month: Int) -> Bool {
        let s = settings
        return s.isEnabled && month >= s.startMonth && !s.optedOutMonths.contains(month)
    }

    // MARK: - Recompute

    /// Brings every following month's budget in line with its income. Returns the months changed.
    @discardableResult
    func recomputeIfEnabled(today: Date = Date()) -> [Int] {
        let s = settings
        guard s.isEnabled else { return [] }
        lock.lock()
        defer { lock.unlock() }
        guard !isRecomputing else { return [] }
        isRecomputing = true
        defer { isRecomputing = false }

        // The repository caches rows across the process; read what was just written.
        TransactionRepository.invalidateCache()
        let income = countedIncome()
        let existing = Dictionary(
            budgetRepo.fetchBudgets().map { ($0.monthDate, $0.amount) }, uniquingKeysWith: { a, _ in a })
        let targets = Self.targets(
            income: income, settings: s, existing: existing, currentMonth: today.monthAnchor)
        guard !targets.isEmpty else { return [] }

        do {
            try budgetRepo.setBudgetAmounts(targets)
        } catch {
            logError("[BudgetFollowsIncome] Could not write budgets: \(error)")
            return []
        }
        // Balance warnings read budgets; re-check them with the new values.
        DispatchQueue.global(qos: .utility).async {
            BalanceMonitorManager.shared.forceTriggerBalanceMonitoring()
        }
        return targets.keys.sorted()
    }

    // MARK: - Pure rules (static, so tests can call them; tests still to write)

    /// `income × percent`, rounded half up to whole minor units.
    static func budget(income: Int, percent: Int) -> Int {
        guard income > 0, percent > 0 else { return 0 }
        return (income * percent + 50) / 100
    }

    /// Income per month anchor from rows already filtered by `isCountedIncome`.
    static func incomeByMonth(_ rows: [Transaction]) -> [Int: Int] {
        rows.reduce(into: [:]) { $0[$1.budgetMonthDate, default: 0] += $1.amount }
    }

    /// Money that came in during a month. Card rows are left out (a card refund is not money
    /// received), and so are rows that only balance another row: the credit side of a statement
    /// payment, cancellation refunds and early-payment settlements. A foreign-currency income
    /// counts with its reais `amount`.
    static func isCountedIncome(_ tx: Transaction, excludedIds: Set<Int>) -> Bool {
        guard tx.type == .income, tx.creditCardId == nil else { return false }
        if let id = tx.id, excludedIds.contains(id) { return false }
        return true
    }

    /// The budget each following month must have, only for months whose stored value differs.
    /// Covers every month from the start through the later of this month and the last month with
    /// income; a month with no income gets 0.
    static func targets(
        income rows: [Transaction], settings s: Settings, existing: [Int: Int], currentMonth: Int
    ) -> [Int: Int] {
        guard s.isEnabled else { return [:] }
        let byMonth = incomeByMonth(rows)
        let lastMonth = max(currentMonth, byMonth.keys.max() ?? currentMonth)
        let start = s.startMonth > 0 ? s.startMonth : currentMonth
        var out: [Int: Int] = [:]
        for month in BudgetsViewModel.monthAnchors(from: start, through: lastMonth)
        where !s.optedOutMonths.contains(month) {
            let target = budget(income: byMonth[month] ?? 0, percent: s.percent)
            if existing[month] != target { out[month] = target }
        }
        return out
    }

    // MARK: - Reading income

    /// The rows that count as income, the same set the ledger reads (early-paid installments
    /// already removed), minus card rows and balancing rows.
    func countedIncome() -> [Transaction] {
        let excluded = Self.balancingRowIds(db: DBHelper.shared)
        return transactionRepo.fetchAllTransactions().excludingEarlyPaidInstallments()
            .filter { Self.isCountedIncome($0, excludedIds: excluded) }
    }

    /// Ids of rows that only balance another row. Read with `GROUP_CONCAT` so no new DBHelper
    /// API is needed.
    static func balancingRowIds(db: DBHelper) -> Set<Int> {
        let sql = """
            SELECT GROUP_CONCAT(id) FROM Transactions
             WHERE statement_payment_id IS NOT NULL
                OR COALESCE(is_statement_payment, 0) = 1
                OR COALESCE(is_cancellation_refund, 0) = 1
                OR COALESCE(is_early_payment, 0) = 1;
            """
        guard let list = db.fetchSingleString(sql, orderedBindings: []) else { return [] }
        return Set(list.split(separator: ",").compactMap { Int($0) })
    }
}
