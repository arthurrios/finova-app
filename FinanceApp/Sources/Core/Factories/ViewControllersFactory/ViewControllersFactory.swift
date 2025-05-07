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
        let viewController = LoginViewController(contentView: contentView, flowDelegate: flowDelegate)
        return viewController
    }
}
