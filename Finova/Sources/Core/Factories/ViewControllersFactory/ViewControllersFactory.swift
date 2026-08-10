//
//  ViewControllersFactory.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

final class ViewControllersFactory: ViewControllersFactoryProtocol {

    // MARK: - Shared Repository Instances
    let transactionRepository = TransactionRepository()

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
    
    func makeProfileViewController(flowDelegate: ProfileFlowDelegate) -> ProfileViewController {
        let contentView = ProfileView()
        let viewModel = ProfileViewModel()
        let viewController = ProfileViewController(
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
            transactionRepository: transactionRepository,
            transaction: transaction
        )
        let viewController = TransactionDetailsViewController(
            contentView: contentView,
            viewModel: viewModel,
            flowDelegate: flowDelegate
        )
        return viewController
    }
    
    func makeEarlyPaymentViewController(
        flowDelegate: EarlyPaymentFlowDelegate,
        transaction: Transaction
    ) -> EarlyPaymentViewController {
        let contentView = EarlyPaymentView()
        let viewModel = EarlyPaymentViewModel(transaction: transaction)
        let viewController = EarlyPaymentViewController(
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
    
    func makeNotificationHistoryViewController(
        flowDelegate: NotificationHistoryFlowDelegate
    ) -> NotificationHistoryViewController {
        let contentView = NotificationHistoryView()
        let viewModel = NotificationHistoryViewModel()
        let viewController = NotificationHistoryViewController(
            contentView: contentView,
            viewModel: viewModel,
            flowDelegate: flowDelegate
        )
        return viewController
    }
    
    func makeCreditCardsViewController(flowDelegate: CreditCardsFlowDelegate) -> CreditCardsViewController {
        let contentView = CreditCardsView()
        let viewModel = CreditCardsViewModel()
        let viewController = CreditCardsViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }

    func makeAddCreditCardViewController(flowDelegate: AddCreditCardFlowDelegate, cardToEdit: CreditCard? = nil) -> AddCreditCardViewController {
        let contentView = AddCreditCardView()
        let viewModel = AddCreditCardViewModel()
        viewModel.cardToEdit = cardToEdit
        let viewController = AddCreditCardViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }

    func makeStatementDetailsViewController(flowDelegate: StatementDetailsFlowDelegate, statement: CreditCardStatement, card: CreditCard) -> StatementDetailsViewController {
        let contentView = StatementDetailsView()
        let viewModel = StatementDetailsViewModel(card: card, statement: statement)
        let viewController = StatementDetailsViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }

    func makeStatementPaymentViewController(flowDelegate: StatementPaymentFlowDelegate, statement: CreditCardStatement, card: CreditCard) -> StatementPaymentViewController {
        let contentView = StatementPaymentView()
        let viewModel = StatementPaymentViewModel(card: card, statement: statement)
        let viewController = StatementPaymentViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }

    func makeBudgetGroupsViewController(flowDelegate: BudgetGroupsFlowDelegate) -> BudgetGroupsViewController {
        let contentView = BudgetGroupsView()
        let viewModel = BudgetGroupsViewModel()
        let viewController = BudgetGroupsViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }

    func makeAllocationTagsViewController(flowDelegate: AllocationTagsFlowDelegate) -> AllocationTagsViewController {
        let contentView = AllocationTagsView()
        let viewModel = AllocationTagsViewModel()
        let viewController = AllocationTagsViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }

    func makeAllocationTagEditViewController(flowDelegate: AllocationTagEditFlowDelegate, tag: AllocationTag) -> AllocationTagEditViewController {
        let contentView = AllocationTagEditView()
        let viewController = AllocationTagEditViewController(
            contentView: contentView, tag: tag, flowDelegate: flowDelegate)
        return viewController
    }

    func makeAllocationTagCategoriesViewController(flowDelegate: AllocationTagCategoriesFlowDelegate, tag: AllocationTag) -> AllocationTagCategoriesViewController {
        let contentView = AllocationTagCategoriesView()
        let viewController = AllocationTagCategoriesViewController(
            contentView: contentView, tag: tag, flowDelegate: flowDelegate)
        return viewController
    }

    func makeGroupDetailsViewController(flowDelegate: GroupDetailsFlowDelegate, group: BudgetGroup) -> GroupDetailsViewController {
        let contentView = GroupDetailsView()
        let viewModel = GroupDetailsViewModel(group: group)
        let viewController = GroupDetailsViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }

    func makeInviteMemberViewController(flowDelegate: InviteMemberFlowDelegate, group: BudgetGroup) -> InviteMemberViewController {
        let contentView = InviteMemberView()
        let viewModel = InviteMemberViewModel(group: group)
        let viewController = InviteMemberViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }

    func makeMemberPermissionsViewController(flowDelegate: MemberPermissionsFlowDelegate, member: GroupMember, group: BudgetGroup) -> MemberPermissionsViewController {
        let contentView = MemberPermissionsView()
        let viewModel = MemberPermissionsViewModel(member: member, group: group)
        let viewController = MemberPermissionsViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }

    func makeGroupInvitationViewController(flowDelegate: GroupInvitationFlowDelegate, invitation: GroupInvitation) -> GroupInvitationViewController {
        let contentView = GroupInvitationView()
        let viewModel = GroupInvitationViewModel(invitation: invitation)
        let viewController = GroupInvitationViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }

    func makeSyncSettingsViewController(flowDelegate: SyncSettingsFlowDelegate) -> SyncSettingsViewController {
        let contentView = SyncSettingsView()
        let viewModel = SyncSettingsViewModel()
        let viewController = SyncSettingsViewController(
            contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
        return viewController
    }

    // MARK: - Budget Allocation Details

    static func makeBudgetAllocationDetailsViewController(
        allocation: BudgetAllocation
    ) -> BudgetAllocationDetailsViewController {
        return BudgetAllocationDetailsViewController(allocation: allocation)
    }

    static func makeBudgetAllocationDetailsViewController(
        unallocatedSpending: UnallocatedCategorySpending
    ) -> BudgetAllocationDetailsViewController {
        return BudgetAllocationDetailsViewController(unallocatedSpending: unallocatedSpending)
    }

    // MARK: - Projection Explainer

    /// Takes the projection rather than the inputs to build one: the card has already computed it, and
    /// a second construction site for that formula would drift from the first.
    static func makeProjectionExplainerViewController(
        projection: AllocationBalanceProjection,
        balanceDay: Int,
        allocations: [BudgetAllocation],
        monthAnchor: Int,
        ledgerScope: LedgerScope
    ) -> ProjectionExplainerViewController {
        return ProjectionExplainerViewController(
            contentView: ProjectionExplainerView(),
            viewModel: ProjectionExplainerViewModel(
                projection: projection,
                balanceDay: balanceDay,
                allocations: allocations,
                monthAnchor: monthAnchor,
                ledgerScope: ledgerScope))
    }
}
