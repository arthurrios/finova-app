//
//  DashboardViewController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation
import ShimmerView
import UIKit

final class DashboardViewController: UIViewController {
    let contentView: DashboardView
    let viewModel: DashboardViewModel
    let syncedViewModel: SyncedCollectionsViewModel
    var todayMonthIndex: Int
    var isLoadingInitialData: Bool
    private var needsRefresh = false
    private var transactions: [Transaction] = []
    private var currentCellTransactions: [Transaction] = []
    private var transactionsByMonth: [Int: [Transaction]] = [:]
    private var isInitialLoadComplete = false
    private var hasAppearedBefore = false
    private var isDeletionInProgress = false
    private let updateToastContainer = UpdateToastContainer()
    private let updateToastManager = UpdateToastManager.shared
    private var updateToastTimer: Timer?
    
    // MARK: - Data Recovery Toast
    private let recoveryToastContainer = DataRecoveryToastContainer()
    private let recoveryToastManager = DataRecoveryToastManager.shared
    
    private var currentCell: MonthCarouselCell?
    weak var flowDelegate: DashboardFlowDelegate?

    private func mergeWithStatementTransactions(_ transactions: [Transaction]) -> [Transaction] {
        let statementTxs = viewModel.getStatementTransactions()
        return transactions + statementTxs
    }
    
    // MARK: - Shimmer State Tracking
    private var cardsWithActiveShimmer: Set<Int> = []

    // MARK: - Scroll Direction Locking
    private enum ScrollDirection {
        case none
        case horizontal
        case vertical
    }
    private var lockedScrollDirection: ScrollDirection = .none
    private var initialContentOffset: CGPoint = .zero

    // MARK: - Budget View State Tracking
    /// Global state for showing budget view (applies to all months)
    private var isGlobalBudgetViewActive: Bool = false

    // MARK: - Debounce
    private var refreshWorkItem: DispatchWorkItem?

    // MARK: - Global Filter State
    /// Global filters that apply to all months
    private var globalFilters: TransactionFilters = TransactionFilters()
    
    init(
        contentView: DashboardView,
        viewModel: DashboardViewModel,
        flowDelegate: DashboardFlowDelegate
    ) {
        self.contentView = contentView
        self.viewModel = viewModel
        self.syncedViewModel = SyncedCollectionsViewModel()
        self.flowDelegate = flowDelegate
        self.syncedViewModel.saveInitialDate()
        self.todayMonthIndex = UserDefaultsManager.getCurrentMonthIndex()
        self.isLoadingInitialData = true
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        stopUpdateToastTimer()
        hideRecoveryToast()
        removeKeyboardObservers()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        loadData()
        setupCollectionViews()
        syncedViewModel.selectMonth(at: todayMonthIndex, animated: false)
        contentView.frame = view.bounds
        setupUpdateToast()
        setupRecoveryToast()
        setupPullToRefresh()
        setupKeyboardObservers()
        
#if DEBUG
        setupDebugGesture()
#endif
        
        // Verificar e agendar notificações automaticamente
        checkAndScheduleNotificationsIfNeeded()

        // Setup notification badge
        setupNotificationBadge()

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Update notification badge count
        updateNotificationBadge()

        // Refresh avatar in case it was changed in Profile screen (async to avoid blocking main thread)
        DispatchQueue.global(qos: .userInitiated).async {
            let userImage = ProfileImageManager.shared.loadProfileImage()
            if let image = userImage {
                DispatchQueue.main.async { [weak self] in
                    self?.contentView.avatar.userImage = image
                }
            }
        }

        // Skip refresh on first appearance — loadData() in viewDidLoad already loaded fresh data
        if isInitialLoadComplete && hasAppearedBefore {
            refreshDashboardData()

            // Recalculate current day for day slider when dashboard appears in foreground
            recalculateCurrentDayForVisibleCell()

            // Check for update toast when dashboard appears
            checkForUpdateToastOnForeground()
        }
        hasAppearedBefore = true
    }

    /// Restores the budget view state for the currently visible cell if it was showing budget view
    private func restoreBudgetViewStateForCurrentCell() {
        // Get the actual visible cell from the collection view (currentCell might be stale)
        guard let visibleCells = contentView.monthCarousel.visibleCells as? [MonthCarouselCell],
              let cell = visibleCells.first(where: { $0.tag == syncedViewModel.selectedIndex }),
              !cell.isShowingBudgetView else { return }

        // Update currentCell reference
        currentCell = cell

        let monthAnchor = syncedViewModel.monthData[syncedViewModel.selectedIndex].date.monthAnchor
        if isGlobalBudgetViewActive {
            let allocationService = BudgetAllocationService()
            let allocations = allocationService.getAllocationsWithUsage(forMonth: monthAnchor)
            let summary = allocationService.getUnallocatedSummary(forMonth: monthAnchor)
            cell.restoreBudgetViewState(allocations: allocations, summary: summary)
        }
    }

    private func setupNotificationBadge() {
        NotificationHistoryManager.shared.onUnreadCountChanged = { [weak self] count in
            DispatchQueue.main.async {
                self?.contentView.updateNotificationBadge(count: count)
            }
        }
        updateNotificationBadge()
    }

    private func updateNotificationBadge() {
        let count = NotificationHistoryManager.shared.unreadCount
        contentView.updateNotificationBadge(count: count)
    }
    
    private func refreshDashboardData() {
        // Debounce rapid calls to coalesce multiple reloads
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performDashboardRefresh()
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    private func performDashboardRefresh() {
        // Invalidate caches so we get fresh data
        viewModel.transactionLedger.invalidateCache()
        TransactionRepository.invalidateCache()

        // Load fresh data from repositories
        let monthData = viewModel.loadMonthlyCards()
        let transactions: [Transaction]
        switch viewModel.currentContext {
        case .personal:
            transactions = viewModel.transactionRepo.fetchTransactions()
        case .group(let group):
            transactions = viewModel.transactionRepo.fetchTransactionsForGroup(groupId: group.id)
        }

        // Update the view models with fresh data
        syncedViewModel.setMonthData(monthData)
        syncedViewModel.setTransactions(mergeWithStatementTransactions(transactions))

        // Schedule notifications for any new transactions in the next 30 days
        scheduleNext30DaysNotifications()

        // Force refresh the current visible cell if it exists
        if let currentCell = currentCell {
            let selectedIndex = syncedViewModel.selectedIndex
            if selectedIndex < monthData.count {
                let currentMonthData = monthData[selectedIndex]
                let monthAnchor = currentMonthData.date.monthAnchor

                // Check if global budget view is active
                let shouldShowBudgetView = isGlobalBudgetViewActive

                if shouldShowBudgetView {
                    let allocationService = BudgetAllocationService()
                    let allocations = allocationService.getAllocationsWithUsage(forMonth: monthAnchor)
                    let summary = allocationService.getUnallocatedSummary(forMonth: monthAnchor)

                    // Restore budget view if not already showing, then refresh
                    if !currentCell.isShowingBudgetView {
                        currentCell.restoreBudgetViewState(allocations: allocations, summary: summary)
                    } else {
                        currentCell.refreshBudgetView(allocations: allocations, summary: summary)
                    }
                } else {
                    // Refresh the month budget card with fresh data (but preserve day slider state)
                    currentCell.monthCard.refresh(with: currentMonthData)

                    // Update transactions for the current cell
                    let key = DateFormatter.keyFormatter.string(from: currentMonthData.date)
                    let filteredTransactions = transactions.filter { tx in
                        let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                        let txKey = DateFormatter.keyFormatter.string(from: txDate)
                        let matches = txKey == key
                        return matches
                    }.sorted { $0.date > $1.date }

                    // Update transactions without reconfiguring the month card (to preserve day slider)
                    currentCell.updateTransactions(filteredTransactions)
                }
            }
        }

        // Also refresh all visible cells in the collection view
        DispatchQueue.main.async {
            self.refreshVisibleCells()

            // Clean up any orphaned per-card shimmer overlays (tag 998)
            // that may have been left active when navigating away mid-load
            self.hideShimmerOnAllCards()
        }
    }
    
    /// Recalculates the current day for the day slider in the visible cell
    private func recalculateCurrentDayForVisibleCell(animated: Bool = false) -> Bool {
        guard let currentCell = currentCell else { return false }

        // Recalculate the current day for the day slider
        let refreshNeeded = currentCell.monthCard.recalculateCurrentDay(animated: animated)

        return refreshNeeded
    }
    
    /// Called specifically when app comes into foreground to refresh with animation
    func refreshOnForegroundWithAnimation() {
        // First check if the day slider needs to be updated
        let sliderRefreshNeeded = recalculateCurrentDayForVisibleCell(animated: false)

        if sliderRefreshNeeded {
            // Only refresh data if slider position changed
            refreshAfterTransactionAdd()

            // Then animate the day slider after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.recalculateCurrentDayForVisibleCell(animated: true)
            }
        }

        // Check for update toast when app comes to foreground
        checkForUpdateToastOnForeground()
    }
    
    /// Setup pull-to-refresh functionality
    private func setupPullToRefresh() {
        contentView.delegate = self
    }
    
    private func refreshVisibleCells() {
        let visibleIndexPaths = contentView.monthCarousel.indexPathsForVisibleItems

        for indexPath in visibleIndexPaths {
            if let cell = contentView.monthCarousel.cellForItem(at: indexPath) as? MonthCarouselCell {
                if indexPath.item < syncedViewModel.monthData.count {
                    let monthData = syncedViewModel.monthData[indexPath.item]
                    let monthAnchor = monthData.date.monthAnchor

                    // Check if global budget view is active
                    let shouldShowBudgetView = isGlobalBudgetViewActive

                    if shouldShowBudgetView {
                        // Refresh budget view data
                        let allocationService = BudgetAllocationService()
                        let allocations = allocationService.getAllocationsWithUsage(forMonth: monthAnchor)
                        let summary = allocationService.getUnallocatedSummary(forMonth: monthAnchor)

                        if !cell.isShowingBudgetView {
                            cell.restoreBudgetViewState(allocations: allocations, summary: summary)
                        } else {
                            cell.refreshBudgetView(allocations: allocations, summary: summary)
                        }
                    } else {
                        // Refresh the month budget card (preserving day slider state)
                        cell.monthCard.refresh(with: monthData)

                        // Update transactions without reconfiguring the month card
                        let key = DateFormatter.keyFormatter.string(from: monthData.date)
                        let filteredTransactions = syncedViewModel.allTransactions.filter { tx in
                            let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                            let txKey = DateFormatter.keyFormatter.string(from: txDate)
                            return txKey == key
                        }.sorted { $0.date > $1.date }

                        cell.updateTransactions(filteredTransactions)
                    }
                }
            }
        }
    }
    
