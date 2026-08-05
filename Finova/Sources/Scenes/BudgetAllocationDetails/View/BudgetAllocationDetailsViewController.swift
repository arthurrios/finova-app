//
//  BudgetAllocationDetailsViewController.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import UIKit

final class BudgetAllocationDetailsViewController: UIViewController {

    // MARK: - Properties

    private let mainView = BudgetAllocationDetailsView()
    private let viewModel: BudgetAllocationDetailsViewModel
    weak var flowDelegate: BudgetAllocationDetailsFlowDelegate?
    private var pendingDeleteCompletion: ((Bool) -> Void)?

    // MARK: - Initialization

    /// Initialize with an existing allocation (allocated mode)
    init(allocation: BudgetAllocation) {
        self.viewModel = BudgetAllocationDetailsViewModel(allocation: allocation)
        super.init(nibName: nil, bundle: nil)
    }

    /// Initialize with unallocated spending (unallocated mode)
    init(unallocatedSpending: UnallocatedCategorySpending) {
        self.viewModel = BudgetAllocationDetailsViewModel(unallocatedSpending: unallocatedSpending)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Returns true if showing unallocated spending details
    var isUnallocatedMode: Bool {
        viewModel.isUnallocatedMode
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = mainView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        mainView.delegate = self
        mainView.configure(with: viewModel)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh data when returning from transaction details (in case transaction was edited/deleted)
        viewModel.refreshAllocation()
        mainView.configure(with: viewModel)
    }

    // MARK: - Public Methods

    func refreshAfterEdit() {
        viewModel.refreshAllocation()
        mainView.configure(with: viewModel)
    }
}

// MARK: - BudgetAllocationDetailsViewDelegate

extension BudgetAllocationDetailsViewController: BudgetAllocationDetailsViewDelegate {

    func didTapEdit() {
        guard let allocation = viewModel.allocation else { return }
        flowDelegate?.editAllocation(allocation)
    }

    func didTapDelete() {
        if viewModel.isRecurring {
            showRecurringDeleteOptions()
        } else {
            showDeleteConfirmation()
        }
    }

    func didTapCreateAllocation() {
        flowDelegate?.createAllocation(
            forCategory: viewModel.category,
            monthAnchor: viewModel.monthDate
        )
    }

    func didTapBack() {
        flowDelegate?.dismissAllocationDetails()
    }

    func didTapTransaction(_ transaction: Transaction) {
        flowDelegate?.navigateToTransactionDetails(transaction: transaction)
    }

    func didRequestDeleteTransaction(_ transaction: Transaction, completion: @escaping (Bool) -> Void) {
        pendingDeleteCompletion = completion
        let transactionType = viewModel.getTransactionType(for: transaction)

        if transactionType == .simple {
            // Handle simple transactions with basic confirmation
            showTransactionDeleteConfirmation(transaction: transaction)
        } else {
            // Handle complex transactions with user choice (current/future/all)
            showTransactionDeletionOptions(transaction: transaction, transactionType: transactionType)
        }
    }

    // MARK: - Transaction Delete Helpers

    private func showTransactionDeleteConfirmation(transaction: Transaction) {
        let alert = UIAlertController(
            title: "transactionDetails.delete.title".localized,
            message: "transactionDetails.delete.message".localized,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(
            title: "alert.cancel".localized,
            style: .cancel
        ) { [weak self] _ in
            self?.pendingDeleteCompletion?(false)
            self?.pendingDeleteCompletion = nil
        })

        alert.addAction(UIAlertAction(
            title: "alert.delete".localized,
            style: .destructive
        ) { [weak self] _ in
            self?.performTransactionDelete(transaction: transaction)
        })

        present(alert, animated: true)
    }

    private func showTransactionDeletionOptions(
        transaction: Transaction,
        transactionType: TransactionComplexityType
    ) {
        let content = getTransactionDeletionPromptContent(for: transactionType)

        let alertController = UIAlertController(
            title: content.title,
            message: content.message,
            preferredStyle: .alert
        )

        let deleteCurrentAction = UIAlertAction(
            title: content.currentTitle,
            style: .default
        ) { [weak self] _ in
            self?.performTransactionDeletionWithOption(
                transaction: transaction,
                option: .currentSelection
            )
        }

        let deleteFutureAction = UIAlertAction(
            title: content.futureTitle,
            style: .default
        ) { [weak self] _ in
            self?.performTransactionDeletionWithOption(
                transaction: transaction,
                option: .futureOnly
            )
        }

        let cancelAction = UIAlertAction(
            title: "alert.cancel".localized,
            style: .cancel
        ) { [weak self] _ in
            self?.pendingDeleteCompletion?(false)
            self?.pendingDeleteCompletion = nil
        }

        let deleteAllAction = UIAlertAction(
            title: content.allTitle,
            style: .destructive
        ) { [weak self] _ in
            self?.performTransactionDeletionWithOption(
                transaction: transaction,
                option: .all
            )
        }

        alertController.addAction(deleteCurrentAction)
        alertController.addAction(deleteFutureAction)
        alertController.addAction(deleteAllAction)
        alertController.addAction(cancelAction)

        present(alertController, animated: true)
    }

