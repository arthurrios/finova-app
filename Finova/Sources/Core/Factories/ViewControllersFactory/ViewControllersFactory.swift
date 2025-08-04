//
//  ViewControllersFactory.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

final class ViewControllersFactory: ViewControllersFactoryProtocol {
    func makeRegisterViewController(flowDelegate: any RegisterFlowDelegate) -> RegisterViewController {
        let contentView = RegisterView()
        let viewModel = RegisterViewModel()
        let viewController = RegisterViewController(contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }
    
    func makeAddTransactionModalViewController(flowDelegate: any AddTransactionModalFlowDelegate)
    -> AddTransactionModalViewController {
        let contentView = AddTransactionModalView()
        let viewModel = AddTransactionModalViewModel()
        let viewController = AddTransactionModalViewController(
            contentView: contentView, flowDelegate: flowDelegate, viewModel: viewModel)
        return viewController
    }
    
    func makeSplashViewController(flowDelegate: SplashFlowDelegate) -> SplashViewController {
        let contentView = SplashView()
        let viewController = SplashViewController(contentView: contentView, flowDelegate: flowDelegate)
        return viewController
    }
    
    func makeLoginViewController(flowDelegate: LoginFlowDelegate) -> LoginViewController {
        let contentView = LoginView()
        let viewModel = LoginViewModel()
        let viewController = LoginViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }
    
    func makeDashboardViewController(flowDelegate: DashboardFlowDelegate) -> DashboardViewController {
        let contentView = DashboardView()
        let viewModel = DashboardViewModel()
        let viewController = DashboardViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }
    
    func makeBudgetsViewController(flowDelegate: BudgetsFlowDelegate, date: Date?)
    -> BudgetsViewController {
        let contentView = BudgetsView()
        let viewModel = BudgetsViewModel(initialDate: date)
        let viewController = BudgetsViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }
    
    func makeSettingsViewController(flowDelegate: SettingsFlowDelegate) -> SettingsViewController {
        let contentView = SettingsView()
        let viewModel = SettingsViewModel()
        let viewController = SettingsViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }
    
    func makeCategoriesViewController(flowDelegate: any CategoriesFlowDelegate) -> CategoriesViewController {
        let contentView = CategoriesView()
        let viewModel = CategoriesViewModel()
        let viewController = CategoriesViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }
    
    // MARK: - Custom Tab Bar Controller
    func makeCustomTabBarController(flowDelegate: CustomTabBarControllerDelegate) -> CustomTabBarController {
        let tabBarController = CustomTabBarController(nibName: nil, bundle: nil)
        tabBarController.customDelegate = flowDelegate
        return tabBarController
    }
}