    /// Called when a transaction is added to immediately refresh the dashboard
    func refreshAfterTransactionAdd() {
        
        // For transaction addition, we need to be more conservative since we don't know
        // which months will be affected (installments/recurring can span many months)
        // Show shimmer only on current card initially, then comprehensive cleanup
        showShimmerOnCurrentCard()
        
        // For recurring/installment transactions, we need to ensure generation is complete
        // Add a small delay to allow backend processing to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Load fresh data after backend processing
            let monthData = self.viewModel.loadMonthlyCards()
            let transactions = self.viewModel.transactionRepo.fetchTransactions()
            
            // Update the view models
            self.syncedViewModel.setMonthData(monthData)
            self.syncedViewModel.setTransactions(self.mergeWithStatementTransactions(transactions))

            // Schedule notifications for any new transactions in the next 30 days
            self.scheduleNext30DaysNotifications()
            
            // Force refresh the UI with animation
            DispatchQueue.main.async {
                self.refreshVisibleCellsWithAnimation()
                
                // Use comprehensive cleanup since installments might affect non-visible months
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.hideShimmerOnAllCards()
                }
            }
        }
    }
    
    /// Called when an allocation is added/updated to immediately refresh the budget view
    func refreshAfterAllocationChange() {
        // Ensure global budget view state is active
        isGlobalBudgetViewActive = true

        let allocationService = BudgetAllocationService()
        let visibleIndexPaths = contentView.monthCarousel.indexPathsForVisibleItems

        // Refresh all visible cells
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            for indexPath in visibleIndexPaths {
                guard let cell = self.contentView.monthCarousel.cellForItem(at: indexPath) as? MonthCarouselCell else {
                    continue
                }

                let monthAnchor = cell.currentMonthAnchor
                let allocations = allocationService.getAllocationsWithUsage(forMonth: monthAnchor)
                let summary = allocationService.getUnallocatedSummary(forMonth: monthAnchor)

                if cell.isShowingBudgetView {
                    // Already showing budget view, just refresh data
                    UIView.transition(with: cell, duration: 0.3, options: .transitionCrossDissolve) {
                        cell.refreshBudgetView(allocations: allocations, summary: summary)
                    }
                } else {
                    // Need to restore budget view state
                    cell.restoreBudgetViewState(allocations: allocations, summary: summary)
                }
            }
        }
    }

    /// Flips all visible cells to match the global budget view state
    private func flipAllVisibleCellsToGlobalState() {
        let visibleIndexPaths = contentView.monthCarousel.indexPathsForVisibleItems
        let allocationService = BudgetAllocationService()

        for indexPath in visibleIndexPaths {
            guard let cell = contentView.monthCarousel.cellForItem(at: indexPath) as? MonthCarouselCell else {
                continue
            }

            // Skip if cell is already in the correct state
            if cell.isShowingBudgetView == isGlobalBudgetViewActive {
                continue
            }

            let monthAnchor = cell.currentMonthAnchor

            if isGlobalBudgetViewActive {
                // Flip to budget view
                let allocations = allocationService.getAllocationsWithUsage(forMonth: monthAnchor)
                let summary = allocationService.getUnallocatedSummary(forMonth: monthAnchor)
                cell.flipToBudgetView(allocations: allocations, summary: summary)
            } else {
                // Flip back to transaction view
                cell.flipToTransactionView()
            }
        }
    }

    private func refreshVisibleCellsWithAnimation() {
        let visibleIndexPaths = contentView.monthCarousel.indexPathsForVisibleItems

        for indexPath in visibleIndexPaths {
            if let cell = contentView.monthCarousel.cellForItem(at: indexPath) as? MonthCarouselCell {
                if indexPath.item < syncedViewModel.monthData.count {
                    let monthData = syncedViewModel.monthData[indexPath.item]

                    // Animate the refresh
                    UIView.transition(with: cell.monthCard, duration: 0.3, options: .transitionCrossDissolve)
                    {
                        cell.monthCard.refresh(with: monthData)
                    }
                    
                    // Update transactions with animation
                    let key = DateFormatter.keyFormatter.string(from: monthData.date)
                    let filteredTransactions = syncedViewModel.allTransactions.filter { tx in
                        let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                        let txKey = DateFormatter.keyFormatter.string(from: txDate)
                        return txKey == key
                    }.sorted { $0.date > $1.date }
                    
                    // Save current scroll position to restore after update
                    let currentContentOffset = cell.transactionTableView.contentOffset
                    
                    // Reset any gesture states that might be causing freezing
                    cell.transactionTableView.isUserInteractionEnabled = false
                    
                    // Reset scroll position and clear any ongoing gestures
                    cell.transactionTableView.setContentOffset(.zero, animated: false)
                    
                    // Animate table view update with proper cleanup
                    UIView.transition(
                        with: cell.transactionTableView, duration: 0.3, options: .transitionCrossDissolve
                    ) {
                        cell.updateTransactions(filteredTransactions)
                    } completion: { _ in
                        // Restore scroll position if it was valid and reasonable
                        if currentContentOffset.y >= 0
                            && currentContentOffset.y <= cell.transactionTableView.contentSize.height
                        {
                            cell.transactionTableView.setContentOffset(currentContentOffset, animated: false)
                        }

                        // Re-enable interaction after animation completes
                        cell.transactionTableView.isUserInteractionEnabled = true
                        cell.transactionTableView.setNeedsLayout()
                        cell.transactionTableView.layoutIfNeeded()

                        // Force recalculate scroll state after layout completes
                        // This fixes the bug where scroll gets locked after batch updates
                        DispatchQueue.main.async {
                            cell.recalculateScrollState()
                        }
                    }
                }
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        LoadingManager.shared.hideLoading()

        // Restore budget view state after view is fully visible
        // Use slight delay to ensure collection view layout is complete
        DispatchQueue.main.async { [weak self] in
            self?.restoreBudgetViewStateForCurrentCell()
        }

        // Check if we should show notification success alert
        checkAndShowNotificationSuccessAlert()
        
#if DEBUG
        // Add notification debugging on dashboard appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.debugNotificationSystem()
        }
#endif
    }
    
    /// Check if we should show notification success alert and show it if needed
    private func checkAndShowNotificationSuccessAlert() {
        let shouldShowAlert = UserDefaults.standard.bool(forKey: "shouldShowNotificationSuccessAlert")
        
        if shouldShowAlert {
            // Clear the flag first
            UserDefaults.standard.set(false, forKey: "shouldShowNotificationSuccessAlert")
            
            // Get the alert type if specified
            let alertType = UserDefaults.standard.string(forKey: "notificationAlertType") ?? "success"
            
            // Show the appropriate alert
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {  // Small delay to ensure dashboard is fully loaded
                let monthlyManager = MonthlyNotificationManager()
                
                switch alertType {
                case "rescheduled":
                    monthlyManager.showRescheduledAlert()
                case "failure":
                    monthlyManager.showFailureAlert()
                case "permission":
                    monthlyManager.showPermissionDeniedAlert()
                default:
                    monthlyManager.showSuccessAlert()
                }
                
                // Clear the alert type
                UserDefaults.standard.removeObject(forKey: "notificationAlertType")
            }
        }
    }
    
#if DEBUG
    private func debugNotificationSystem() {
        // Run comprehensive notification debugging
        DebugDataManager.shared.debugNotificationSystem()
        
        // Also show current pending notifications
        viewModel.debugPendingNotifications()
    }
    
    private func debugBalanceMonitoring() {
        // Run comprehensive balance monitoring debugging using dashboard data
        let balanceMonitor = BalanceMonitorManager()
        
        // Get current month data from the dashboard
        if let currentMonthData = syncedViewModel.getCurrentMonthData() {
            balanceMonitor.debugBalanceMonitoring(with: currentMonthData)
        } else {
            // Fallback to regular debug if no dashboard data available
            balanceMonitor.debugBalanceMonitoring()
        }
    }
    
    private func forceTriggerBalanceMonitoring() {
        // Force trigger balance monitoring
        let balanceMonitor = BalanceMonitorManager()
        balanceMonitor.forceTriggerBalanceMonitoring()
    }
    
    private func clearBalanceNotifications() {
        // Clear all negative balance notifications
        let balanceMonitor = BalanceMonitorManager()
        balanceMonitor.clearAllNegativeBalanceNotifications()
        
        // Show confirmation alert
        let alert = UIAlertController(
            title: "🧹 Notifications Cleared",
            message: "All negative balance notifications have been cleared.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func testTomorrowNegativeBalanceAlert() {
        // Test tomorrow's negative balance notification
        let balanceMonitor = BalanceMonitorManager()
        balanceMonitor.testTomorrowNegativeBalanceNotification()
        
        // Show confirmation alert
        let alert = UIAlertController(
            title: "🧪 Test Notification Scheduled",
            message: "A test notification for tomorrow's negative balance will appear in 5 seconds.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func testNegativeBalanceAlertIn1Minute() {
        // Test negative balance notification in 1 minute
        let balanceMonitor = BalanceMonitorManager()
        balanceMonitor.testNegativeBalanceNotificationIn1Minute()
        
        // Show confirmation alert
        let alert = UIAlertController(
            title: "🧪 Test Notification Scheduled",
            message: "A test negative balance notification will appear in 1 minute.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    /// Reset notification state for testing
    private func resetNotificationStateForTesting() {
        // Clear all notification-related UserDefaults
        UserDefaults.standard.removeObject(forKey: "lastScheduledMonthKey")
        UserDefaults.standard.removeObject(forKey: "shouldShowNotificationSuccessAlert")
        UserDefaults.standard.removeObject(forKey: "notificationAlertType")
        
        
        // Show confirmation alert
        let alert = UIAlertController(
            title: "🧪 Notification State Reset",
            message:
                "Notification state has been reset. The next time you open the app, it should trigger the monthly notification setup.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
#endif
    
    private func setup() {
        view.addSubview(contentView)
        buildHierarchy()

        contentView.delegate = self
        syncedViewModel.delegate = self

        // Refresh dashboard when lazy generation creates new recurring/installment instances
        viewModel.onDataNeedsRefresh = { [weak self] in
            self?.refreshDashboardData()
        }

        // Setup notification observers for transaction data changes
        setupNotificationObservers()
        
#if DEBUG
        setupDebugGestures()
#endif
    }
    
    private func setupNotificationObservers() {
        // Listen for transaction data changes to invalidate ledger cache
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTransactionDataChanged),
            name: .transactionDataChanged,
            object: nil
        )

        // Listen for currency changes to refresh displayed values
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCurrencyDidChange),
            name: .currencyDidChange,
            object: nil
        )

        // Listen for group data changes to update context chip (e.g., groups restored from CloudKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGroupDataChanged),
            name: .budgetGroupDataChanged,
            object: nil
        )

    }

    @objc private func handleCurrencyDidChange() {
        // Reload the carousel to refresh all currency displays
        logDebug("DashboardViewController received currencyDidChange notification")
        logDebug("Current AppConfig.currencyCode: \(AppConfig.currencyCode)")
        DispatchQueue.main.async { [weak self] in
            self?.contentView.monthCarousel.reloadData()
        }
    }

    @objc private func handleGroupDataChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateContextChip()
        }
    }
    
    private func setupUpdateToast() {
        updateToastManager.delegate = self
        updateToastContainer.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(updateToastContainer)
        NSLayoutConstraint.activate([
            updateToastContainer.topAnchor.constraint(equalTo: view.topAnchor),
            updateToastContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            updateToastContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            updateToastContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
#if DEBUG
        // Reset testing state to ensure clean test
        updateToastManager.resetTestingState()
        
        // Comment out mock version for production testing
        // updateToastManager.setMockLatestVersion("2.0.0")
#endif

        // Clear cache to force fresh API call
        VersionService.shared.clearCache()

        // Check for updates from App Store first
        updateToastManager.checkForUpdatesFromAppStore { [weak self] hasNewerVersion in
            // Show toast with delay after dashboard loads (both debug and release)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self?.showUpdateToast()
            }
        }
        
        // Start periodic timer to check for toast reminders
        startUpdateToastTimer()
    }
    
    private func setupRecoveryToast() {
        recoveryToastManager.delegate = self
        recoveryToastContainer.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(recoveryToastContainer)
        NSLayoutConstraint.activate([
            recoveryToastContainer.topAnchor.constraint(equalTo: view.topAnchor),
            recoveryToastContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            recoveryToastContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            recoveryToastContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        // Check for recovery toast after dashboard loads
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.showRecoveryToast()
        }
    }
    
    private func showUpdateToast() {
        // Check if toast should be shown based on version logic
        let shouldShow = updateToastManager.shouldShowUpdateToast()

        if shouldShow {
            updateToastContainer.showUpdateToast(delegate: self)
            // Mark toast as shown for cooldown tracking
            updateToastManager.markToastAsShown()
        }
    }
    
    private func hideUpdateToast() {
        updateToastContainer.hideUpdateToast()
    }
    
    private func showRecoveryToast() {
        // Check if recovery toast should be shown
        let shouldShow = recoveryToastManager.shouldShowRecoveryToast()

        if shouldShow {
            recoveryToastContainer.showRecoveryToast(delegate: self)
        }
    }
    
    private func hideRecoveryToast() {
        recoveryToastContainer.hideRecoveryToast()
    }
    
    private func startUpdateToastTimer() {
        // Check every 30 minutes for toast reminders (6-hour interval)
        updateToastTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) {
            [weak self] _ in
            self?.checkForUpdateToastReminder()
        }
    }
    
    private func checkForUpdateToastReminder() {
        let shouldShow = updateToastManager.shouldShowUpdateToast()
        if shouldShow {
            showUpdateToast()
        }
    }
    
    /// Check for update toast when app comes to foreground
    private func checkForUpdateToastOnForeground() {
        // Check for updates from App Store first
        updateToastManager.checkForUpdatesFromAppStore { [weak self] hasNewerVersion in
            // Show toast with a small delay to ensure smooth transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.showUpdateToast()
            }
        }
    }
    
    private func stopUpdateToastTimer() {
        updateToastTimer?.invalidate()
        updateToastTimer = nil
    }
    
