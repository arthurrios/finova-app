//
//  AppFlowController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

class AppFlowController {
    // MARK: - Properties
    private var navigationController: UINavigationController?
    private let viewControllersFactory: ViewControllersFactoryProtocol
    /// Tracks whether a pending large-sync notification needs to show InitialSync
    /// once the dashboard becomes visible (handles race condition).
    private var pendingLargeSyncDetected = false
    // MARK: - init
    public init() {
        viewControllersFactory = ViewControllersFactory()
        setupAppRefreshObserver()
    }
    
    // MARK: - startFlow
    func startFlow() -> UINavigationController? {
        let viewController = viewControllersFactory.makeSplashViewController(flowDelegate: self)
        navigationController = UINavigationController(rootViewController: viewController)
        return navigationController
    }
    
    // MARK: - App Refresh on Foreground
    
    /// Sets up observer for app foreground refresh notifications
    private func setupAppRefreshObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterForeground),
            name: .appDidEnterForeground,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigateToTransactionDetails(_:)),
            name: .navigateToTransactionDetails,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigateToStatementDetails(_:)),
            name: .navigateToStatementDetails,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePendingInvitations),
            name: .groupInvitationReceived,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigateToGroupInvitation(_:)),
            name: .navigateToGroupInvitation,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLargeSyncDetected),
            name: .syncRequiresLoadingScreen,
            object: nil
        )
    }
    
    /// Handles navigation to transaction details from notification tap
    @objc private func handleNavigateToTransactionDetails(_ notification: Notification) {
        guard let transactionId = notification.userInfo?["transactionId"] as? Int else {
            logWarning("AppFlowController: No transactionId found in navigation notification")
            return
        }
        
        logDebug("AppFlowController: Navigating to transaction details for ID: \(transactionId)")
        
        // Find the transaction by ID
        let transactionRepo = TransactionRepository()
        let allTransactions = transactionRepo.fetchAllTransactions()
        
        guard let transaction = allTransactions.first(where: { $0.id == transactionId }) else {
            logWarning("AppFlowController: Could not find transaction with ID: \(transactionId)")
            return
        }
        
        // Navigate to transaction details
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Make sure we're on the dashboard first
            self.navigationController?.dismiss(animated: false)
            
            // Check if we need to navigate to dashboard first
            if !(self.navigationController?.topViewController is DashboardViewController) {
                // Pop to root and then push dashboard if needed
                self.navigationController?.popToRootViewController(animated: false)
                let dashboardViewController = self.viewControllersFactory.makeDashboardViewController(
                    flowDelegate: self)
                self.navigationController?.pushViewController(dashboardViewController, animated: false)
            }
            
            // Navigate to transaction details
            let viewController = self.viewControllersFactory.makeTransactionDetailsViewController(
                flowDelegate: self, transaction: transaction)
            self.navigationController?.pushViewController(viewController, animated: true)
        }
    }
    
    /// Handles navigation to statement details from notification tap
    @objc private func handleNavigateToStatementDetails(_ notification: Notification) {
        guard let statementId = notification.userInfo?["statementId"] as? Int,
              let cardId = notification.userInfo?["cardId"] as? Int else {
            logWarning("AppFlowController: Missing statementId or cardId in navigation notification")
            return
        }

        logDebug("AppFlowController: Navigating to statement details for ID: \(statementId)")

        let cardRepo = CreditCardRepository()
        let statementRepo = StatementRepository()

        guard let card = cardRepo.fetchCard(byId: cardId) else {
            logWarning("AppFlowController: Could not find card with ID: \(cardId)")
            return
        }

        let statements = statementRepo.fetchStatements(forCardId: cardId)
        guard let statement = statements.first(where: { $0.id == statementId }) else {
            logWarning("AppFlowController: Could not find statement with ID: \(statementId)")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.navigationController?.dismiss(animated: false)

            if !(self.navigationController?.topViewController is DashboardViewController) {
                self.navigationController?.popToRootViewController(animated: false)
                let dashboardViewController = self.viewControllersFactory.makeDashboardViewController(
                    flowDelegate: self)
                self.navigationController?.pushViewController(dashboardViewController, animated: false)
            }

            self.navigateToStatementDetails(card: card, statement: statement)
        }
    }

    /// Handles pending group invitations received from CloudKit
    @objc private func handlePendingInvitations() {
        // Only auto-present if user is on the dashboard (not splash/login)
        guard navigationController?.topViewController is DashboardViewController else { return }

        let invitations = BudgetGroupService.shared.fetchPendingInvitations()
        guard let first = invitations.first else { return }

        // Avoid presenting over an existing modal
        guard navigationController?.presentedViewController == nil else { return }

        presentGroupInvitation(first)
    }

    /// Handles navigation to group invitation from notification tap
    @objc private func handleNavigateToGroupInvitation(_ notification: Notification) {
        guard let invitationId = notification.userInfo?["invitationId"] as? String else { return }

        let repo = BudgetGroupRepository()
        guard let invitation = repo.fetchInvitation(byId: invitationId),
              invitation.status == "pending" else { return }

        // Dismiss any existing modals first
        guard navigationController?.presentedViewController == nil else {
            navigationController?.dismiss(animated: false) { [weak self] in
                self?.presentGroupInvitation(invitation)
            }
            return
        }
        presentGroupInvitation(invitation)
    }

    /// Handles app foreground refresh notification
    @objc private func handleAppDidEnterForeground() {
        logDebug("AppFlowController: Handling app foreground refresh")
        
        // Refresh the current visible view controller if it's the dashboard
        refreshCurrentViewControllerIfNeeded()
    }
    
    /// Refreshes the current view controller if it supports refresh
    private func refreshCurrentViewControllerIfNeeded() {
        guard let navigationController = navigationController else {
            logWarning("AppFlowController: No navigation controller available for refresh")
            return
        }
        
        // Check if the top view controller is the dashboard
        if let dashboardViewController = navigationController.topViewController
            as? DashboardViewController
        {
            logDebug("AppFlowController: Refreshing dashboard on foreground with animation")
            dashboardViewController.refreshOnForegroundWithAnimation()
        } else {
            logDebug("AppFlowController: Current view controller doesn't support refresh")
        }
    }
    
    // MARK: - Initial Sync Detection

    private func needsInitialSync() -> Bool {
        guard UserDefaultsManager.getSyncEnabled() else { return false }
        return !UserDefaults.standard.bool(forKey: "syncFullPullVerified_v2")
    }

    @objc private func handleLargeSyncDetected() {
        pendingLargeSyncDetected = true
        presentInitialSyncIfReady(attempt: 0)
    }

    /// Attempts to show InitialSync screen when the dashboard is visible.
    /// Retries with delay to handle the race condition where the notification
    /// fires while navigation to the dashboard is still in progress.
    private func presentInitialSyncIfReady(attempt: Int) {
        guard pendingLargeSyncDetected else { return }
        guard let topVC = navigationController?.topViewController else {
            retryPresentInitialSync(attempt: attempt)
            return
        }
        // Already on InitialSync — no-op
        if topVC is InitialSyncViewController {
            pendingLargeSyncDetected = false
            return
        }
        // Dashboard visible — show InitialSync
        if topVC is DashboardViewController {
            pendingLargeSyncDetected = false
            let syncVC = InitialSyncViewController()
            syncVC.flowDelegate = self
            navigationController?.pushViewController(syncVC, animated: true)
            return
        }
        // Some other VC (Splash transitioning, modal, etc.) — retry
        retryPresentInitialSync(attempt: attempt)
    }

    private func retryPresentInitialSync(attempt: Int) {
        guard attempt < 10 else {
            pendingLargeSyncDetected = false
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.presentInitialSyncIfReady(attempt: attempt + 1)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Common Navigation
extension AppFlowController: CommonFlowDelegate {
    func navigateToDashboard() {
        navigationController?.dismiss(animated: false)
        if needsInitialSync() {
            let vc = InitialSyncViewController()
            vc.flowDelegate = self
            navigationController?.pushViewController(vc, animated: true)
        } else {
            let dashboardViewController = viewControllersFactory.makeDashboardViewController(
                flowDelegate: self)
            navigationController?.pushViewController(dashboardViewController, animated: true)
        }
    }
}

// MARK: - Splash
extension AppFlowController: SplashFlowDelegate {
    func navigateToLogin() {
        let viewController = viewControllersFactory.makeLoginViewController(flowDelegate: self)
        viewController.modalPresentationStyle = .overCurrentContext
        viewController.modalTransitionStyle = .crossDissolve
        navigationController?.present(viewController, animated: false) {
            viewController.animateShow()
        }
    }
    
    func navigateDirectlyToDashboard() {
        navigationController?.dismiss(animated: false)
        if needsInitialSync() {
            let vc = InitialSyncViewController()
            vc.flowDelegate = self
            navigationController?.pushViewController(vc, animated: true)
        } else {
            let viewController = viewControllersFactory.makeDashboardViewController(flowDelegate: self)
            navigationController?.pushViewController(viewController, animated: true)
        }
    }
}

// MARK: - Login Flow
extension AppFlowController: LoginFlowDelegate {
    func navigateToRegister() {
        navigationController?.dismiss(animated: false)
        let viewController = viewControllersFactory.makeRegisterViewController(flowDelegate: self)
        viewController.modalPresentationStyle = .overCurrentContext
        viewController.modalTransitionStyle = .crossDissolve
        navigationController?.present(viewController, animated: false) {
            viewController.animateShow()
        }
    }
}

// MARK: - Register Flow
extension AppFlowController: RegisterFlowDelegate {
    func navigateBackToLogin() {
        navigationController?.dismiss(animated: false)
        let viewController = viewControllersFactory.makeLoginViewController(flowDelegate: self)
        viewController.modalPresentationStyle = .overCurrentContext
        viewController.modalTransitionStyle = .crossDissolve
        navigationController?.present(viewController, animated: false) {
            viewController.animateShow()
        }
    }
}

// MARK: - Dashboard Flow
extension AppFlowController: DashboardFlowDelegate, SettingsFlowDelegate, ProfileFlowDelegate, NotificationSettingsFlowDelegate, NotificationHistoryFlowDelegate, SyncSettingsFlowDelegate {
    func navigateToAllocationDetails(allocation: BudgetAllocation) {
        let viewController = ViewControllersFactory.makeBudgetAllocationDetailsViewController(allocation: allocation)
        viewController.flowDelegate = self
        navigationController?.pushViewController(viewController, animated: true)
    }

    func navigateToUnallocatedDetails(unallocatedSpending: UnallocatedCategorySpending) {
        let viewController = ViewControllersFactory.makeBudgetAllocationDetailsViewController(
            unallocatedSpending: unallocatedSpending
        )
        viewController.flowDelegate = self
        navigationController?.pushViewController(viewController, animated: true)
    }

    func navigateToProfile() {
        navigationController?.dismiss(animated: false)
        let viewController = viewControllersFactory.makeProfileViewController(flowDelegate: self)
        navigationController?.pushViewController(viewController, animated: true)
    }

    func dismissProfile() {
        navigationController?.popViewController(animated: true)
    }

    func navigateToSettings() {
        let viewController = viewControllersFactory.makeSettingsViewController(flowDelegate: self)
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    func navigateToNotificationSettings() {
        let viewController = viewControllersFactory.makeNotificationSettingsViewController(
            flowDelegate: self)
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    func dismissNotificationSettings() {
        navigationController?.popViewController(animated: true)
    }
    
    func navigateToNotificationHistory() {
        navigationController?.dismiss(animated: false)
        let viewController = viewControllersFactory.makeNotificationHistoryViewController(
            flowDelegate: self)
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    func dismissNotificationHistory() {
        navigationController?.popViewController(animated: true)
    }
    
    func openAppStoreFromNotificationHistory() {
        // Pop back to dashboard first, then open App Store
        navigationController?.popViewController(animated: true)
        UpdateToastManager.shared.openAppStore()
    }
    
    func navigateToStatementDetailsFromNotificationHistory(statementId: Int) {
        let statementRepo = StatementRepository()
        let cardRepo = CreditCardRepository()

        // Look up the card from the statement's creditCardId
        // We need to search all cards' statements to find the one with this statementId
        guard let user = UserDefaultsManager.getUser(),
              let firebaseUID = user.firebaseUID else {
            logWarning("AppFlowController: Cannot navigate to statement - user not authenticated")
            return
        }

        let cards = cardRepo.fetchAllCards(userId: firebaseUID)
        var foundCard: CreditCard?
        var foundStatement: CreditCardStatement?

        for card in cards {
            guard let cardId = card.id else { continue }
            let statements = statementRepo.fetchStatements(forCardId: cardId)
            if let statement = statements.first(where: { $0.id == statementId }) {
                foundCard = card
                foundStatement = statement
                break
            }
        }

        guard let card = foundCard, let statement = foundStatement else {
            logWarning("AppFlowController: Could not find statement with ID: \(statementId)")
            return
        }

        navigationController?.popViewController(animated: false)
        navigateToStatementDetails(card: card, statement: statement)
    }

    func navigateToGroupInvitationFromNotificationHistory(invitationId: String) {
        let repo = BudgetGroupRepository()
        guard let invitation = repo.fetchInvitation(byId: invitationId) else { return }

        guard invitation.status == "pending" else {
            // Invitation already responded to — just pop back
            navigationController?.popViewController(animated: true)
            return
        }
        presentGroupInvitation(invitation)
    }

    func navigateToTransactionDetailsFromNotificationHistory(transactionId: Int) {
        // Find the transaction by ID
        let transactionRepo = TransactionRepository()
        let allTransactions = transactionRepo.fetchAllTransactions()
        
        guard let transaction = allTransactions.first(where: { $0.id == transactionId }) else {
            logWarning("AppFlowController: Could not find transaction with ID: \(transactionId)")
            return
        }
        
        // Pop notification history and navigate to transaction details
        navigationController?.popViewController(animated: false)
        let viewController = viewControllersFactory.makeTransactionDetailsViewController(
            flowDelegate: self, transaction: transaction)
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    func openAddTransactionModal(context: DataContext) {
        logWarning("openAddTransactionModal: context=\(context), groupId=\(context.groupId ?? "nil")")
        let viewController = viewControllersFactory.makeAddTransactionModalViewController(
            flowDelegate: self)
        viewController.viewModel.activeContext = context
        viewController.modalPresentationStyle = .overCurrentContext
        viewController.modalTransitionStyle = .crossDissolve
        navigationController?.present(viewController, animated: false) {
            viewController.animateShow()
        }
    }

    func openAdjustBalanceModal(currentBalance: Int, context: DataContext) {
        let viewController = AdjustBalanceModalViewController(currentBalance: currentBalance, context: context)
        viewController.flowDelegate = self
        viewController.modalPresentationStyle = .overCurrentContext
        viewController.modalTransitionStyle = .crossDissolve
        navigationController?.present(viewController, animated: true)
    }

    func openAddAllocationModal(forMonth monthAnchor: Int, preselectedCategory: TransactionCategory?) {
        let viewController = AddAllocationModalViewController(
            monthAnchor: monthAnchor,
            preselectedCategory: preselectedCategory
        )
        viewController.flowDelegate = self
        viewController.modalPresentationStyle = .overCurrentContext
        viewController.modalTransitionStyle = .crossDissolve
        navigationController?.present(viewController, animated: true)
    }

    func navigateToBudgets(date: Date?) {
        navigationController?.dismiss(animated: false)
        let budgetsViewController = viewControllersFactory.makeBudgetsViewController(
            flowDelegate: self, date: date)
        navigationController?.pushViewController(budgetsViewController, animated: true)
    }
    
    func logout() {
        navigationController?.dismiss(animated: false)
        
        let viewController = viewControllersFactory.makeLoginViewController(flowDelegate: self)
        
        let transition = CATransition()
        transition.duration = 0.3
        transition.type = .push
        transition.subtype = .fromLeft
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        navigationController?.setNavigationBarHidden(true, animated: false)
        navigationController?.view.backgroundColor = Colors.gray100
        UIApplication.shared.delegate?.window??.backgroundColor = Colors.gray100
        navigationController?.view.layer.add(transition, forKey: kCATransition)
        navigationController?.pushViewController(viewController, animated: false)
        viewController.contentView.containerView.alpha = 1
    }
    
    func navigateToCreditCards() {
        let viewController = viewControllersFactory.makeCreditCardsViewController(flowDelegate: self)
        navigationController?.pushViewController(viewController, animated: true)
    }

    func dismissSettings() {
        navigationController?.popViewController(animated: true)
    }

    func navigateToBudgetGroups() {
        let viewController = viewControllersFactory.makeBudgetGroupsViewController(flowDelegate: self)
        navigationController?.pushViewController(viewController, animated: true)
    }

    func navigateToSyncSettingsFromDashboard() {
        let viewController = viewControllersFactory.makeSyncSettingsViewController(flowDelegate: self)
        navigationController?.pushViewController(viewController, animated: true)
    }

    func navigateToSyncSettings() {
        let viewController = viewControllersFactory.makeSyncSettingsViewController(flowDelegate: self)
        navigationController?.pushViewController(viewController, animated: true)
    }

    func dismissSyncSettings() {
        navigationController?.popViewController(animated: true)
    }

    func navigateToInitialSync() {
        let syncVC = InitialSyncViewController()
        syncVC.flowDelegate = self
        navigationController?.setViewControllers([syncVC], animated: true)
    }
}

// MARK: - Budgets Flow
extension AppFlowController: BudgetsFlowDelegate {
    func navBackToDashboard() {
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - Add Transaction Modal Flow
extension AppFlowController: AddTransactionModalFlowDelegate {
    func didAddTransaction() {
        navigationController?.dismiss(animated: false)
        
        // Trigger immediate dashboard refresh
        DispatchQueue.main.async {
            if let dashboardViewController = self.navigationController?
                .viewControllers
                .compactMap({ $0 as? DashboardViewController })
                .last
            {
                dashboardViewController.refreshAfterTransactionAdd()
            }
        }
    }
    
    func didUpdateTransaction() {
        navigationController?.dismiss(animated: false)

        // Refresh both Dashboard and Transaction Details after updating a transaction
        DispatchQueue.main.async {
            // Refresh Dashboard
            if let dashboardViewController = self.navigationController?
                .viewControllers
                .compactMap({ $0 as? DashboardViewController })
                .last
            {
                dashboardViewController.refreshAfterTransactionAdd()
            }

            // Refresh Transaction Details if it's currently displayed
            if let transactionDetailsViewController = self.navigationController?
                .viewControllers
                .compactMap({ $0 as? TransactionDetailsViewController })
                .last
            {
                transactionDetailsViewController.refreshTransactionData()
            }
        }
    }

    func didTapCreateCreditCard() {
        navigationController?.dismiss(animated: true) {
            let viewController = self.viewControllersFactory.makeAddCreditCardViewController(flowDelegate: self, cardToEdit: nil)
            self.navigationController?.pushViewController(viewController, animated: true)
        }
    }
}

extension AppFlowController: TransactionDetailsFlowDelegate {
    func dismissTransactionDetails() {
        navigationController?.popViewController(animated: true)
    }
    
    func editTransaction(_ transaction: Transaction) {
        let viewController = viewControllersFactory.makeEditTransactionModalViewController(
            transaction: transaction,
            flowDelegate: self
        )
        viewController.modalPresentationStyle = .overCurrentContext
        viewController.modalTransitionStyle = .crossDissolve
        navigationController?.present(viewController, animated: false) {
            viewController.animateShow()
        }
    }
    
    func didDeleteTransaction() {
        navigationController?.popViewController(animated: true)
        
        // Refresh Dashboard after deletion
        DispatchQueue.main.async {
            if let dashboardViewController = self.navigationController?
                .viewControllers
                .compactMap({ $0 as? DashboardViewController })
                .last
            {
                dashboardViewController.refreshAfterTransactionAdd()
            }
        }
    }
    
    func navigateToTransactionDetails(transaction: Transaction) {
        let viewController = viewControllersFactory.makeTransactionDetailsViewController(
            flowDelegate: self, transaction: transaction)
        navigationController?.pushViewController(viewController, animated: true)
    }

    func navigateToStatementDetails(card: CreditCard, statement: CreditCardStatement) {
        let viewController = viewControllersFactory.makeStatementDetailsViewController(
            flowDelegate: self, statement: statement, card: card)
        navigationController?.pushViewController(viewController, animated: true)
    }

    func payInstallmentsEarly(for transaction: Transaction) {
        let viewController = viewControllersFactory.makeEarlyPaymentViewController(
            flowDelegate: self, transaction: transaction)
        navigationController?.pushViewController(viewController, animated: true)
    }
}

// MARK: - EarlyPaymentFlowDelegate

extension AppFlowController: EarlyPaymentFlowDelegate {
    func dismissEarlyPayment() {
        navigationController?.popViewController(animated: true)
    }

    func didCompleteEarlyPayment(paymentId: Int) {
        guard let navigationController = navigationController else { return }

        // Replace the selection screen with the debit that was just created, rather than pushing on
        // top of it: going "back" from the result should return to the transaction the user started
        // from, not to a selection list whose installments are now settled.
        var stack = navigationController.viewControllers
        if stack.last is EarlyPaymentViewController { stack.removeLast() }

        if let payment = TransactionRepository().fetchAllTransactions().first(where: {
            $0.id == paymentId
        }) {
            stack.append(
                viewControllersFactory.makeTransactionDetailsViewController(
                    flowDelegate: self, transaction: payment))
        }

        navigationController.setViewControllers(stack, animated: true)

        // The dashboard behind this stack is showing pre-payment balances.
        DispatchQueue.main.async {
            navigationController.viewControllers
                .compactMap { $0 as? DashboardViewController }
                .last?
                .refreshAfterTransactionAdd()
        }
    }
}

// MARK: - BudgetAllocationDetailsFlowDelegate

extension AppFlowController: BudgetAllocationDetailsFlowDelegate {
    func dismissAllocationDetails() {
        navigationController?.popViewController(animated: true)
    }

    func editAllocation(_ allocation: BudgetAllocation) {
        let viewController = AddAllocationModalViewController(
            monthAnchor: allocation.monthDate,
            allocationToEdit: allocation
        )
        viewController.flowDelegate = self
        viewController.modalPresentationStyle = .overCurrentContext
        viewController.modalTransitionStyle = .crossDissolve
        navigationController?.present(viewController, animated: true)
    }

    func didUpdateAllocation() {
        // Refresh the allocation details view if it's visible
        if let allocationDetailsVC = navigationController?.topViewController
            as? BudgetAllocationDetailsViewController {
            allocationDetailsVC.refreshAfterEdit()
        }

        // Also refresh the dashboard
        if let dashboardViewController = navigationController?
            .viewControllers
            .compactMap({ $0 as? DashboardViewController })
            .last
        {
            dashboardViewController.refreshAfterAllocationChange()
        }
    }

    func didDeleteAllocation() {
        navigationController?.popViewController(animated: true)

        // Refresh the dashboard after deletion
        DispatchQueue.main.async { [weak self] in
            if let dashboardViewController = self?.navigationController?
                .viewControllers
                .compactMap({ $0 as? DashboardViewController })
                .last
            {
                dashboardViewController.refreshAfterAllocationChange()
            }
        }
    }

    func createAllocation(forCategory category: TransactionCategory, monthAnchor: Int) {
        // Verify the category is still available for allocation in this month
        // (handles race conditions or if a recurring allocation now covers this month)
        let allocationService = BudgetAllocationService()
        let availableCategories = allocationService.getAvailableCategoriesForAllocation(monthAnchor: monthAnchor)

        guard availableCategories.contains(where: { $0.key == category.key }) else {
            // Category already has an allocation - show alert and go back to dashboard
            let alert = UIAlertController(
                title: "allocation.already.exists.title".localized,
                message: String(
                    format: "allocation.already.exists.message".localized,
                    category.displayName
                ),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                // Pop back to dashboard and refresh
                self?.navigationController?.popViewController(animated: true)
                DispatchQueue.main.async {
                    if let dashboardViewController = self?.navigationController?
                        .viewControllers
                        .compactMap({ $0 as? DashboardViewController })
                        .last
                    {
                        dashboardViewController.refreshAfterAllocationChange()
                    }
                }
            })
            navigationController?.topViewController?.present(alert, animated: true)
            return
        }

        // Open the add allocation modal with the category pre-selected
        let viewController = AddAllocationModalViewController(
            monthAnchor: monthAnchor,
            preselectedCategory: category
        )
        viewController.flowDelegate = self
        viewController.modalPresentationStyle = .overCurrentContext
        viewController.modalTransitionStyle = .crossDissolve
        navigationController?.present(viewController, animated: true)
    }
}

// MARK: - Credit Cards Flow
extension AppFlowController: CreditCardsFlowDelegate {
    func dismissCreditCards() {
        navigationController?.popViewController(animated: true)
    }

    func navigateToAddCreditCard() {
        let viewController = viewControllersFactory.makeAddCreditCardViewController(flowDelegate: self, cardToEdit: nil)
        navigationController?.pushViewController(viewController, animated: true)
    }

    func navigateToEditCreditCard(_ card: CreditCard) {
        let viewController = viewControllersFactory.makeAddCreditCardViewController(flowDelegate: self, cardToEdit: card)
        navigationController?.pushViewController(viewController, animated: true)
    }
}

// MARK: - Add Credit Card Flow
extension AppFlowController: AddCreditCardFlowDelegate {
    func dismissAddCreditCard() {
        navigationController?.popViewController(animated: true)
    }

    func didSaveCreditCard() {
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - Statement Details Flow
extension AppFlowController: StatementDetailsFlowDelegate {
    func dismissStatementDetails() {
        navigationController?.popViewController(animated: true)
    }

    func didMarkStatementAsPaid() {
        // Pop back and refresh dashboard
        navigationController?.popViewController(animated: true)
        refreshDashboard()
    }

    func didDeleteTransactionInStatement() {
        // Refresh dashboard to reflect updated statement totals
        refreshDashboard()
    }

    private func refreshDashboard() {
        DispatchQueue.main.async {
            if let dashboardViewController = self.navigationController?
                .viewControllers
                .compactMap({ $0 as? DashboardViewController })
                .last
            {
                dashboardViewController.refreshAfterTransactionAdd()
            }
        }
    }
}

// MARK: - AdjustBalanceModalFlowDelegate

extension AppFlowController: AdjustBalanceModalFlowDelegate {
    func dismissAdjustBalanceModal() {
        navigationController?.dismiss(animated: true)
    }

    func didAdjustBalance() {
        navigationController?.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let dashboardViewController = self.navigationController?
                    .viewControllers
                    .compactMap({ $0 as? DashboardViewController })
                    .last
                {
                    dashboardViewController.refreshAfterBalanceAdjustment()
                }
            }
        }
    }
}

// MARK: - Budget Groups Flow
extension AppFlowController: BudgetGroupsFlowDelegate {
    func dismissBudgetGroups() {
        navigationController?.popViewController(animated: true)
    }

    func navigateToGroupDetails(group: BudgetGroup) {
        let viewController = viewControllersFactory.makeGroupDetailsViewController(flowDelegate: self, group: group)
        navigationController?.pushViewController(viewController, animated: true)
    }

    func openCreateGroupModal() {
        // Handled inline by BudgetGroupsViewController via alert
    }

    func presentGroupInvitationFromGroups(invitation: GroupInvitation) {
        presentGroupInvitation(invitation)
    }
}

// MARK: - Group Details Flow
extension AppFlowController: GroupDetailsFlowDelegate {
    func dismissGroupDetails() {
        navigationController?.popViewController(animated: true)
    }

    func navigateToMemberPermissions(member: GroupMember, group: BudgetGroup) {
        let viewController = viewControllersFactory.makeMemberPermissionsViewController(
            flowDelegate: self, member: member, group: group)
        navigationController?.pushViewController(viewController, animated: true)
    }

    func openInviteMemberModal(group: BudgetGroup) {
        let vc = viewControllersFactory.makeInviteMemberViewController(flowDelegate: self, group: group)
        vc.modalPresentationStyle = .pageSheet
        if let sheet = vc.sheetPresentationController {
            let defaultDetent = UISheetPresentationController.Detent.custom(
                identifier: InviteMemberViewController.defaultDetentIdentifier
            ) { context in
                return context.maximumDetentValue * 0.50
            }
            // Only set default detent initially — VC manages adding/removing
            // expanded detent dynamically to prevent keyboard auto-expansion
            sheet.detents = [defaultDetent]
            sheet.selectedDetentIdentifier = InviteMemberViewController.defaultDetentIdentifier
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = CornerRadius.bottomSheet
        }
        navigationController?.present(vc, animated: true)
    }
}

// MARK: - InviteMemberFlowDelegate
extension AppFlowController: InviteMemberFlowDelegate {
    func dismissInviteMember() {
        navigationController?.dismiss(animated: true)
    }
}

// MARK: - MemberPermissionsFlowDelegate
extension AppFlowController: MemberPermissionsFlowDelegate {
    func dismissMemberPermissions() {
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - GroupInvitationFlowDelegate
extension AppFlowController: GroupInvitationFlowDelegate {
    func presentGroupInvitation(_ invitation: GroupInvitation) {
        let vc = viewControllersFactory.makeGroupInvitationViewController(
            flowDelegate: self, invitation: invitation)
        vc.modalPresentationStyle = .pageSheet
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = CornerRadius.bottomSheet
        }
        navigationController?.topViewController?.present(vc, animated: true)
    }

    func didAcceptInvitation() {
        navigationController?.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            // Show InitialSync screen to wait for full group data sync
            let syncVC = InitialSyncViewController()
            syncVC.flowDelegate = self
            self.navigationController?.pushViewController(syncVC, animated: true)
        }
    }

    func didDeclineInvitation() {
        navigationController?.dismiss(animated: true)
    }

    func didDismissInvitation() {
        navigationController?.dismiss(animated: true)
    }
}

// MARK: - AddAllocationModalFlowDelegate

extension AppFlowController: AddAllocationModalFlowDelegate {
    func dismissAllocationModal() {
        navigationController?.dismiss(animated: true)
    }

    func didSaveAllocation() {
        navigationController?.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }

            // Check if we're on the unallocated details screen (creating new allocation)
            // In that case, pop back to dashboard since the unallocated category is now allocated
            if let allocationDetailsVC = self.navigationController?.topViewController
                as? BudgetAllocationDetailsViewController,
               allocationDetailsVC.isUnallocatedMode {
                // Pop back to dashboard after creating allocation
                // Use CATransaction to properly sequence the refresh after pop completes
                CATransaction.begin()
                CATransaction.setCompletionBlock { [weak self] in
                    // Refresh dashboard after pop animation completes
                    DispatchQueue.main.async {
                        if let dashboardViewController = self?.navigationController?
                            .viewControllers
                            .compactMap({ $0 as? DashboardViewController })
                            .last
                        {
                            dashboardViewController.refreshAfterAllocationChange()
                        }
                    }
                }
                self.navigationController?.popViewController(animated: true)
                CATransaction.commit()
            } else {
                // Editing existing allocation or regular add from dashboard
                DispatchQueue.main.async {
                    // Refresh allocation details if it's visible (for edit case)
                    if let allocationDetailsVC = self.navigationController?.topViewController
                        as? BudgetAllocationDetailsViewController {
                        allocationDetailsVC.refreshAfterEdit()
                    }

                    // Also refresh the dashboard
                    if let dashboardViewController = self.navigationController?
                        .viewControllers
                        .compactMap({ $0 as? DashboardViewController })
                        .last
                    {
                        dashboardViewController.refreshAfterAllocationChange()
                    }
                }
            }
        }
    }
}

// MARK: - InitialSyncFlowDelegate

extension AppFlowController: InitialSyncFlowDelegate {
    func initialSyncDidComplete() {
        pendingLargeSyncDetected = false
        let dashboardVC = viewControllersFactory.makeDashboardViewController(flowDelegate: self)
        navigationController?.setViewControllers([dashboardVC], animated: true)
    }
}
