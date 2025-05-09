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
        self.viewControllersFactory = ViewControllersFactory()
    }
    
    // MARK: - startFlow
    func startFlow() -> UINavigationController? {
        let startViewController = viewControllersFactory.makeSplashViewController(flowDelegate: self)
        self.navigationController = UINavigationController(rootViewController: startViewController)
        return navigationController
    }
}

// MARK: - Splash
extension AppFlowController: SplashFlowDelegate {
    func navigateToLogin() {
        let loginViewController = viewControllersFactory.makeLoginViewController(flowDelegate: self)
        loginViewController.modalPresentationStyle = .overCurrentContext
        loginViewController.modalTransitionStyle = .crossDissolve
        navigationController?.present(loginViewController, animated: false) {
            loginViewController.animateShow()
        }
        
        func navigateToDashboard() {
            self.navigationController?.dismiss(animated: false)
            let dashboardViewController = viewControllersFactory.makeDashboardViewController(flowDelegate: self)
            self.navigationController?.pushViewController(dashboardViewController, animated: true)
        }
    }
}

extension AppFlowController: LoginFlowDelegate {
    func sendLoginData(name: String, email: String, password: String) {
        //
    }
    
    func navigateToDashboard() {
        self.navigationController?.dismiss(animated: false)
        let dashboardViewController = viewControllersFactory.makeDashboardViewController(flowDelegate: self)
        self.navigationController?.pushViewController(dashboardViewController, animated: true)
    }
}

extension AppFlowController: DashboardFlowDelegate {
    
}