#if DEBUG
    private func setupDebugGesture() {
        let tripleTapGesture = UITapGestureRecognizer(
            target: self, action: #selector(handleTripleTap))
        tripleTapGesture.numberOfTapsRequired = 3
        view.addGestureRecognizer(tripleTapGesture)
    }
    
    @objc private func handleTripleTap() {
        UpdateToastDebugManager.shared.showDebugMenu(from: self)
    }
#endif
    
    @objc private func handleTransactionDataChanged() {
        // Only refresh if we're not currently in the middle of a deletion operation
        // to prevent race conditions and double refreshes
        if !isDeletionInProgress {
            // Force refresh current month balance to ensure immediate update
            viewModel.forceRefreshCurrentMonthBalance()
        }

        // Refresh the dashboard data and context chip (groups may have been discovered during sync)
        DispatchQueue.main.async {
            self.refreshDashboardData()
            self.updateContextChip()
        }
    }
    
#if DEBUG
    private func setupDebugGestures() {
        // Add long press gesture to trigger notification debugging
        let longPressGesture = UILongPressGestureRecognizer(
            target: self, action: #selector(handleLongPress))
        longPressGesture.minimumPressDuration = 2.0
        view.addGestureRecognizer(longPressGesture)
    }
    
    @objc private func handleLongPress() {
        let alertController = UIAlertController(
            title: "🔔 Debug Notifications",
            message: "Choose a debugging action:",
            preferredStyle: .actionSheet
        )
        
        let debugAction = UIAlertAction(title: "🔍 Run Full Debug", style: .default) { _ in
            self.debugNotificationSystem()
        }
        
        let balanceDebugAction = UIAlertAction(title: "💰 Debug Balance Monitoring", style: .default) {
            _ in
            self.debugBalanceMonitoring()
        }
        
        let forceBalanceAction = UIAlertAction(title: "⚡ Force Balance Monitoring", style: .default) {
            _ in
            self.forceTriggerBalanceMonitoring()
        }
        
        let clearNotificationsAction = UIAlertAction(
            title: "🧹 Clear Balance Notifications", style: .default
        ) { _ in
            self.clearBalanceNotifications()
        }
        
        let testTomorrowAction = UIAlertAction(title: "🧪 Test Tomorrow's Alert (5s)", style: .default)
        { _ in
            self.testTomorrowNegativeBalanceAlert()
        }
        
        let test1MinAction = UIAlertAction(title: "🧪 Test Alert in 1 Minute", style: .default) { _ in
            self.testNegativeBalanceAlertIn1Minute()
        }
        
        let testAction = UIAlertAction(title: "📡 Test Notification (5s)", style: .default) { _ in
            DebugDataManager.shared.testNotificationNow()
        }
        
        let rescheduleAction = UIAlertAction(title: "🔄 Force Reschedule All", style: .default) { _ in
            DebugDataManager.shared.forceRescheduleNotifications()
        }
        
        let resetAction = UIAlertAction(title: "🧪 Reset Notification State", style: .default) { _ in
            self.resetNotificationStateForTesting()
        }
        
        let duplicateAnalysisAction = UIAlertAction(title: "🔍 Analyze Duplicates", style: .default) {
            _ in
            self.analyzeDuplicateTransactions()
        }
        
        let duplicateCleanupAction = UIAlertAction(title: "🧹 Clean Duplicates", style: .default) {
            _ in
            self.cleanupDuplicateTransactions()
        }
        
        let forceRefreshBalanceAction = UIAlertAction(
            title: "💰 Force Refresh Balance", style: .default
        ) {
            _ in
            self.forceRefreshCurrentMonthBalance()
        }
        
        let migrateBudgetsAction = UIAlertAction(title: "🔄 Migrate Budgets", style: .default) {
            _ in
            self.migrateBudgetsToNewTimezone()
        }
        
        let migrateAllDataAction = UIAlertAction(title: "🌍 Migrate All Data", style: .default) {
            _ in
            self.migrateAllDataToNewTimezone()
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alertController.addAction(debugAction)
        alertController.addAction(balanceDebugAction)
        alertController.addAction(forceBalanceAction)
        alertController.addAction(clearNotificationsAction)
        alertController.addAction(testTomorrowAction)
        alertController.addAction(test1MinAction)
        alertController.addAction(testAction)
        alertController.addAction(rescheduleAction)
        alertController.addAction(resetAction)
        alertController.addAction(duplicateAnalysisAction)
        alertController.addAction(duplicateCleanupAction)
        alertController.addAction(forceRefreshBalanceAction)
        alertController.addAction(migrateBudgetsAction)
        alertController.addAction(migrateAllDataAction)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true)
    }
#endif
    
    // MARK: - Duplicate Transaction Management
    
    private func analyzeDuplicateTransactions() {
        let analysis = viewModel.analyzeDuplicateTransactions()
        
        let alert = UIAlertController(
            title: "🔍 Duplicate Analysis",
            message: analysis,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func cleanupDuplicateTransactions() {
        let alert = UIAlertController(
            title: "🧹 Clean Duplicates",
            message: "This will remove all duplicate transactions. Are you sure?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Clean", style: .destructive) { _ in
                self.viewModel.cleanupExistingDuplicates()
                
                // Show completion alert
                let completionAlert = UIAlertController(
                    title: "✅ Cleanup Complete",
                    message:
                        "Duplicate transactions have been removed. The dashboard will refresh automatically.",
                    preferredStyle: .alert
                )
                completionAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(completionAlert, animated: true)
            })
        
        present(alert, animated: true)
    }
    
    private func forceRefreshCurrentMonthBalance() {
        // Force refresh the balance
        viewModel.forceRefreshCurrentMonthBalance()
        
        // Refresh the dashboard to show the updated balance
        refreshDashboardData()
        
        // Show completion alert
        let alert = UIAlertController(
            title: "✅ Balance Refreshed",
            message:
                "Current month balance has been force refreshed. Check the console for detailed logs.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func migrateBudgetsToNewTimezone() {
        // Show confirmation alert
        let alert = UIAlertController(
            title: "🔄 Migrate Budgets",
            message:
                "This will migrate existing budgets to use the new timezone-based month anchors. This is needed after the timezone fix. Continue?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Migrate", style: .destructive) { _ in
                // Run the migration
                self.viewModel.migrateBudgetsToNewTimezone()
                
                // Refresh the dashboard to show the updated data
                self.refreshDashboardData()
                
                // Show completion alert
                let completionAlert = UIAlertController(
                    title: "✅ Migration Complete",
                    message:
                        "Budgets have been migrated to use new timezone-based month anchors. The dashboard will refresh automatically.",
                    preferredStyle: .alert
                )
                completionAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(completionAlert, animated: true)
            })
        
        present(alert, animated: true)
    }
    
    private func migrateAllDataToNewTimezone() {
        // Show confirmation alert
        let alert = UIAlertController(
            title: "🌍 Migrate All Data",
            message:
                "This will migrate BOTH budgets AND transactions to use the new timezone-based month anchors. This is needed to fix the 0 balance issue. Continue?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Migrate All", style: .destructive) { _ in
                // Run the comprehensive migration
                self.viewModel.migrateAllDataToNewTimezone()
                
                // Refresh the dashboard to show the updated data
                self.refreshDashboardData()
                
                // Show completion alert
                let completionAlert = UIAlertController(
                    title: "✅ Migration Complete",
                    message:
                        "All data has been migrated to use new timezone-based month anchors. The dashboard will refresh automatically.",
                    preferredStyle: .alert
                )
                completionAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(completionAlert, animated: true)
            })
        
        present(alert, animated: true)
    }
    
    private func checkAndRunBudgetMigrationIfNeeded() {
        // Check if migration has already been run for this user
        let migrationKey = "budgetMigrationCompleted"
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        // Check if there are any budgets that need migration
        let budgetRepo = BudgetRepository()
        let allBudgets = budgetRepo.fetchBudgets()

        if allBudgets.isEmpty {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        // Check if any budget has the old UTC-based month anchor
        let needsMigration = allBudgets.contains { budget in
            let oldDate = Date(timeIntervalSince1970: TimeInterval(budget.monthDate))
            let newMonthAnchor = oldDate.monthAnchor
            return newMonthAnchor != budget.monthDate
        }

        if needsMigration {
            // Run the comprehensive migration (budgets + transactions)
            viewModel.migrateAllDataToNewTimezone()

            // Mark migration as completed
            UserDefaults.standard.set(true, forKey: migrationKey)
        } else {
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
    }
    
    private func checkAndRunTransactionMigrationIfNeeded() {
        // Check if transaction migration has already been run for this user
        let migrationKey = "transactionMigrationCompleted"
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        // Check if there are any transactions that need migration
        let allTransactions = viewModel.transactionRepo.fetchAllTransactions()

        if allTransactions.isEmpty {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        // Check if any transaction has the old UTC-based month anchor
        let needsMigration = allTransactions.contains { transaction in
            let oldDate = Date(timeIntervalSince1970: TimeInterval(transaction.dateTimestamp))
            let newMonthAnchor = oldDate.monthAnchor
            return newMonthAnchor != transaction.budgetMonthDate
        }

        if needsMigration {
            // Run the migration
            viewModel.migrateAllDataToNewTimezone()

            // Mark migration as completed
            UserDefaults.standard.set(true, forKey: migrationKey)
        } else {
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
    }
    
    private func buildHierarchy() {
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
    }
    
    func loadData() {
        // Get user from UID-based settings first, fallback to global UserDefaults
        var displayUser: User?
        
        // First try to get Firebase user and set current UID if needed
        if let firebaseUser = AuthenticationManager.shared.currentUser {
            // Ensure current UID is set
            UIDUserDefaultsManager.shared.currentUserUID = firebaseUser.uid
            DBHelper.shared.backfillUserIds(uid: firebaseUser.uid)

            // Try to get UID-based settings
            if let uidSettings = UIDUserDefaultsManager.shared.getUserSettings(for: firebaseUser.uid) {
                displayUser = User(
                    firebaseUID: firebaseUser.uid,
                    name: uidSettings.name,
                    email: uidSettings.email,
                    isUserSaved: uidSettings.isUserSaved,
                    hasFaceIdEnabled: uidSettings.hasFaceIdEnabled
                )
            } else {
                // No UID settings found, check global and migrate
                if let globalUser = UserDefaultsManager.getUserWithUID() {
                    displayUser = globalUser

                    // Migrate to UID-based system if same user
                    if globalUser.firebaseUID == firebaseUser.uid {
                        let userSettings = UserSettings(
                            name: globalUser.name,
                            email: globalUser.email,
                            hasFaceIdEnabled: globalUser.hasFaceIdEnabled,
                            isUserSaved: globalUser.isUserSaved
                        )
                        UIDUserDefaultsManager.shared.saveUserSettings(
                            for: firebaseUser.uid, settings: userSettings)
                    }
                } else {
                    // Create basic user from Firebase
                    displayUser = User(
                        firebaseUID: firebaseUser.uid,
                        name: firebaseUser.displayName ?? "User",
                        email: firebaseUser.email ?? "",
                        isUserSaved: true,
                        hasFaceIdEnabled: false
                    )
                }
            }
        }
        // Fallback to UID-based settings with stored current UID
        else if let currentUID = UIDUserDefaultsManager.shared.currentUserUID,
                let uidSettings = UIDUserDefaultsManager.shared.getUserSettings(for: currentUID)
        {
            displayUser = User(
                firebaseUID: currentUID,
                name: uidSettings.name,
                email: uidSettings.email,
                isUserSaved: uidSettings.isUserSaved,
                hasFaceIdEnabled: uidSettings.hasFaceIdEnabled
            )
        }
        // Final fallback to global UserDefaults
        else if let globalUser = UserDefaultsManager.getUserWithUID() {
            displayUser = globalUser
        }
        
        if let user = displayUser {
            if let firebaseUID = user.firebaseUID {
                // Ensure user settings are properly created in UID-based system
                if UIDUserDefaultsManager.shared.getUserSettings(for: firebaseUID) == nil {
                    UserDefaultsManager.updateCurrentUserSavedStatus(saved: user.isUserSaved)
                    if user.hasFaceIdEnabled {
                        UserDefaultsManager.updateCurrentUserFaceID(enabled: true)
                    }
                }
            }

            contentView.welcomeTitleLabel.text = "dashboard.welcomeTitle".localized + "\(user.name)!"
            contentView.welcomeTitleLabel.applyStyle()
        } else {
            logError("Dashboard: No user found in any UserDefaults system")
            contentView.welcomeTitleLabel.text = "dashboard.welcomeTitle".localized + "User!"
        }
        
        // Check if budget migration is needed (run once)
        checkAndRunBudgetMigrationIfNeeded()
        
        DispatchQueue.global(qos: .userInitiated).async {
            let userImage = ProfileImageManager.shared.loadProfileImage()
            if let image = userImage {
                DispatchQueue.main.async { [weak self] in
                    self?.contentView.avatar.userImage = image
                }
            }
        }

        // Safely load transactions with authentication check
        switch viewModel.currentContext {
        case .personal:
            transactions = viewModel.transactionRepo.fetchTransactions()
        case .group(let group):
            transactions = viewModel.transactionRepo.fetchTransactionsForGroup(groupId: group.id)
        }

        // Safely load monthly cards data
        let monthData = viewModel.loadMonthlyCards()
        
        syncedViewModel.setMonthData(monthData)
        syncedViewModel.setTransactions(mergeWithStatementTransactions(transactions))

        // Configure context chip
        updateContextChip()

        contentView.monthCarousel.layoutIfNeeded()

        // Marcar que o carregamento inicial foi concluído
        // Note: isLoadingInitialData is set to false in didUpdateMonthData/didUpdateSelectedIndex
        // after shimmer is hidden, not here
        isInitialLoadComplete = true
    }
    
    private func setupCollectionViews() {
        // Verificar se já foi configurado
        guard contentView.monthSelectorView.collectionView.delegate == nil else {
            return
        }
        
        contentView.monthSelectorView.collectionView.delegate = self
        contentView.monthSelectorView.collectionView.dataSource = self
        contentView.monthSelectorView.collectionView.register(
            MonthCell.self, forCellWithReuseIdentifier: MonthCell.reuseID)
        contentView.monthSelectorView.delegate = self
        
        contentView.monthCarousel.delegate = self
        contentView.monthCarousel.dataSource = self
        contentView.monthCarousel.register(
            MonthCarouselCell.self, forCellWithReuseIdentifier: MonthCarouselCell.reuseID)
        
        // Don't configure month selector here - let it be configured through didUpdateMonthData
        // This ensures consistency between month data and month selector
        
        contentView.monthCarousel.reloadData()
        
        contentView.monthSelectorView.layoutIfNeeded()
        contentView.monthCarousel.layoutIfNeeded()
    }
}

extension DashboardViewController: DashboardViewDelegate {
    func didTapProfile() {
        self.flowDelegate?.navigateToProfile()
    }

    func didTapAddTransaction() {
        // If budget view is showing, open add allocation modal instead
        if let currentCell = currentCell, currentCell.isShowingBudgetView {
            let monthAnchor = syncedViewModel.monthData[syncedViewModel.selectedIndex].date.monthAnchor
            // Track that budget view is active before opening modal
            isGlobalBudgetViewActive = true
            self.flowDelegate?.openAddAllocationModal(forMonth: monthAnchor, preselectedCategory: nil)
        } else {
            self.flowDelegate?.openAddTransactionModal(context: viewModel.currentContext)
        }
    }
    
    func didTapContextSwitch() {
        let groups = viewModel.getAvailableGroups()
        guard !groups.isEmpty else { return }

        let alert = UIAlertController(
            title: "dashboard.context.switch".localized,
            message: nil,
            preferredStyle: .actionSheet
        )

        // Personal option
        let personalAction = UIAlertAction(
            title: "dashboard.context.personal".localized,
            style: .default
        ) { [weak self] _ in
            self?.switchToContext(.personal)
        }
        if viewModel.currentContext == .personal {
            personalAction.setValue(true, forKey: "checked")
        }
        alert.addAction(personalAction)

        // Group options
        for group in groups {
            let action = UIAlertAction(title: group.name, style: .default) { [weak self] _ in
                self?.switchToContext(.group(group))
            }
            if case .group(let current) = viewModel.currentContext, current.id == group.id {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        present(alert, animated: true)
    }

    private func switchToContext(_ context: DataContext) {
        viewModel.switchContext(to: context)
        updateContextChip()
    }

    func updateContextChip() {
        let hasGroups = !viewModel.getAvailableGroups().isEmpty
        contentView.configureContextChip(
            currentContext: viewModel.currentContext,
            hasGroups: hasGroups
        )
    }

    func didTapNotifications() {
        self.flowDelegate?.navigateToNotificationHistory()
    }
    
    func dashboardViewDidRequestRefresh(_ dashboardView: DashboardView) {
        // Trigger iCloud sync on pull-to-refresh
        SyncEngine.shared.performFullSync()

        // Refresh dashboard data and recalculate current day with animation
        refreshDashboardData()
        
        // Add a small delay to ensure data is refreshed before animating
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.recalculateCurrentDayForVisibleCell(animated: true)
        }
        
        // Check for update toast on pull-to-refresh
        checkForUpdateToastOnForeground()
        
        // End the refresh animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dashboardView.endRefreshing()
        }
    }
}

extension DashboardViewController: MonthSelectorDelegate {
    func didTapPrev() {
        syncedViewModel.moveToPreviousMonth()
    }
    
    func didTapNext() {
        syncedViewModel.moveToNextMonth()
    }
    
    func didSelectMonth(at index: Int) {
        syncedViewModel.selectMonth(at: index)
    }
}

extension DashboardViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int)
    -> Int
    {
        return syncedViewModel.monthData.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
    -> UICollectionViewCell
    {
        if collectionView == contentView.monthCarousel {
            let model = syncedViewModel.monthData[indexPath.item]
            
            guard
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: MonthCarouselCell.reuseID, for: indexPath) as? MonthCarouselCell
            else {
                fatalError("Could not dequeue cell")
            }
            
            cell.monthCard.delegate = self
            cell.searchDelegate = self
            cell.onAllocationTapped = { [weak self] allocation in
                self?.flowDelegate?.navigateToAllocationDetails(allocation: allocation)
            }
            cell.onUnallocatedSpendingTapped = { [weak self] unallocatedSpending in
                // Navigate to unallocated details screen where user can see transactions and create allocation
                self?.flowDelegate?.navigateToUnallocatedDetails(unallocatedSpending: unallocatedSpending)
            }
            cell.onBudgetsConfigTapped = { [weak self] monthAnchor in
                // Budget view is already active since config button is only visible in budget view
                let date = Date.fromMonthAnchor(monthAnchor)
                self?.flowDelegate?.navigateToBudgets(date: date)
            }
            cell.onDefineBudgetTapped = { [weak self] monthAnchor in
                let date = Date.fromMonthAnchor(monthAnchor)
                self?.flowDelegate?.navigateToBudgets(date: date)
            }
            cell.onBudgetViewStateChanged = { [weak self] _, isShowingBudget in
                guard let self = self else { return }
                self.isGlobalBudgetViewActive = isShowingBudget
                // Flip all visible cells to match the global state
                self.flipAllVisibleCellsToGlobalState()
            }
            cell.onBalanceVisibilityToggled = { [weak self] isHidden in
                self?.updateAllMonthCardsBalanceVisibility(isHidden)
            }

            cell.transactionTableView.dataSource = self
            cell.transactionTableView.delegate = self
            cell.transactionTableView.register(
                TransactionCell.self, forCellReuseIdentifier: TransactionCell.reuseID)
            
            let key = DateFormatter.keyFormatter.string(from: model.date)
            let txs = syncedViewModel.allTransactions.filter { tx in
                let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                let txKey = DateFormatter.keyFormatter.string(from: txDate)
                return txKey == key
            }.sorted { (tx1, tx2) -> Bool in
                return tx1.date > tx2.date
            }
            
            if indexPath.item == syncedViewModel.selectedIndex {
                currentCellTransactions = txs
                currentCell = cell
            }
            
            cell.tag = indexPath.item
            cell.transactions = txs

            // Set the month anchor for budget view operations
            let monthAnchor = model.date.monthAnchor
            cell.setMonthAnchor(monthAnchor)

            cell.monthCard.ledgerService = viewModel.transactionLedger
            cell.monthCard.refresh(with: model)

            cell.setFiltersWithoutApplying(globalFilters)
            cell.updateTransactions(txs)

            // Restore budget view state if global budget view is active
            if isGlobalBudgetViewActive {
                let allocationService = BudgetAllocationService()
                let allocations = allocationService.getAllocationsWithUsage(forMonth: monthAnchor)
                let summary = allocationService.getUnallocatedSummary(forMonth: monthAnchor)
                cell.restoreBudgetViewState(allocations: allocations, summary: summary)
            }

            return cell
        } else {
            guard
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: MonthCell.reuseID, for: indexPath) as? MonthCell
            else {
                fatalError("Could not dequeue month cell")
            }
            
            let monthName = syncedViewModel.monthData[indexPath.item].month
            cell.configure(title: monthName)
            return cell
        }
    }
}

extension DashboardViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView == contentView.monthSelectorView.collectionView {
            syncedViewModel.selectMonth(at: indexPath.item)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard collectionView == contentView.monthCarousel,
              let monthCell = cell as? MonthCarouselCell else { return }

        // Ensure budget view state is synchronized before the cell is displayed
        let monthAnchor = syncedViewModel.monthData[indexPath.item].date.monthAnchor
        if isGlobalBudgetViewActive && !monthCell.isShowingBudgetView {
            let allocationService = BudgetAllocationService()
            let allocations = allocationService.getAllocationsWithUsage(forMonth: monthAnchor)
            let summary = allocationService.getUnallocatedSummary(forMonth: monthAnchor)
            monthCell.restoreBudgetViewState(allocations: allocations, summary: summary)
        } else if !isGlobalBudgetViewActive && monthCell.isShowingBudgetView {
            monthCell.flipToTransactionView()
        }

        // Ensure filter state is synchronized with global filters
        // Always reapply filters when displaying a cell to ensure consistency
        // This handles cell reuse, async timing issues, and monthCard state resets
        if !globalFilters.isEmpty {
            monthCell.applyFilters(globalFilters)
        } else if !monthCell.currentFilters.isEmpty {
            // Global filters are empty but cell has filters - clear them
            monthCell.clearFilters()
        }

        // Recalculate scroll state after cell is displayed to fix any stale scroll locks
        if !isGlobalBudgetViewActive {
            DispatchQueue.main.async {
                monthCell.recalculateScrollState()
            }
        }
    }
}

extension DashboardViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        if collectionView == contentView.monthCarousel {
            return CGSize(width: collectionView.bounds.width, height: collectionView.bounds.height)
        } else if collectionView == contentView.monthSelectorView.collectionView {
            
            let spacing =
            (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?
                .minimumInteritemSpacing ?? 0
            let totalSpacing = spacing * 4
            let availableWidth = collectionView.bounds.width - totalSpacing
            let cellWidth = availableWidth / 5
            
            return CGSize(width: cellWidth, height: collectionView.bounds.height)
        } else {
            return CGSize(width: collectionView.bounds.width, height: collectionView.bounds.height)
        }
    }
}

