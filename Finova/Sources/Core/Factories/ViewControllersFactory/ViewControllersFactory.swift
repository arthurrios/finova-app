//
//  ViewControllersFactory.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

final class ViewControllersFactory: ViewControllersFactoryProtocol {

  func makeRegisterViewController(flowDelegate: any RegisterFlowDelegate) -> RegisterViewController
  {
    let contentView = RegisterView()
    let viewModel = RegisterViewModel()
    let viewController = RegisterViewController(
      contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
    return viewController
  }

  func makeAddTransactionModalViewController(flowDelegate: any AddTransactionModalFlowDelegate)
    -> AddTransactionModalViewController
  {
    let contentView = AddTransactionModalView()
    let viewModel = AddTransactionModalViewModel()
    let viewController = AddTransactionModalViewController(
      contentView: contentView, flowDelegate: flowDelegate, viewModel: viewModel)
    return viewController
  }

  func makeEditTransactionModalViewController(
    transaction: Transaction,
    flowDelegate: AddTransactionModalFlowDelegate
  ) -> AddTransactionModalViewController {
    return AddTransactionModalViewController.forEdit(
      transaction: transaction,
      flowDelegate: flowDelegate
    )
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
    -> BudgetsViewController
  {
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

  func makeTransactionDetailsViewController(
    flowDelegate: TransactionDetailsFlowDelegate,
    transaction: Transaction
  ) -> TransactionDetailsViewController {
    let contentView = TransactionDetailsView()
    let viewModel = TransactionDetailsViewModel(
      transactionRepository: TransactionRepository(),
      transaction: transaction
    )
    let viewController = TransactionDetailsViewController(
      contentView: contentView,
      viewModel: viewModel,
      flowDelegate: flowDelegate
    )
    return viewController
  }

  func makeNotificationSettingsViewController(
    flowDelegate: NotificationSettingsFlowDelegate
  ) -> NotificationSettingsViewController {
    let contentView = NotificationSettingsView()
    let viewModel = NotificationSettingsViewModel()
    let viewController = NotificationSettingsViewController(
      contentView: contentView,
      viewModel: viewModel,
      flowDelegate: flowDelegate
    )
    return viewController
  }
}
