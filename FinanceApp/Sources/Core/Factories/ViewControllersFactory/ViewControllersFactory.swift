//
//  ViewControllersFactory.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation

final class ViewControllersFactory: ViewControllersFactoryProtocol {
    func makeSplashViewController(flowDelegate: SplashFlowDelegate) -> SplashViewController {
        let contentView = SplashView()
        let viewController = SplashViewController(contentView: contentView, flowDelegate: flowDelegate)
        return viewController
    }
    
    func makeLoginViewController(flowDelegate: LoginFlowDelegate) -> LoginViewController {
        let contentView = LoginView()
        let viewModel = LoginViewModel()
        let viewController = LoginViewController(contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }
    
    func makeDashboardViewController(flowDelegate: DashboardFlowDelegate) -> DashboardViewController {
        let contentView = DashboardView()
        let viewModel = DashboardViewModel()
        let viewController = DashboardViewController(contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }
    
    func makeBudgetsViewController(flowDelegate: BudgetsFlowDelegate, date: Date?) -> BudgetsViewController {
        let contentView = BudgetsView()
        let viewModel = BudgetsViewModel(initialDate: date)
        let viewController = BudgetsViewController(contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }
}