extension DashboardViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView == contentView.monthCarousel else { return }
        // Reset direction lock and store initial offset
        lockedScrollDirection = .none
        initialContentOffset = scrollView.contentOffset
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView == contentView.monthCarousel else { return }

        // Determine scroll direction if not yet locked
        if lockedScrollDirection == .none {
            let deltaX = abs(scrollView.contentOffset.x - initialContentOffset.x)
            let deltaY = abs(scrollView.contentOffset.y - initialContentOffset.y)

            // Only lock direction after a minimum movement threshold (5 points)
            let threshold: CGFloat = 5.0
            if deltaX > threshold || deltaY > threshold {
                if deltaX > deltaY {
                    lockedScrollDirection = .horizontal
                } else {
                    lockedScrollDirection = .vertical
                }
            }
        }

        // Enforce direction lock
        switch lockedScrollDirection {
        case .horizontal:
            // Lock to horizontal - prevent vertical movement
            if scrollView.contentOffset.y != initialContentOffset.y {
                scrollView.contentOffset.y = initialContentOffset.y
            }
        case .vertical:
            // Lock to vertical (for pull-to-refresh) - prevent horizontal movement
            if scrollView.contentOffset.x != initialContentOffset.x {
                scrollView.contentOffset.x = initialContentOffset.x
            }
        case .none:
            break
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView == contentView.monthCarousel else { return }
        if !decelerate {
            // Reset direction lock when scrolling ends without deceleration
            lockedScrollDirection = .none
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // Reset direction lock when scrolling ends
        lockedScrollDirection = .none
        if scrollView == contentView.monthCarousel {
            let pageWidth = scrollView.frame.width
            let page = Int(floor((scrollView.contentOffset.x - pageWidth / 2) / pageWidth) + 1)
            syncedViewModel.selectMonth(at: page, animated: true)
            
            if let visibleCells = contentView.monthCarousel.visibleCells as? [MonthCarouselCell],
               let firstCell = visibleCells.first
            {
                currentCell = firstCell

                let index = firstCell.tag
                if index < syncedViewModel.monthData.count {
                    let model = syncedViewModel.monthData[index]
                    let key = DateFormatter.keyFormatter.string(from: model.date)
                    let txs = syncedViewModel.allTransactions.filter { tx in
                        let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                        let txKey = DateFormatter.keyFormatter.string(from: txDate)
                        return txKey == key
                    }.sorted { (tx1, tx2) -> Bool in
                        return tx1.date > tx2.date
                    }
                    currentCellTransactions = txs

                    // Ensure budget view state is synchronized after scroll ends
                    let monthAnchor = model.date.monthAnchor
                    if isGlobalBudgetViewActive && !firstCell.isShowingBudgetView {
                        let allocationService = BudgetAllocationService()
                        let allocations = allocationService.getAllocationsWithUsage(forMonth: monthAnchor)
                        let summary = allocationService.getUnallocatedSummary(forMonth: monthAnchor)
                        firstCell.restoreBudgetViewState(allocations: allocations, summary: summary)
                    } else if !isGlobalBudgetViewActive && firstCell.isShowingBudgetView {
                        firstCell.flipToTransactionView()
                    }
                }
            }
            
            // Clean up any lingering shimmer when user scrolls to new month
            if !cardsWithActiveShimmer.isEmpty {
                hideShimmerOnAllCards()
            }

            // Only run emergency cleanup occasionally to avoid interference
            // Check if there are any visible shimmer views that shouldn't be there
            let hasOrphanedShimmer = contentView.monthCarousel.visibleCells.contains { cell in
                if let monthCell = cell as? MonthCarouselCell {
                    return monthCell.monthCard.viewWithTag(998) != nil
                }
                return false
            }

            if hasOrphanedShimmer {
                emergencyShimmerCleanup()
            }
        }
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        scrollViewDidEndDecelerating(scrollView)
    }
}

