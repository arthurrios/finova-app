//
//  StatementDetailsViewController.swift
//  Finova
//

import UIKit

final class StatementDetailsViewController: UIViewController {
    let contentView: StatementDetailsView
    private let viewModel: StatementDetailsViewModel
    weak var flowDelegate: StatementDetailsFlowDelegate?
    private var pendingDeleteCompletion: ((Bool) -> Void)?

    init(contentView: StatementDetailsView, viewModel: StatementDetailsViewModel, flowDelegate: StatementDetailsFlowDelegate) {
        self.contentView = contentView
        self.viewModel = viewModel
        self.flowDelegate = flowDelegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        viewModel.loadTransactions()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        viewModel.loadTransactions()
    }

    private func setup() {
        view.addSubview(contentView)
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
        contentView.delegate = self
        viewModel.delegate = self
    }
}

extension StatementDetailsViewController: StatementDetailsViewDelegate {
    func didTapBack() {
        flowDelegate?.dismissStatementDetails()
    }

    func didTapMarkAsPaid() {
        let alert = UIAlertController(
            title: "statementDetails.button.markAsPaid".localized,
            message: nil,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default) { [weak self] _ in
            self?.viewModel.markAsPaid()
        })
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))

        present(alert, animated: true)
    }

    func didTapTransaction(_ transaction: Transaction) {
        flowDelegate?.navigateToTransactionDetails(transaction: transaction)
    }

    func didRequestDeleteTransaction(_ transaction: Transaction, completion: @escaping (Bool) -> Void) {
        pendingDeleteCompletion = completion
        let transactionType = viewModel.getTransactionType(for: transaction)

        if transactionType == .simple {
            showTransactionDeleteConfirmation(transaction: transaction)
        } else {
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

        alertController.addAction(UIAlertAction(
            title: content.currentTitle,
            style: .default
        ) { [weak self] _ in
            self?.performTransactionDeletionWithOption(
                transaction: transaction, option: .currentSelection)
        })

        alertController.addAction(UIAlertAction(
            title: content.futureTitle,
            style: .default
        ) { [weak self] _ in
            self?.performTransactionDeletionWithOption(
                transaction: transaction, option: .futureOnly)
        })

        alertController.addAction(UIAlertAction(
            title: content.allTitle,
            style: .destructive
        ) { [weak self] _ in
            self?.performTransactionDeletionWithOption(
                transaction: transaction, option: .all)
        })

        alertController.addAction(UIAlertAction(
            title: "alert.cancel".localized,
            style: .cancel
        ) { [weak self] _ in
            self?.pendingDeleteCompletion?(false)
            self?.pendingDeleteCompletion = nil
        })

        present(alertController, animated: true)
    }

    private func performTransactionDelete(transaction: Transaction) {
        // The swipe action's completion, the reload and the navigation all wait for the delete to
        // finish - previously the row animated away while the rows behind it were still being written.
        LoadingManager.shared.showLoading(on: self)
        viewModel.deleteTransactionAsync(transaction) { [weak self] result in
            guard let self else { return }
            LoadingManager.shared.hideLoading()

            switch result {
            case .success:
                self.pendingDeleteCompletion?(true)
                self.pendingDeleteCompletion = nil
                self.handleSuccessfulDeletion()
            case .failure:
                self.pendingDeleteCompletion?(false)
                self.pendingDeleteCompletion = nil
            }
        }
    }

    private func performTransactionDeletionWithOption(
        transaction: Transaction,
        option: RecurringCleanupOption
    ) {
        guard let transactionId = transaction.id else {
            pendingDeleteCompletion?(false)
            pendingDeleteCompletion = nil
            return
        }

        LoadingManager.shared.showLoading(on: self)
        viewModel.deleteTransactionWithOptionAsync(
            transactionId: transactionId, option: option
        ) { [weak self] result in
            guard let self else { return }
            LoadingManager.shared.hideLoading()

            switch result {
            case .success:
                self.pendingDeleteCompletion?(true)
                self.pendingDeleteCompletion = nil
                self.handleSuccessfulDeletion()
            case .failure:
                self.pendingDeleteCompletion?(false)
                self.pendingDeleteCompletion = nil
            }
        }
    }

    private func handleSuccessfulDeletion() {
        flowDelegate?.didDeleteTransactionInStatement()

        if viewModel.transactions.isEmpty {
            // No more transactions — statement will be empty, go back to dashboard
            flowDelegate?.dismissStatementDetails()
        } else {
            contentView.configure(with: viewModel)
        }
    }

    private func getTransactionDeletionPromptContent(
        for transactionType: TransactionComplexityType
    ) -> (title: String, message: String, currentTitle: String, futureTitle: String, allTitle: String) {
        switch transactionType {
        case .recurringParent, .recurringInstance:
            return (
                title: "recurring.delete.title".localized,
                message: "recurring.delete.message".localized,
                currentTitle: "recurring.delete.current".localized,
                futureTitle: "recurring.delete.future".localized,
                allTitle: "recurring.delete.all".localized
            )
        case .installmentParent, .installmentInstance:
            return (
                title: "installment.delete.title".localized,
                message: "installment.delete.message".localized,
                currentTitle: "installment.delete.current".localized,
                futureTitle: "installment.delete.remaining".localized,
                allTitle: "installment.delete.all".localized
            )
        case .simple:
            return (
                title: "transaction.delete.title".localized,
                message: "delete.confirmation".localized,
                currentTitle: "alert.delete".localized,
                futureTitle: "alert.delete".localized,
                allTitle: "alert.delete".localized
            )
        }
    }
}

extension StatementDetailsViewController: StatementDetailsViewModelDelegate {
    func didLoadTransactions(_ transactions: [Transaction]) {
        contentView.configure(with: viewModel)
    }

    func didMarkStatementPaid() {
        contentView.configure(with: viewModel)
        flowDelegate?.didMarkStatementAsPaid()
    }
}
