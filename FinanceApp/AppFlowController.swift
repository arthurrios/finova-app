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
    func didFinishSplashFlow() {
    }
    
    func navigateToDashboardFlow() {
    }
}