extension DashboardViewController: SyncedCollectionsViewModelDelegate {
    func didUpdateSelectedIndex(_ index: Int, animated: Bool) {
        let ip = IndexPath(item: index, section: 0)
        
        if index < syncedViewModel.monthData.count {
            let model = syncedViewModel.monthData[index]
            let key = DateFormatter.keyFormatter.string(from: model.date)
            let txs = syncedViewModel.allTransactions.filter { tx in
                let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                let txKey = DateFormatter.keyFormatter.string(from: txDate)
                return txKey == key
            }.sorted { (tx1, tx2) -> Bool in
                return tx1.date > tx2.date
            }
            currentCellTransactions = txs
        }
        
        contentView.monthCarousel.performBatchUpdates(nil) { _ in
            self.contentView.monthCarousel.scrollToItem(
                at: ip,
                at: .centeredHorizontally,
                animated: animated
            )
            self.contentView.monthSelectorView.scrollToMonth(
                at: index,
                animated: animated
            )

            // Hide shimmer after cells are configured
            if self.isLoadingInitialData {
                // Force layout to ensure cells are rendered
                self.contentView.monthCarousel.layoutIfNeeded()

                // Small delay to ensure cells finish configuring before hiding shimmer
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.contentView.hideShimmerViewsAndShowOriginals()
                    self.isLoadingInitialData = false
                }
            }
        }
    }
    
    func didUpdateMonthData(_ data: [MonthBudgetCardType]) {
        let currentSelectedIndex = syncedViewModel.selectedIndex

        // Verificar se os dados realmente mudaram antes de reconfigurar
        let currentMonths = contentView.monthSelectorView.months
        let newMonths = data.map { $0.month }
        let monthsChanged = currentMonths != newMonths

        if monthsChanged {
            contentView.monthSelectorView.configure(
                months: newMonths, selectedIndex: currentSelectedIndex)
        }

        DispatchQueue.main.async {
            self.contentView.monthCarousel.reloadData()

            // Handle month selection
            if currentSelectedIndex == 0 && data.isEmpty {
                let todayKey = DateFormatter.keyFormatter.string(from: Date())
                if let currentIndex = self.syncedViewModel.monthData.firstIndex(where: {
                    DateFormatter.keyFormatter.string(from: $0.date) == todayKey
                }) {
                    self.syncedViewModel.selectMonth(at: currentIndex, animated: !self.isLoadingInitialData)
                }
            } else if currentSelectedIndex > 0 {
                self.syncedViewModel.selectMonth(
                    at: currentSelectedIndex, animated: !self.isLoadingInitialData)
            }

            // Hide shimmer after cells are configured
            if self.isLoadingInitialData {
                // Force layout pass to ensure cells are rendered
                self.contentView.monthCarousel.layoutIfNeeded()

                // Small delay to ensure cells finish configuring before hiding shimmer
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.contentView.hideShimmerViewsAndShowOriginals()
                    self.isLoadingInitialData = false
                }
            }
        }
    }
    
    func didUpdateTransactions(_ transactions: [Transaction]) {
        DispatchQueue.main.async {
            self.contentView.monthCarousel.reloadData()
        }
        if currentCell != nil {
            let index = syncedViewModel.selectedIndex
            if index < syncedViewModel.monthData.count {
                let model = syncedViewModel.monthData[index]
                let key = DateFormatter.keyFormatter.string(from: model.date)
                let txs = syncedViewModel.allTransactions.filter { tx in
                    let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                    let txKey = DateFormatter.keyFormatter.string(from: txDate)
                    return txKey == key
                }.sorted { (tx1, tx2) -> Bool in
                    return tx1.date > tx2.date
                }
                currentCellTransactions = txs
            }
        }
    }
}

