//
//  TransactionDetailsViewController.swift
//  Finova
//
//  Created by Arthur Rios on 05/09/25.
//

import Foundation
import UIKit

final class TransactionDetailsViewController: UIViewController {
  let contentView: TransactionDetailsView
  let viewModel: TransactionDetailsViewModel
  weak var flowDelegate: TransactionDetailsFlowDelegate?

  init(
    contentView: TransactionDetailsView,
    viewModel: TransactionDetailsViewModel,
    flowDelegate: TransactionDetailsFlowDelegate
  ) {
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
  }

  func refreshTransactionData() {
    // Reload the transaction data from the repository
    viewModel.refreshTransaction()

    // For installment transactions, also refresh related installments data
    if viewModel.transaction.mode == .installments {
      viewModel.refreshRelatedInstallments()
    }

    contentView.configure(with: viewModel)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(true, animated: false)
  }

  private func setup() {
    view.addSubview(contentView)
    buildHierarchy()
    setupDelegates()
    contentView.configure(with: viewModel)
  }

  private func buildHierarchy() {
    setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
  }

  private func setupDelegates() {
    contentView.delegate = self
  }
}

// MARK: - TransactionDetailsViewDelegate
extension TransactionDetailsViewController: TransactionDetailsViewDelegate {
  func didTapEdit() {
    flowDelegate?.editTransaction(viewModel.transaction)
  }

  func didTapDelete() {
    let transactionType = viewModel.getTransactionType(for: viewModel.transaction)

    if transactionType == .simple {
      // Handle simple transactions with basic confirmation
      showConfirmation(
        title: "transactionDetails.delete.title".localized,
        message: "transactionDetails.delete.message".localized,
        okTitle: "alert.delete".localized,
        onOk: { [weak self] in
          self?.deleteTransaction()
        }
      )
    } else {
      // Handle complex transactions with user choice (current/future/all)
      showInstallmentDeletionOptions(
        transaction: viewModel.transaction, transactionType: transactionType)
    }
  }

  func didTapBack() {
    flowDelegate?.dismissTransactionDetails()
  }

  func didTapMoveToGroup() {
    if viewModel.isInGroup() {
      // Move to Personal — confirmation
      showConfirmation(
        title: "transactionDetails.moveToPersonal.title".localized,
        message: "transactionDetails.moveToPersonal.message".localized,
        okTitle: "alert.ok".localized
      ) { [weak self] in
        self?.viewModel.moveTransactionToPersonal()
        self?.contentView.configure(with: self!.viewModel)
        NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
      }
    } else {
      // Move to Group — show action sheet with available groups
      let groups = viewModel.getAvailableGroups()
      guard !groups.isEmpty else { return }

      let alert = UIAlertController(
        title: "transactionDetails.moveToGroup.title".localized,
        message: "transactionDetails.moveToGroup.message".localized,
        preferredStyle: .actionSheet
      )

      for group in groups {
        alert.addAction(UIAlertAction(title: group.name, style: .default) { [weak self] _ in
          self?.viewModel.moveTransactionToGroup(group.id)
          self?.contentView.configure(with: self!.viewModel)
          NotificationCenter.default.post(name: .budgetGroupDataChanged, object: nil)
        })
      }

      alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
      present(alert, animated: true)
    }
  }

  func didTapMoveToStatement() {
    let monthOptions = viewModel.getMonthOptionsForMove()
    let currentStatement = viewModel.getCurrentStatement()

    guard !monthOptions.isEmpty else { return }

    let alert = UIAlertController(
      title: "transactionDetails.moveToStatement.title".localized,
      message: "transactionDetails.moveToStatement.message".localized,
      preferredStyle: .actionSheet
    )

    let calendar = Calendar.current
    for option in monthOptions {
      // Skip the month of the current statement (already there)
      if let currentClosing = currentStatement?.closingDate,
         calendar.isDate(option.firstOfMonth, equalTo: currentClosing, toGranularity: .month) {
        continue
      }

      alert.addAction(UIAlertAction(title: option.label, style: .default) { [weak self] _ in
        self?.viewModel.moveToStatementForMonth(option.firstOfMonth)
        self?.contentView.configure(with: self!.viewModel)
      })
    }

    alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
    present(alert, animated: true)
  }

  func didTapPayInstallmentsEarly() {
    flowDelegate?.payInstallmentsEarly(for: viewModel.transaction)
  }

