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
  func makeEditTransactionModalViewController(
    transaction: Transaction,
    flowDelegate: AddTransactionModalFlowDelegate
  ) -> AddTransactionModalViewController
  func makeRegisterViewController(flowDelegate: RegisterFlowDelegate) -> RegisterViewController
  func makeProfileViewController(flowDelegate: ProfileFlowDelegate) -> ProfileViewController
  func makeSettingsViewController(flowDelegate: SettingsFlowDelegate) -> SettingsViewController
  func makeTransactionDetailsViewController(
    flowDelegate: TransactionDetailsFlowDelegate,
    transaction: Transaction
  ) -> TransactionDetailsViewController
  func makeEarlyPaymentViewController(
    flowDelegate: EarlyPaymentFlowDelegate,
    transaction: Transaction
  ) -> EarlyPaymentViewController
  func makeNotificationSettingsViewController(
    flowDelegate: NotificationSettingsFlowDelegate
  ) -> NotificationSettingsViewController
  func makeNotificationHistoryViewController(
    flowDelegate: NotificationHistoryFlowDelegate
  ) -> NotificationHistoryViewController
  func makeCreditCardsViewController(flowDelegate: CreditCardsFlowDelegate) -> CreditCardsViewController
  func makeAddCreditCardViewController(flowDelegate: AddCreditCardFlowDelegate, cardToEdit: CreditCard?) -> AddCreditCardViewController
  func makeStatementDetailsViewController(flowDelegate: StatementDetailsFlowDelegate, statement: CreditCardStatement, card: CreditCard) -> StatementDetailsViewController
  func makeStatementPaymentViewController(flowDelegate: StatementPaymentFlowDelegate, statement: CreditCardStatement, card: CreditCard) -> StatementPaymentViewController
  func makeBudgetGroupsViewController(flowDelegate: BudgetGroupsFlowDelegate) -> BudgetGroupsViewController
  func makeAllocationTagsViewController(flowDelegate: AllocationTagsFlowDelegate) -> AllocationTagsViewController
  func makeAllocationTagEditViewController(flowDelegate: AllocationTagEditFlowDelegate, tag: AllocationTag) -> AllocationTagEditViewController
  func makeAllocationTagCategoriesViewController(flowDelegate: AllocationTagCategoriesFlowDelegate, tag: AllocationTag) -> AllocationTagCategoriesViewController
  func makeGroupDetailsViewController(flowDelegate: GroupDetailsFlowDelegate, group: BudgetGroup) -> GroupDetailsViewController
  func makeInviteMemberViewController(flowDelegate: InviteMemberFlowDelegate, group: BudgetGroup) -> InviteMemberViewController
  func makeMemberPermissionsViewController(flowDelegate: MemberPermissionsFlowDelegate, member: GroupMember, group: BudgetGroup) -> MemberPermissionsViewController
  func makeGroupInvitationViewController(flowDelegate: GroupInvitationFlowDelegate, invitation: GroupInvitation) -> GroupInvitationViewController
  func makeSyncSettingsViewController(flowDelegate: SyncSettingsFlowDelegate) -> SyncSettingsViewController
}