extension DashboardViewController: MonthBudgetCardDelegate {
    func didTapConfigButton() {
        flowDelegate?.navigateToBudgets(date: nil)
    }
    
    func didTapDefineBudgetButton(budgetDate: Date) {
        flowDelegate?.navigateToBudgets(date: budgetDate)
    }
    
    func didToggleBalanceVisibility(_ isHidden: Bool) {
        // Update all month cards with the new visibility state
        updateAllMonthCardsBalanceVisibility(isHidden)
    }

    func didLongPressBalance() {
        let selectedIndex = syncedViewModel.selectedIndex
        guard selectedIndex < syncedViewModel.monthData.count else { return }
        let monthData = syncedViewModel.monthData[selectedIndex]
        let currentBalance = monthData.currentBalance ?? monthData.finalBalance ?? 0
        flowDelegate?.openAdjustBalanceModal(currentBalance: currentBalance, context: viewModel.currentContext)
    }

    func refreshAfterBalanceAdjustment() {
        viewModel.transactionLedger.invalidateCache()
        refreshAfterTransactionAdd()
    }
    
    private func updateAllMonthCardsBalanceVisibility(_ isHidden: Bool) {
        // Store the global visibility state first
        UserDefaultsManager.setHideValues(isHidden)

        // Update all visible month cards and budget cards immediately
        for cell in contentView.monthCarousel.visibleCells {
            if let monthCell = cell as? MonthCarouselCell {
                monthCell.monthCard.updateBalanceVisibility(isHidden)
                monthCell.budgetCard.updateBalanceVisibility(isHidden)
            }
        }

        // Post a notification to update any other cards that might be cached
        NotificationCenter.default.post(
            name: NSNotification.Name("BalanceVisibilityChanged"),
            object: nil,
            userInfo: ["isHidden": isHidden]
        )
    }
}

// MARK: - Transaction Table View Management
extension DashboardViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard
            let parentCell = tableView.superview(of: MonthCarouselCell.self),
            parentCell.tag < syncedViewModel.monthData.count
        else { return 0 }
        
        return parentCell.getDisplayedTransactions().count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell =
        tableView.dequeueReusableCell(withIdentifier: TransactionCell.reuseID, for: indexPath)
        as! TransactionCell
        
        guard
            let parentCell = tableView.superview(of: MonthCarouselCell.self),
            parentCell.tag < syncedViewModel.monthData.count
        else {
            return cell
        }
        
        let txs = parentCell.getDisplayedTransactions()
        guard indexPath.row < txs.count else { return cell }
        
        let tx = txs[indexPath.row]
        
        let txCount: Int? = {
            guard tx.isCreditCardStatement == true else { return nil }
            // Use the count embedded in the synthetic transaction (from secure store)
            // to avoid stale DB vs secure store mismatch
            return tx.totalInstallments ?? 0
        }()

        let configuration = TransactionCellConfiguration(
            category: tx.category,
            title: tx.title,
            date: tx.date,
            value: tx.amount,
            transactionType: tx.type,
            transactionMode: tx.mode,
            installmentNumber: tx.installmentNumber,
            totalInstallments: tx.totalInstallments,
            isCreditCardStatement: tx.isCreditCardStatement ?? false,
            statementTransactionCount: txCount,
            creditCardId: tx.creditCardId
        )
        cell.configure(with: configuration)

        // Credit card statement rows are not directly deletable
        guard tx.isCreditCardStatement != true else {
            cell.onDelete = nil
            cell.selectionStyle = .none
            return cell
        }

        cell.onDelete = { [weak self] completion in
            guard let self = self else { return }
            
            let transactionType = self.viewModel.getTransactionType(id: tx.id!)
            
            if transactionType == .simple {
                // Handle simple transactions with basic confirmation
                showConfirmation(
                    title: "transaction.delete.title".localized,
                    message: "delete.confirmation".localized,
                    okTitle: "alert.delete".localized
                ) {
                    // For simple transactions, only show shimmer on the current month card
                    self.showShimmerOnCurrentCard()
                    
                    switch self.viewModel.deleteTransaction(id: tx.id!) {
                    case .success:
                        self.handleTransactionDeletionSuccess(at: indexPath, transactionId: tx.id!)
                        completion(true)
                    case .failure(let error):
                        logError("Failed to delete transaction: \(error)")
                        // Hide shimmer on error
                        self.hideShimmerOnAllCards()
                        completion(false)
                    }
                } onCancel: {
                    completion(false)
                }
            } else {
                // Handle complex transactions with user choice
                self.showTransactionDeletionOptions(
                    transactionId: tx.id!,
                    transactionType: transactionType,
                    indexPath: indexPath,
                    completion: completion
                )
            }
        }
        cell.selectionStyle = .none
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 67
    }
    
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        return indexPath
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let parentCell = tableView.superview(of: MonthCarouselCell.self),
              parentCell.tag < syncedViewModel.monthData.count
        else { return }
        
        let txs = parentCell.getDisplayedTransactions()
        guard indexPath.row < txs.count else { return }
        
        let selectedTransaction = txs[indexPath.row]

        // Credit card statement rows navigate to Statement Details
        if selectedTransaction.isCreditCardStatement == true,
           let cardId = selectedTransaction.creditCardId,
           let stmtId = selectedTransaction.statementId {
            let cardRepo = CreditCardRepository()
            let stmtRepo = StatementRepository()
            if let card = cardRepo.fetchCard(byId: cardId) {
                let statements = stmtRepo.fetchStatements(forCardId: cardId)
                if let statement = statements.first(where: { $0.id == stmtId }) {
                    flowDelegate?.navigateToStatementDetails(card: card, statement: statement)
                    return
                }
            }
        }

        flowDelegate?.navigateToTransactionDetails(transaction: selectedTransaction)
    }
}

private struct DeletionPromptContent {
    let title: String
    let message: String
    let currentTitle: String
    let futureTitle: String
    let allTitle: String
}

// MARK: - Loading State Management
extension DashboardViewController {
    private func showDeletionLoadingOverlay() {
        // Reuse existing shimmer views from the dashboard for consistent UX
        guard let currentCell = currentCell else { return }
        
        // Create a subtle overlay to indicate deletion is in progress
        let overlay = UIView()
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.1)
        overlay.tag = 999  // Unique tag for removal
        overlay.translatesAutoresizingMaskIntoConstraints = false
        
