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
    }
    
    // MARK: - startFlow
    func startFlow() -> UINavigationController? {
        let viewController = viewControllersFactory.makeSplashViewController(flowDelegate: self)
        navigationController = UINavigationController(rootViewController: viewController)
        return navigationController
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
    
    func navigateToDirectlyToDashboard() {
        navigationController?.dismiss(animated: false)
        let viewController = viewControllersFactory.makeDashboardViewController(flowDelegate: self)
        navigationController?.pushViewController(viewController, animated: true)
    }
}

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
    
    func navigateToDashboard() {
        navigationController?.dismiss(animated: false)
        let dashboardViewController = viewControllersFactory.makeDashboardViewController(
            flowDelegate: self)
        navigationController?.pushViewController(dashboardViewController, animated: true)
    }
}

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

extension AppFlowController: DashboardFlowDelegate {
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
}

extension AppFlowController: BudgetsFlowDelegate {
    func navBackToDashboard() {
        navigationController?.popViewController(animated: true)
    }
}

extension AppFlowController: AddTransactionModalFlowDelegate {
    func didAddTransaction() {
        navigationController?.dismiss(animated: false)
        if let dashboardViewController = self.navigationController?
            .viewControllers
            .compactMap({ $0 as? DashboardViewController })
            .last {
            dashboardViewController.loadData()
        }
    }
}