  func didTapUndoEarlyPayment() {
    showConfirmation(
      title: "earlyPayment.undo.title".localized,
      message: "earlyPayment.undo.message".localized,
      okTitle: "earlyPayment.undo.action".localized
    ) { [weak self] in
      guard let self = self else { return }
      switch self.viewModel.undoEarlyPayment() {
      case .success:
        // The debit no longer exists, so this screen has nothing left to show.
        self.flowDelegate?.didDeleteTransaction()
      case .failure(let error):
        self.showErrorAlert(message: error.localizedDescription)
      }
    }
  }

  private func deleteTransaction() {
    contentView.startDeleteLoading()
    viewModel.deleteTransactionAsync { [weak self] result in
      self?.contentView.stopDeleteLoading()
      switch result {
      case .success:
        self?.flowDelegate?.didDeleteTransaction()
      case .failure(let error):
        self?.showErrorAlert(message: error.localizedDescription)
      }
    }
  }

  private func showErrorAlert(message: String) {
    showConfirmation(
      title: "alert.error".localized,
      message: message,
      okTitle: "alert.ok".localized,
      cancelTitle: "",
      onOk: {}
    )
  }

  private func showInstallmentDeletionOptions(
    transaction: Transaction, transactionType: TransactionComplexityType
  ) {
    let content = getDeletionPromptContent(for: transactionType)

    let alertController = UIAlertController(
      title: content.title,
      message: content.message,
      preferredStyle: .alert
    )

    let deleteCurrentAction = UIAlertAction(
      title: content.currentTitle,
      style: .default
    ) { [weak self] _ in
      self?.performInstallmentDeletion(transaction: transaction, cleanupOption: .currentSelection)
    }

    let deleteFutureAction = UIAlertAction(
      title: content.futureTitle,
      style: .default
    ) { [weak self] _ in
      self?.performInstallmentDeletion(transaction: transaction, cleanupOption: .futureOnly)
    }

    let cancelAction = UIAlertAction(
      title: "alert.cancel".localized,
      style: .cancel
    )

    let deleteAllAction = UIAlertAction(
      title: content.allTitle,
      style: .destructive
    ) { [weak self] _ in
      self?.performInstallmentDeletion(transaction: transaction, cleanupOption: .all)
    }

    alertController.addAction(deleteCurrentAction)
    alertController.addAction(deleteFutureAction)
    alertController.addAction(deleteAllAction)
    alertController.addAction(cancelAction)

    present(alertController, animated: true)
  }

  private func performInstallmentDeletion(
    transaction: Transaction, cleanupOption: RecurringCleanupOption
  ) {
    guard let transactionId = transaction.id else {
      showErrorAlert(message: "Invalid transaction ID")
      return
    }

    contentView.startDeleteLoading()
    viewModel.deleteTransactionWithOptionAsync(
      transactionId: transactionId, option: cleanupOption
    ) { [weak self] result in
      self?.contentView.stopDeleteLoading()
      switch result {
      case .success:
        self?.flowDelegate?.didDeleteTransaction()
      case .failure(let error):
        self?.showErrorAlert(message: error.localizedDescription)
      }
    }
  }

  private func getDeletionPromptContent(for transactionType: TransactionComplexityType)
    -> DeletionPromptContent
  {
    switch transactionType {
    case .recurringParent, .recurringInstance:
      return DeletionPromptContent(
        title: "recurring.delete.title".localized,
        message: "recurring.delete.message".localized,
        currentTitle: "recurring.delete.current".localized,
        futureTitle: "recurring.delete.future".localized,
        allTitle: "recurring.delete.all".localized  // Enable "All Occurrences" option
      )
    case .installmentParent, .installmentInstance:
      return DeletionPromptContent(
        title: "installment.delete.title".localized,
        message: "installment.delete.message".localized,
        currentTitle: "installment.delete.current".localized,
        futureTitle: "installment.delete.remaining".localized,
        allTitle: "installment.delete.all".localized
      )
    case .simple:
      return DeletionPromptContent(
        title: "transaction.delete.title".localized,
        message: "delete.confirmation".localized,
        currentTitle: "alert.delete".localized,
        futureTitle: "alert.delete".localized,
        allTitle: "alert.delete".localized
      )
    }
  }
}

private struct DeletionPromptContent {
  let title: String
  let message: String
  let currentTitle: String
  let futureTitle: String
  let allTitle: String?  // Optional - not all transaction types have "delete all" option
}