        currentCell.transactionTableView.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: currentCell.transactionTableView.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: currentCell.transactionTableView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: currentCell.transactionTableView.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: currentCell.transactionTableView.bottomAnchor),
        ])
        
        // Disable table view interaction during deletion
        currentCell.transactionTableView.isUserInteractionEnabled = false
        
        // Add a subtle fade animation
        overlay.alpha = 0
        UIView.animate(withDuration: 0.3) {
            overlay.alpha = 1
        }
    }
    
    private func hideDeletionLoadingOverlay() {
        guard let currentCell = currentCell else { return }
        
        // Re-enable table view interaction
        currentCell.transactionTableView.isUserInteractionEnabled = true
        
        // Remove the overlay with animation
        if let overlay = currentCell.transactionTableView.viewWithTag(999) {
            UIView.animate(
                withDuration: 0.3,
                animations: {
                    overlay.alpha = 0
                }
            ) { _ in
                overlay.removeFromSuperview()
            }
        }
    }
    
    // MARK: - Shimmer Loading for Budget Cards
    
    private func showShimmerLoadingOnCard(_ card: MonthBudgetCard) {
        // Prevent multiple shimmer views
        if card.viewWithTag(998) != nil {
            return
        }
        
        // Create a shimmer overlay that matches the card design
        let shimmerView = ShimmerView()
        shimmerView.style = ShimmerViewStyle(
            baseColor: Colors.gray700.withAlphaComponent(0.3),
            highlightColor: Colors.gray400.withAlphaComponent(0.6),
            duration: 1.0,
            interval: 0.3,
            effectSpan: .points(120),
            effectAngle: 0 * CGFloat.pi
        )
        
        shimmerView.layer.cornerRadius = CornerRadius.extraLarge
        shimmerView.clipsToBounds = true
        shimmerView.tag = 998  // Unique tag for removal
        shimmerView.translatesAutoresizingMaskIntoConstraints = false
        
        card.addSubview(shimmerView)
        NSLayoutConstraint.activate([
            shimmerView.topAnchor.constraint(equalTo: card.topAnchor),
            shimmerView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            shimmerView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            shimmerView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        
        shimmerView.startAnimating()
        
        // Fade in the shimmer
        shimmerView.alpha = 0
        UIView.animate(withDuration: 0.2) {
            shimmerView.alpha = 1
        }
    }
    
    private func hideShimmerLoadingOnCard(_ card: MonthBudgetCard) {
        guard let shimmerView = card.viewWithTag(998) as? ShimmerView else {
            return
        }
        
        // Ensure we're on the main queue
        DispatchQueue.main.async {
            UIView.animate(
                withDuration: 0.3,
                animations: {
                    shimmerView.alpha = 0
                }
            ) { _ in
                shimmerView.stopAnimating()
                shimmerView.removeFromSuperview()
            }
        }
    }
    
    // MARK: - Multi-Card Shimmer Management
    
    private func showShimmerOnCurrentCard() {
        guard let currentCell = currentCell else { return }
        
        // Get the current month index
        let visibleIndexPaths = contentView.monthCarousel.indexPathsForVisibleItems
        if let currentIndexPath = visibleIndexPaths.first {
            showShimmerLoadingOnCard(currentCell.monthCard)
            cardsWithActiveShimmer.insert(currentIndexPath.item)
        }
        
        // Safety mechanism for single card
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.hideShimmerOnAllCards()
        }
    }

    private func showShimmerOnAllVisibleCards() {
        let visibleIndexPaths = contentView.monthCarousel.indexPathsForVisibleItems

        for indexPath in visibleIndexPaths {
            if let cell = contentView.monthCarousel.cellForItem(at: indexPath) as? MonthCarouselCell {
                showShimmerLoadingOnCard(cell.monthCard)
                cardsWithActiveShimmer.insert(indexPath.item)
            }
        }

        // Safety mechanism: ensure shimmer doesn't get stuck for more than 3 seconds
        // This is only a fallback - normal operation should hide shimmer immediately after data updates
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.hideShimmerOnAllCards()
        }
    }
    
    private func hideShimmerOnAllVisibleCards() {
        let visibleIndexPaths = contentView.monthCarousel.indexPathsForVisibleItems
        
        for indexPath in visibleIndexPaths {
            // Only try to hide shimmer on cards that we know have shimmer
            if cardsWithActiveShimmer.contains(indexPath.item),
               let cell = contentView.monthCarousel.cellForItem(at: indexPath) as? MonthCarouselCell
            {
                hideShimmerLoadingOnCard(cell.monthCard)
                cardsWithActiveShimmer.remove(indexPath.item)
            }
        }
    }
    
    private func hideShimmerOnAllCards() {
        // Hide shimmer on all cards that might have it, not just visible ones

        // First try visible cards
        hideShimmerOnAllVisibleCards()

        // For comprehensive cleanup, we need a different approach for non-visible cells
        // We'll schedule a cleanup that triggers when users scroll to affected months
        if !cardsWithActiveShimmer.isEmpty {
            // Force cleanup by trying to access cells that might exist
            for cardIndex in cardsWithActiveShimmer {
                let indexPath = IndexPath(item: cardIndex, section: 0)
                if let cell = contentView.monthCarousel.cellForItem(at: indexPath) as? MonthCarouselCell {
                    hideShimmerLoadingOnCard(cell.monthCard)
                }
            }
        }
        
        // Clear all tracking regardless
        cardsWithActiveShimmer.removeAll()
        
        // Add an additional safety mechanism: clean up any shimmer views that might be orphaned
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.emergencyShimmerCleanup()
        }
    }
    
    private func emergencyShimmerCleanup() {
        // Last resort cleanup - remove any shimmer views that might be stuck

        // Check all currently loaded cells for shimmer views
        for case let cell as MonthCarouselCell in contentView.monthCarousel.visibleCells {
            if let shimmerView = cell.monthCard.viewWithTag(998) {
                shimmerView.removeFromSuperview()
            }
        }
    }
}

extension DashboardViewController {
    func cleanupWithUserPrompt() {
        viewModel.cleanupRecurringTransactionsWithUserPrompt { [weak self] completion in
            let alertController = UIAlertController(
                title: "recurring.cleanup.title".localized,
                message: "recurring.cleanup.message".localized,
                preferredStyle: .alert
            )
            
            let cleanAllAction = UIAlertAction(
                title: "recurring.cleanup.all".localized,
                style: .destructive
            ) { _ in
                completion(.all)
                self?.loadData()
            }
            
            let cleanFutureAction = UIAlertAction(
                title: "recurring.cleanup.future".localized,
                style: .default
            ) { _ in
                completion(.futureOnly)
                self?.loadData()
            }
            
            let cancelAction = UIAlertAction(
                title: "alert.cancel".localized,
                style: .cancel
            )
            
            alertController.addAction(cleanAllAction)
            alertController.addAction(cleanFutureAction)
            alertController.addAction(cancelAction)
            
            self?.present(alertController, animated: true)
        }
    }
    
    private func showTransactionDeletionOptions(
        transactionId: Int,
        transactionType: TransactionComplexityType,
        indexPath: IndexPath,
        completion: @escaping (Bool) -> Void
    ) {
        let content = getDeletionPromptContent(for: transactionType)
        
        let alertController = UIAlertController(
            title: content.title,
            message: content.message,
            preferredStyle: .alert
        )
        
        let deleteCurrentAction = UIAlertAction(
            title: content.currentTitle,
            style: .default
        ) { [weak self] _ in
            self?.performComplexTransactionDeletion(
                transactionId: transactionId,
                cleanupOption: .currentSelection,
                indexPath: indexPath,
                completion: completion
            )
        }
        
        let deleteFutureAction = UIAlertAction(
            title: content.futureTitle,
            style: .default
        ) { [weak self] _ in
            self?.performComplexTransactionDeletion(
                transactionId: transactionId,
                cleanupOption: .futureOnly,
                indexPath: indexPath,
                completion: completion
            )
        }
        
        let deleteAllAction = UIAlertAction(
            title: content.allTitle,
            style: .destructive
        ) { [weak self] _ in
            self?.performComplexTransactionDeletion(
                transactionId: transactionId,
                cleanupOption: .all,
                indexPath: indexPath,
                completion: completion
            )
        }
        
        let cancelAction = UIAlertAction(
            title: "alert.cancel".localized,
            style: .cancel
        ) { _ in
            completion(false)
        }
        
        alertController.addAction(deleteCurrentAction)
        alertController.addAction(deleteFutureAction)
        alertController.addAction(deleteAllAction)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true)
    }
    
    private func getDeletionPromptContent(for transactionType: TransactionComplexityType)
    -> DeletionPromptContent
    {
        switch transactionType {
        case .recurringParent, .recurringInstance:
            return DeletionPromptContent(
                title: "recurring.delete.title".localized,
                message: "recurring.delete.message".localized,
                currentTitle: "recurring.delete.current".localized,
                futureTitle: "recurring.delete.future".localized,
                allTitle: "recurring.delete.all".localized
            )
        case .installmentParent, .installmentInstance:
            return DeletionPromptContent(
                title: "installment.delete.title".localized,
                message: "installment.delete.message".localized,
                currentTitle: "installment.delete.current".localized,
                futureTitle: "installment.delete.remaining".localized,
                allTitle: "installment.delete.all".localized
            )
        case .simple:
            return DeletionPromptContent(
                title: "transaction.delete.title".localized,
                message: "delete.confirmation".localized,
                currentTitle: "alert.delete".localized,
                futureTitle: "alert.delete".localized,
                allTitle: "alert.delete".localized
            )
        }
    }
    
    private func performComplexTransactionDeletion(
        transactionId: Int,
        cleanupOption: RecurringCleanupOption,
        indexPath: IndexPath,
        completion: @escaping (Bool) -> Void
    ) {
        // Set deletion flag to prevent race conditions
        isDeletionInProgress = true
        
        // Show loading state for complex deletions that might affect multiple transactions
        showDeletionLoadingOverlay()
        
        // Complex transactions (recurring/installments) can affect multiple months
        showShimmerOnAllVisibleCards()
        
        viewModel.deleteComplexTransaction(
            transactionId: transactionId,
            cleanupOption: cleanupOption
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.hideDeletionLoadingOverlay()
                
                switch result {
                case .success:
                    self?.handleTransactionDeletionSuccess(at: indexPath, transactionId: transactionId)
                    completion(true)
                case .failure(let error):
                    logError("Error deleting complex transaction: \(error)")
                    // Hide shimmer on error
                    self?.hideShimmerOnAllCards()
                    // Reset deletion flag on error
                    self?.isDeletionInProgress = false
                    completion(false)
                }
            }
        }
    }
    
    private func handleTransactionDeletionSuccess(at indexPath: IndexPath, transactionId: Int) {
        // Ensure we're on main queue for UI updates
        DispatchQueue.main.async {
            guard self.currentCell != nil else {
                self.loadData()
                return
            }
            
            // Shimmer is already shown before deletion starts - no need to show again
            // For recurring transactions, multiple rows might be affected
            // Instead of trying to manually sync, reload the fresh data and update safely
            self.refreshAfterTransactionDeletion()
            
            // Hide shimmer after a brief moment to let users see the data has updated
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.hideShimmerOnAllCards()
                // Reset deletion flag after operation completes
                self.isDeletionInProgress = false
            }
        }
    }
    
    private func refreshAfterTransactionDeletion() {
        // Add a small delay to ensure all async deletion operations have completed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            
            // Load fresh data
            let monthData = self.viewModel.loadMonthlyCards()
            let transactions = self.viewModel.transactionRepo.fetchTransactions()
            
            // Update the view models
            self.syncedViewModel.setMonthData(monthData)
            self.syncedViewModel.setTransactions(self.mergeWithStatementTransactions(transactions))

            // Update current cell data safely first
            if let currentCell = self.currentCell {
                let currentIndex = self.contentView.monthCarousel.indexPathsForVisibleItems.first?.item ?? 0
                
                if currentIndex < self.syncedViewModel.monthData.count {
                    let monthData = self.syncedViewModel.monthData[currentIndex]
                    let key = DateFormatter.keyFormatter.string(from: monthData.date)
                    
                    let filteredTransactions = self.syncedViewModel.allTransactions.filter { tx in
                        let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                        let txKey = DateFormatter.keyFormatter.string(from: txDate)
                        return txKey == key
                    }.sorted { $0.date > $1.date }
                    
                    // Safely update the current cell with new transaction data (preserving day slider)
                    currentCell.monthCard.refresh(with: monthData)
                    currentCell.updateTransactions(filteredTransactions)
                }
            }
            
            // Add a small delay before updating other cells to prevent conflicts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Force refresh visible cells with animation for any other visible cells
                self.refreshVisibleCellsWithAnimation()
            }
        }
    }
    
    // MARK: - Automatic Notification Scheduling
    
    /// Verifica e agenda notificações automaticamente quando necessário
    private func checkAndScheduleNotificationsIfNeeded() {
        let status = viewModel.checkMonthlyNotificationsStatus()
        
        switch status {
        case .notConfigured:
            scheduleNotificationsAutomatically()

        case .outdated:
            scheduleNotificationsAutomatically()

        case .configured:
            break
        }
    }
    
    /// Agenda notificações automaticamente sem interação do usuário
    private func scheduleNotificationsAutomatically() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.scheduleNext30DaysNotifications()
        }
    }
    
    /// Smart notification scheduling for the next 30 days
    private func scheduleNext30DaysNotifications() {
        // Check if user is authenticated first
        guard let user = UserDefaultsManager.getUser(),
              let firebaseUID = user.firebaseUID
        else {
            return
        }
        
        // Get all transactions
        let allTxs = viewModel.transactionRepo.fetchAllTransactions()
        let now = Date()
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        
        // Filter for future transactions in next 30 days (excluding hidden parent transactions)
        let thirtyDaysFromNow = calendar.date(byAdding: .day, value: 30, to: now) ?? now
        
        let next30DaysTxs = allTxs.filter { tx in
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
            
            // Must be in future and within 30 days
            return notificationDate > now && tx.date <= thirtyDaysFromNow
        }.sorted { $0.date < $1.date }  // Sort by date (closest first)
        
        // Get currently pending notifications to avoid duplicates
        UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] requests in
            DispatchQueue.main.async {
                let existingNotificationIds = Set(requests.map { $0.identifier })
                
                // Schedule notifications for transactions that don't already have them
                var scheduledCount = 0
                var skippedCount = 0
                
                for tx in next30DaysTxs {
                    guard let transactionId = tx.id else { continue }
                    
                    let notificationId = "transaction_\(transactionId)"

                    if existingNotificationIds.contains(notificationId) {
                        skippedCount += 1
                        continue
                    }
                    
                    // Schedule the notification
                    self?.scheduleNotificationForTransaction(tx, calendar: calendar)
                    scheduledCount += 1
                    
                    // Respect iOS limit - stop at 50 total (but prioritize by date)
                    if scheduledCount >= 50 {
                        break
                    }
                }

                // Clean up any duplicate notifications
                self?.removeDuplicateNotifications()
            }
        }
    }
    
    /// Schedule notification for a specific transaction
    private func scheduleNotificationForTransaction(_ tx: Transaction, calendar: Calendar) {
        guard let transactionId = tx.id else { return }
        
        let id = "transaction_\(transactionId)"
        
        // Create notification time (8 AM) in local timezone
        var notificationDate = calendar.startOfDay(for: tx.date)
        notificationDate =
        calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate
        
        // Only schedule if notification time is in the future
        guard notificationDate > Date() else { return }
        
        let timeInterval = notificationDate.timeIntervalSinceNow
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        
        let titleKey =
        tx.type == .income
        ? "notification.transaction.title.income" : "notification.transaction.title.expense"
        let bodyKey =
        tx.type == .income
        ? "notification.transaction.body.income" : "notification.transaction.body.expense"
        
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
                logError("Error scheduling notification for \(tx.title): \(error)")
            }
        }
    }
    
    /// Remove duplicate notifications based on content similarity
    private func removeDuplicateNotifications() {
        // Use the improved logic from NotificationDebugManager
        NotificationDebugManager.shared.removeDuplicateNotifications()
    }
    
    // MARK: - Recovery Methods
    
}

