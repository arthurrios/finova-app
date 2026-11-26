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

  func didTapMoveToStatement() {
    // Already leaves out the option that lands on the current statement.
    let monthOptions = viewModel.getMonthOptionsForMove()

    guard !monthOptions.isEmpty else { return }

    let alert = UIAlertController(
      title: "transactionDetails.moveToStatement.title".localized,
      message: "transactionDetails.moveToStatement.message".localized,
      preferredStyle: .actionSheet
    )

    for option in monthOptions {
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

  func didTapCancelPurchase() {
    let count = viewModel.getRefundableInstallmentCount()
    let amount = viewModel.getCancellationRefundAmount()

    // The message states the net effect explicitly. "You get R$ X back" on its own would read as a
    // windfall, when in fact the remaining installments keep being charged and the two offset.
    showConfirmation(
      title: "cancellation.confirm.title".localized,
      message: String(
        format: count == 1
          ? "cancellation.confirm.message.singular".localized
          : "cancellation.confirm.message.plural".localized,
        count, amount.currencyString),
      okTitle: "cancellation.confirm.action".localized
    ) { [weak self] in
      guard let self = self else { return }
      switch self.viewModel.cancelPurchase() {
      case .success(let refundId):
        self.flowDelegate?.didCancelInstallmentPurchase(refundId: refundId)
      case .failure(let error):
        self.showErrorAlert(message: "cancellation.error.generic".localized)
        logError("Cancelling installment purchase failed: \(error)")
      }
    }
  }

  func didTapUndoCancellation() {
    showConfirmation(
      title: "cancellation.undo.title".localized,
      message: "cancellation.undo.message".localized,
      okTitle: "cancellation.undo.action".localized
    ) { [weak self] in
      guard let self = self else { return }
      switch self.viewModel.undoCancellation() {
      case .success:
        // The credit is gone, so this screen has nothing left to show.
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

// MARK: - Foreign-currency income

extension TransactionDetailsViewController {
  /// "Enter amount received": only after the lock. Saves the typed R$ as `amount`, keeps the foreign
  /// amount and stores the implied rate, so the badge then includes spread, IOF and fees.
  func didTapEnterAmountReceived() {
    guard let id = viewModel.transaction.id, let fx = viewModel.transaction.foreign, fx.isLocked
    else { return }
    let app = AppConfig.currencyCode
    let alert = UIAlertController(
      title: "fx.received.title".localized,
      message: "fx.received.message".localized(
        ForeignCurrencyService.format(amountMinor: fx.amount, currency: fx.currency)),
      preferredStyle: .alert)
    alert.addTextField { field in
      field.keyboardType = .decimalPad
      field.placeholder = self.viewModel.transaction.amount.currencyString
    }
    alert.addAction(UIAlertAction(title: "fx.cancel".localized, style: .cancel))
    alert.addAction(UIAlertAction(title: "fx.received.save".localized, style: .default) { [weak self] _ in
      guard let self = self else { return }
      let text = alert.textFields?.first?.text ?? ""
      guard let typed = Self.minorUnits(from: text, currency: app),
        let result = FxEditPlanner.received(old: fx, typedAmount: typed, appCurrency: app)
      else { return }
      ForeignCurrencyService.shared.save(result, transactionId: id)
      self.refreshTransactionData()
    })
    present(alert, animated: true)
  }

  /// "28.900,00" / "28900" / "28,900.00" → minor units of `currency`.
  static func minorUnits(from text: String, currency: String) -> Int? {
    let digits = CurrencyUtils.fractionDigits(for: currency)
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = .autoupdatingCurrent
    let cleaned = text.trimmingCharacters(in: .whitespaces)
    guard let number = formatter.number(from: cleaned)
      ?? Decimal(string: cleaned.replacingOccurrences(of: ",", with: ".")).map({ NSDecimalNumber(decimal: $0) })
    else { return nil }
    let value = number.decimalValue * pow(10, digits)
    let minor = FxMath.roundHalfEven(value)
    return minor > 0 ? minor : nil
  }
}
