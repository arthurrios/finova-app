//
//  ViewControllersFactoryProtocol.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

protocol ViewControllersFactoryProtocol: AnyObject {
    func makeSplashViewController(flowDelegate: SplashFlowDelegate) -> SplashViewController
    func makeLoginViewController(flowDelegate: LoginFlowDelegate) -> LoginViewController
    func makeDashboardViewController(flowDelegate: DashboardFlowDelegate) -> DashboardViewController
    func makeBudgetsViewController(flowDelegate: BudgetsFlowDelegate, date: Date?)
    -> BudgetsViewController
    func makeAddTransactionModalViewController(flowDelegate: AddTransactionModalFlowDelegate)
    -> AddTransactionModalViewController
    func makeRegisterViewController(flowDelegate: RegisterFlowDelegate) -> RegisterViewController
}