// MARK: - UpdateToastManagerDelegate
extension DashboardViewController: UpdateToastManagerDelegate {
    func updateToastManager(_ manager: UpdateToastManager, shouldShowToast: Bool) {
        if shouldShowToast {
            showUpdateToast()
        }
    }
    
    func updateToastManager(_ manager: UpdateToastManager, didDismissToast: Bool) {
        // Handle toast dismissal if needed
    }
}

// MARK: - UpdateToastViewDelegate
extension DashboardViewController: UpdateToastViewDelegate {
    func updateToastViewDidTapUpdate(_ toastView: UpdateToastView) {
        updateToastManager.openAppStore()
        hideUpdateToast()
    }
    
    func updateToastViewDidTapDismiss(_ toastView: UpdateToastView) {
        updateToastManager.markToastAsDismissed()
        hideUpdateToast()
    }
}

// MARK: - DataRecoveryToastManagerDelegate
extension DashboardViewController: DataRecoveryToastManagerDelegate {
    func dataRecoveryToastManager(_ manager: DataRecoveryToastManager, shouldShowToast: Bool) {
        if shouldShowToast {
            showRecoveryToast()
        }
    }
    
    func dataRecoveryToastManager(_ manager: DataRecoveryToastManager, didDismissToast: Bool) {
        // Handle toast dismissal if needed
    }
}

// MARK: - DataRecoveryToastViewDelegate
extension DashboardViewController: DataRecoveryToastViewDelegate {
    func dataRecoveryToastViewDidTapRecover(_ toastView: DataRecoveryToastView) {
        hideRecoveryToast()
        
        // Show loading state
        LoadingManager.shared.showLoading(on: self, message: "Recovering your data...")
        
        // Perform recovery
        recoveryToastManager.performDataRecovery { [weak self] success, message in
            DispatchQueue.main.async {
                LoadingManager.shared.hideLoading()
                
                let alert = UIAlertController(
                    title: success ? "✅ Recovery Complete" : "❌ Recovery Failed",
                    message: message,
                    preferredStyle: .alert
                )
                
                alert.addAction(
                    UIAlertAction(title: "OK", style: .default) { _ in
                        if success {
                            // Refresh dashboard to show recovered data
                            self?.refreshDashboardData()
                        }
                    })
                
                self?.present(alert, animated: true)
            }
        }
    }
    
    func dataRecoveryToastViewDidTapDismiss(_ toastView: DataRecoveryToastView) {
        recoveryToastManager.markToastAsDismissedTemporarily()
        hideRecoveryToast()
    }
}

// MARK: - MonthCarouselCellDelegate
extension DashboardViewController: MonthCarouselCellDelegate {
    func monthCarouselCell(_ cell: MonthCarouselCell, didChangeSearchText text: String) {
        // The cell handles filtering internally, we can add analytics or other logic here if needed
    }
    
    func monthCarouselCellDidTapFilter(_ cell: MonthCarouselCell) {
        // Store reference to the cell that opened the filter modal
        // This ensures filters are applied to the correct cell when the modal is dismissed
        currentCell = cell

        // Get the month date from the current month data
        let monthDate: Date
        let currentIndex = syncedViewModel.selectedIndex
        if currentIndex < syncedViewModel.monthData.count {
            monthDate = syncedViewModel.monthData[currentIndex].date
        } else {
            // Fallback to current date if we can't find the month
            monthDate = Date()
        }

        let filterModal = TransactionFilterModalViewController(currentFilters: globalFilters, monthDate: monthDate)
        filterModal.delegate = self
        present(filterModal, animated: false)
    }
}

// MARK: - Keyboard Handling
extension DashboardViewController {
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dashboardKeyboardWillShow(notification:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dashboardKeyboardWillHide(notification:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    @objc private func dashboardKeyboardWillShow(notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let currentCell = currentCell,
              currentCell.searchInput.textField.isFirstResponder else {
            return
        }
        
        let keyboardHeight = keyboardFrame.height
        
        // Scroll collection view to ensure cell is visible above keyboard
        if let indexPath = contentView.monthCarousel.indexPath(for: currentCell) {
            contentView.monthCarousel.scrollToItem(
                at: indexPath,
                at: .centeredVertically,
                animated: true
            )
        }
        
        // Wait a bit for the scroll animation, then adjust table
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Convert table frame to view coordinates to see how much is covered by keyboard
            guard let tableFrame = currentCell.transactionTableView.superview?.convert(
                currentCell.transactionTableView.frame, to: self.view) else {
                return
            }
            
            let viewHeight = self.view.bounds.height
            let keyboardTopY = viewHeight - keyboardHeight
            let tableBottomY = tableFrame.maxY
            
            // Calculate how much of the table is below the keyboard
            if tableBottomY > keyboardTopY {
                let overlap = tableBottomY - keyboardTopY
                // Add padding to ensure content is visible above keyboard
                let inset = overlap + 40
                
                // Adjust table content inset to account for keyboard
                currentCell.adjustTableForKeyboard(keyboardHeight: inset, animationDuration: animationDuration)
                
                // Scroll to show first result if there are filtered transactions
                if !currentCell.filteredTransactions.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
                        currentCell.transactionTableView.scrollToRow(
                            at: IndexPath(row: 0, section: 0),
                            at: .top,
                            animated: true
                        )
                    }
                }
            } else {
                // Table might still need some inset for better scrolling
                currentCell.adjustTableForKeyboard(keyboardHeight: 20, animationDuration: animationDuration)
            }
        }
    }
    
    @objc private func dashboardKeyboardWillHide(notification: Notification) {
        guard let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let currentCell = currentCell else {
            return
        }
        
        currentCell.adjustTableForKeyboard(keyboardHeight: 0, animationDuration: animationDuration)
    }
}

// MARK: - TransactionFilterModalDelegate
extension DashboardViewController: TransactionFilterModalDelegate {
    func transactionFilterModal(_ modal: TransactionFilterModalViewController, didApplyFilters filters: TransactionFilters) {
        // Store global filters WITHOUT day range - day filters are date-specific
        // and don't make sense across different months
        globalFilters = filters.withoutDayFilter()

        // Apply full filters (including day range) to current cell only
        if let currentCell = findSelectedCell() {
            currentCell.applyFilters(filters)
        }

        // Apply global filters (without day range) to other visible cells
        applyGlobalFiltersToOtherCells()
    }

    func transactionFilterModalDidClear(_ modal: TransactionFilterModalViewController) {
        // Clear global filters
        globalFilters.clear()

        // Clear filters on all visible cells
        clearFiltersOnAllCells()
    }

    /// Applies global filters to all visible month carousel cells except the current one
    /// (current cell gets full filters including day range)
    private func applyGlobalFiltersToOtherCells() {
        guard let visibleCells = contentView.monthCarousel.visibleCells as? [MonthCarouselCell] else { return }
        let selectedIndex = syncedViewModel.selectedIndex
        for cell in visibleCells {
            if cell.tag != selectedIndex {
                cell.applyFilters(globalFilters)
            }
        }
    }

    /// Clears filters on all visible month carousel cells
    private func clearFiltersOnAllCells() {
        guard let visibleCells = contentView.monthCarousel.visibleCells as? [MonthCarouselCell] else { return }
        for cell in visibleCells {
            cell.clearFilters()
        }
    }

    /// Finds the currently selected month carousel cell
    private func findSelectedCell() -> MonthCarouselCell? {
        let visibleCells = contentView.monthCarousel.visibleCells as? [MonthCarouselCell]
        return visibleCells?.first(where: { $0.tag == syncedViewModel.selectedIndex })
    }
}
