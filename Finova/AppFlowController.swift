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
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Common Navigation
extension AppFlowController: CommonFlowDelegate {
    func navigateToDashboard() {
        navigationController?.dismiss(animated: false)
        let dashboardViewController = viewControllersFactory.makeDashboardViewController(
            flowDelegate: self)
        navigationController?.pushViewController(dashboardViewController, animated: true)
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
        let viewController = viewControllersFactory.makeDashboardViewController(flowDelegate: self)
        navigationController?.pushViewController(viewController, animated: true)
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
extension AppFlowController: DashboardFlowDelegate, SettingsFlowDelegate, NotificationSettingsFlowDelegate, NotificationHistoryFlowDelegate {
    func navigateToAllocationDetails(allocation: BudgetAllocation) {
        let viewController = ViewControllersFactory.makeBudgetAllocationDetailsViewController(allocation: allocation)
        viewController.flowDelegate = self
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    
    func navigateToSettings() {
        navigationController?.dismiss(animated: false)
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
    
    func openAddTransactionModal() {
        let viewController = viewControllersFactory.makeAddTransactionModalViewController(
            flowDelegate: self)
        viewController.modalPresentationStyle = .overCurrentContext
        viewController.modalTransitionStyle = .crossDissolve
        navigationController?.present(viewController, animated: false) {
            viewController.animateShow()
        }
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
    
    func dismissSettings() {
        navigationController?.popViewController(animated: true)
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
}

// MARK: - BudgetAllocationDetailsFlowDelegate

extension AppFlowController: BudgetAllocationDetailsFlowDelegate {
    func dismissAllocationDetails() {
        navigationController?.popViewController(animated: true)
    }
    
    func didUpdateAllocation() {
        navigationController?.popViewController(animated: true)
    }
    
    func didDeleteAllocation() {
        navigationController?.popViewController(animated: true)
    }
}