    private func performTransactionDelete(transaction: Transaction) {
        viewModel.deleteTransactionAsync(transaction) { [weak self] result in
            self?.finishDelete(result)
        }
    }

    /// Reports the outcome and refreshes, once the write has actually landed.
    private func finishDelete(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            pendingDeleteCompletion?(true)
            pendingDeleteCompletion = nil
            mainView.refreshTransactions(with: viewModel)
            flowDelegate?.didUpdateAllocation()
        case .failure(let error):
            pendingDeleteCompletion?(false)
            pendingDeleteCompletion = nil
            showErrorAlert(error)
        }
    }

    private func performTransactionDeletionWithOption(
        transaction: Transaction,
        option: RecurringCleanupOption
    ) {
        guard let transactionId = transaction.id else {
            pendingDeleteCompletion?(false)
            pendingDeleteCompletion = nil
            showErrorAlert(NSError(
                domain: "BudgetAllocationDetails",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid transaction ID"]
            ))
            return
        }

        viewModel.deleteTransactionWithOptionAsync(
            transactionId: transactionId,
            option: option
        ) { [weak self] result in
            self?.finishDelete(result)
        }
    }

    private func getTransactionDeletionPromptContent(
        for transactionType: TransactionComplexityType
    ) -> TransactionDeletionPromptContent {
        switch transactionType {
        case .recurringParent, .recurringInstance:
            return TransactionDeletionPromptContent(
                title: "recurring.delete.title".localized,
                message: "recurring.delete.message".localized,
                currentTitle: "recurring.delete.current".localized,
                futureTitle: "recurring.delete.future".localized,
                allTitle: "recurring.delete.all".localized
            )
        case .installmentParent, .installmentInstance:
            return TransactionDeletionPromptContent(
                title: "installment.delete.title".localized,
                message: "installment.delete.message".localized,
                currentTitle: "installment.delete.current".localized,
                futureTitle: "installment.delete.remaining".localized,
                allTitle: "installment.delete.all".localized
            )
        case .simple:
            return TransactionDeletionPromptContent(
                title: "transaction.delete.title".localized,
                message: "delete.confirmation".localized,
                currentTitle: "alert.delete".localized,
                futureTitle: "alert.delete".localized,
                allTitle: "alert.delete".localized
            )
        }
    }

    // MARK: - Allocation Delete Helpers

    private func showDeleteConfirmation() {
        let alert = UIAlertController(
            title: "allocation.delete.title".localized,
            message: String(
                format: "allocation.delete.message".localized,
                viewModel.category.displayName
            ),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(
            title: "alert.cancel".localized,
            style: .cancel
        ))

        alert.addAction(UIAlertAction(
            title: "allocation.details.action.delete".localized,
            style: .destructive
        ) { [weak self] _ in
            self?.performDelete()
        })

        present(alert, animated: true)
    }

    private func showRecurringDeleteOptions() {
        let alert = UIAlertController(
            title: "allocation.delete.recurring.title".localized,
            message: "allocation.delete.recurring.message".localized,
            preferredStyle: .alert
        )

        // Delete only this month
        alert.addAction(UIAlertAction(
            title: "allocation.delete.recurring.current".localized,
            style: .default
        ) { [weak self] _ in
            self?.performRecurringDelete(option: .currentOnly)
        })

        // Delete this and all future months
        alert.addAction(UIAlertAction(
            title: "allocation.delete.recurring.future".localized,
            style: .default
        ) { [weak self] _ in
            self?.performRecurringDelete(option: .futureOnly)
        })

        // Delete all occurrences (past, present, and future)
        alert.addAction(UIAlertAction(
            title: "allocation.delete.recurring.all".localized,
            style: .destructive
        ) { [weak self] _ in
            self?.performRecurringDelete(option: .all)
        })

        alert.addAction(UIAlertAction(
            title: "alert.cancel".localized,
            style: .cancel
        ))

        present(alert, animated: true)
    }

    private func performDelete() {
        let result = viewModel.deleteAllocation()

        switch result {
        case .success:
            flowDelegate?.didDeleteAllocation()
        case .failure(let error):
            showErrorAlert(error)
        }
    }

    private func performRecurringDelete(option: AllocationDeleteOption) {
        logDebug("BudgetAllocationDetailsVC: Deleting allocation with option: \(option), dbId: \(String(describing: viewModel.allocation?.dbId))")
        let result = viewModel.deleteRecurringAllocation(option: option)

        switch result {
        case .success:
            logDebug("BudgetAllocationDetailsVC: Allocation deleted successfully, calling flowDelegate")
            flowDelegate?.didDeleteAllocation()
        case .failure(let error):
            logError("BudgetAllocationDetailsVC: Failed to delete allocation: \(error)")
            showErrorAlert(error)
        }
    }

    private func showErrorAlert(_ error: Error) {
        let alert = UIAlertController(
            title: "error.title".localized,
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Helper Types

private struct TransactionDeletionPromptContent {
    let title: String
    let message: String
    let currentTitle: String
    let futureTitle: String
    let allTitle: String
}
