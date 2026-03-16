//
//  AddTransactionViewController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/05/25.
//

import Foundation
import UIKit

final class AddTransactionModalViewController: UIViewController {
  let viewModel: AddTransactionModalViewModel
  let contentView: AddTransactionModalView
  weak var flowDelegate: AddTransactionModalFlowDelegate?

  // Track if we're in edit mode for keyboard handling
  private var isEditMode = false

  // Used to cancel the hide-reset when the user switches directly between fields
  private var keyboardHideWorkItem: DispatchWorkItem?

  init(
    contentView: AddTransactionModalView, flowDelegate: AddTransactionModalFlowDelegate,
    viewModel: AddTransactionModalViewModel
  ) {
    self.contentView = contentView
    self.flowDelegate = flowDelegate
    self.viewModel = viewModel
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Edit Mode Factory
  static func forEdit(
    transaction: Transaction,
    flowDelegate: AddTransactionModalFlowDelegate
  ) -> AddTransactionModalViewController {
    let contentView = AddTransactionModalView()
    let viewModel = AddTransactionModalViewModel()
    let viewController = AddTransactionModalViewController(
      contentView: contentView,
      flowDelegate: flowDelegate,
      viewModel: viewModel
    )

    // Set edit mode with transaction data
    viewController.configureForEdit(with: transaction)
    return viewController
  }

  private func configureForEdit(with transaction: Transaction) {
    isEditMode = true
    contentView.configureForEdit(with: transaction)

    // For installment transactions, set the total amount instead of individual amount
    if transaction.mode == .installments {
      // Calculate total amount from all related installments
      let allTransactions = TransactionRepository().fetchAllTransactions()
      let installmentGroupId = transaction.parentTransactionId ?? transaction.id
      let relatedTransactions = allTransactions.filter { t in
        t.id == installmentGroupId || t.parentTransactionId == installmentGroupId
      }

      if !relatedTransactions.isEmpty {
        let totalAmount = relatedTransactions.reduce(0) { $0 + $1.amount }
        contentView.setTotalAmountForInstallment(totalAmount)
      }
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    contentView.delegate = self
    contentView.incomeSelectorButton.delegate = self
    contentView.expenseSelectorButton.delegate = self

    setupView()
    loadCreditCards()

    // Configure group context banner
    contentView.configureGroupContext(viewModel.activeContext)
  }

  private func loadCreditCards() {
    let cardRepo = CreditCardRepository()
    switch viewModel.activeContext {
    case .personal:
      guard let uid = AuthenticationManager.shared.currentUser?.uid else { return }
      let cards = cardRepo.fetchAllCards(userId: uid)
      contentView.loadAvailableCards(cards)
    case .group(let group):
      let cards = cardRepo.fetchCardsForGroup(groupId: group.id)
      contentView.loadAvailableCards(cards)
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    startCustomKeyboardObservers()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    stopKeyboardObservers()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
  }

  private func setupView() {
    let blurEffect = UIBlurEffect(style: .dark)
    let blurEffectView = UIVisualEffectView(effect: blurEffect)
    blurEffectView.frame = view.bounds
    blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    setupGesture(viewTapped: blurEffectView)

    view.addSubview(blurEffectView)
    view.addSubview(contentView)
    contentView.translatesAutoresizingMaskIntoConstraints = false

    setupConstraints()
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    // Modal auto-sizes to fit content (driven by self-sizing scroll view).
    // Only cap with a max height — scroll kicks in if content exceeds it.
    contentView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.85)
      .isActive = true
  }

  private func setupGesture(viewTapped: UIView) {
    let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissModal))
    viewTapped.addGestureRecognizer(tapGestureRecognizer)
  }

  @objc
  private func dismissModal() {
    dismiss(animated: true)
  }

  func animateShow() {
    view.layoutIfNeeded()
    contentView.transform = CGAffineTransform(translationX: 0, y: contentView.frame.height)
    UIView.animate(
      withDuration: 0.3,
      animations: {
        self.contentView.transform = .identity
        self.view.layoutIfNeeded()
      })
  }
}

extension AddTransactionModalViewController: AddTransactionModalViewDelegate,
  TransactionTypeSelectorDelegate
{

  func sendInstallmentTransactionData(_ data: InstallmentTransactionData) {
    // Show loading state
    contentView.saveButton.startLoading()

    // Use async version
    viewModel.addTransactionWithInstallmentsAsync(data) { [weak self] result in
      DispatchQueue.main.async {
        self?.contentView.saveButton.stopLoading()

        switch result {
        case .success:
          self?.dismissModal()
          self?.flowDelegate?.didAddTransaction()
        case .failure(let error):
          let message: String
          switch error {
          case TransactionError.invalidDateFormat:
            message = "alert.error.invalidDateFormat".localized
          case TransactionError.invalidCategory:
            message = "alert.error.invalidCategory".localized
          case TransactionError.invalidType:
            message = "alert.error.invalidTransactionType".localized
          case TransactionError.invalidInstallmentCount:
            message = "alert.error.invalidInstallmentCount".localized
          default:
            message = "alert.error.defaultMessage".localized
          }
          self?.handleError(title: "alert.error.title".localized, message: message)
        }
      }
    }
  }

  func handleError(title: String, message: String) {
    let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
    let retryAction = UIAlertAction(title: "alert.ok".localized, style: .default)
    alertController.addAction(retryAction)
    self.present(alertController, animated: true)
  }

  func sendTransactionData(_ data: AddTransactionData) {
    contentView.saveButton.startLoading()
    let result = viewModel.addTransaction(
      title: data.title,
      amount: data.amount,
      dateString: data.date,
      categoryKey: data.category,
      typeRaw: data.transactionType,
      creditCardId: data.creditCardId)
    contentView.saveButton.stopLoading()

    handleTransactionResult(result)
  }

  func sendRecurringTransactionData(_ data: AddTransactionData) {
    // Show loading state
    contentView.saveButton.startLoading()

    // Use async version that waits for instance generation
    viewModel.addRecurringTransactionAsync(
      title: data.title,
      amount: data.amount,
      dateString: data.date,
      categoryKey: data.category,
      typeRaw: data.transactionType,
      creditCardId: data.creditCardId
    ) { [weak self] result in
      DispatchQueue.main.async {
        self?.contentView.saveButton.stopLoading()

        switch result {
        case .success:
          self?.dismissModal()
          self?.flowDelegate?.didAddTransaction()
        case .failure(let error):
          let message: String
          switch error {
          case TransactionError.invalidDateFormat:
            message = "alert.error.invalidDateFormat".localized
          case TransactionError.invalidCategory:
            message = "alert.error.invalidCategory".localized
          case TransactionError.invalidType:
            message = "alert.error.invalidTransactionType".localized
          default:
            message = "alert.error.defaultMessage".localized
          }
          self?.handleError(title: "alert.error.title".localized, message: message)
        }
      }
    }
  }

  func updateTransactionData(id: Int, _ data: AddTransactionData) {
    contentView.saveButton.startLoading()
    let result = viewModel.updateTransaction(
      id: id,
      title: data.title,
      amount: data.amount,
      dateString: data.date,
      categoryKey: data.category,
      typeRaw: data.transactionType,
      creditCardId: data.creditCardId
    )
    contentView.saveButton.stopLoading()
    handleUpdateResult(result)
  }

  func updateRecurringTransactionData(id: Int, _ data: AddTransactionData) {
    contentView.saveButton.startLoading()
    let result = viewModel.updateTransaction(
      id: id,
      title: data.title,
      amount: data.amount,
      dateString: data.date,
      categoryKey: data.category,
      typeRaw: data.transactionType,
      creditCardId: data.creditCardId
    )
    contentView.saveButton.stopLoading()
    handleUpdateResult(result)
  }

  func updateInstallmentTransactionData(id: Int, _ data: InstallmentTransactionData) {
    contentView.saveButton.startLoading()
    let result = viewModel.updateTransactionWithInstallments(id: id, data)
    contentView.saveButton.stopLoading()
    handleUpdateResult(result)
  }

  func updateSingleRecurringTransactionData(id: Int, _ data: AddTransactionData) {
    contentView.saveButton.startLoading()
    let result = viewModel.updateSingleTransaction(
      id: id,
      title: data.title,
      amount: data.amount,
      dateString: data.date,
      categoryKey: data.category,
      typeRaw: data.transactionType,
      creditCardId: data.creditCardId
    )
    contentView.saveButton.stopLoading()
    handleUpdateResult(result)
  }

  func updateSingleInstallmentTransactionData(id: Int, _ data: InstallmentTransactionData) {
    contentView.saveButton.startLoading()
    let result = viewModel.updateSingleTransactionWithInstallments(id: id, data)
    contentView.saveButton.stopLoading()
    handleUpdateResult(result)
  }

  func updateRecurringTransactionDataWithOption(
    id: Int, _ data: AddTransactionData, editOption: RecurringEditOption
  ) {
    // Show loading state
    contentView.saveButton.startLoading()

    // Run editing in background
    viewModel.updateRecurringTransactionWithOptionAsync(
      id: id,
      title: data.title,
      amount: data.amount,
      dateString: data.date,
      categoryKey: data.category,
      typeRaw: data.transactionType,
      creditCardId: data.creditCardId,
      editOption: editOption
    ) { [weak self] result in
      DispatchQueue.main.async {
        self?.contentView.saveButton.stopLoading()

        switch result {
        case .success:
          self?.dismissModal()
          self?.flowDelegate?.didUpdateTransaction()
        case .failure(let error):
          // Show error alert, keep modal open for retry
          self?.handleError(
            title: "alert.error.title".localized,
            message: "alert.error.defaultMessage".localized
          )
        }
      }
    }
  }

  private func handleTransactionResult(_ result: Result<Void, Error>) {
    switch result {
    case .success:
      dismissModal()
      flowDelegate?.didAddTransaction()
    case .failure(let error):
      let message: String
      switch error {
      case TransactionError.invalidDateFormat:
        message = "alert.error.invalidDateFormat".localized
      case TransactionError.invalidCategory:
        message = "alert.error.invalidCategory".localized
      case TransactionError.invalidType:
        message = "alert.error.invalidTransactionType".localized
      case TransactionError.invalidInstallmentCount:
        message = "alert.error.invalidInstallmentCount".localized
      default:
        message = "alert.error.defaultMessage".localized
      }
      handleError(title: "alert.error.title".localized, message: message)
    }
  }

  private func handleUpdateResult(_ result: Result<Void, Error>) {
    switch result {
    case .success:
      dismissModal()
      flowDelegate?.didUpdateTransaction()  // Refresh both dashboard and transaction details
    case .failure(let error):
      let message: String
      switch error {
      case TransactionError.invalidDateFormat:
        message = "alert.error.invalidDateFormat".localized
      case TransactionError.invalidCategory:
        message = "alert.error.invalidCategory".localized
      case TransactionError.invalidType:
        message = "alert.error.invalidTransactionType".localized
      case TransactionError.invalidInstallmentCount:
        message = "alert.error.invalidInstallmentCount".localized
      default:
        message = "alert.error.defaultMessage".localized
      }
      handleError(title: "alert.error.title".localized, message: message)
    }
  }

  func transactionTypeSelectorDidSelect(_ selector: TransactionTypeSelector) {
    if selector.variant == .selected {
      contentView.incomeSelectorButton.variant = .normal
      contentView.expenseSelectorButton.variant = .normal
    } else {
      if selector.transactionType == .income {
        contentView.incomeSelectorButton.variant = .selected
        contentView.expenseSelectorButton.variant = .unselected
      } else {
        contentView.expenseSelectorButton.variant = .selected
        contentView.incomeSelectorButton.variant = .unselected
      }
    }

    // Show payment method section only for expenses
    let isExpense = contentView.expenseSelectorButton.variant == .selected
    contentView.showPaymentMethodSection(isExpense)
  }

  func didTapCreateCreditCard() {
    dismissModal()
    flowDelegate?.didTapCreateCreditCard()
  }

  func closeModal() {
    dismissModal()
  }

  // MARK: - Custom Keyboard Handling
  private func startCustomKeyboardObservers() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(modalKeyboardWillShow(notification:)),
      name: UIResponder.keyboardWillShowNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(modalKeyboardWillHide(notification:)),
      name: UIResponder.keyboardWillHideNotification,
      object: nil
    )
  }

  private func stopKeyboardObservers() {
    NotificationCenter.default.removeObserver(
      self, name: UIResponder.keyboardWillShowNotification, object: nil)
    NotificationCenter.default.removeObserver(
      self, name: UIResponder.keyboardWillHideNotification, object: nil)
  }

  @objc private func modalKeyboardWillShow(notification: Notification) {
    // If the user switched directly from one field to another, cancel the pending
    // hide-reset so the modal doesn't jump down then back up.
    keyboardHideWorkItem?.cancel()
    keyboardHideWorkItem = nil

    guard
      let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
        as? CGRect,
      let animationDuration = notification.userInfo?[
        UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
    else {
      return
    }

    // Convert keyboard frame to this view's coordinate space so the math is correct
    // even when the VC is presented as a sheet on iPad (not necessarily full-screen).
    let keyboardTopY = view.convert(keyboardFrame, from: nil).minY

    // Shift exactly enough so the active input clears the keyboard with 16pt padding.
    // Using the precise field position avoids under-shifting (which lets the keyboard
    // overlap the input and intercept touches) and over-shifting.
    let fieldOriginalBottom = activeInputOriginalBottomY()
    let targetY = keyboardTopY - 16

    if fieldOriginalBottom > targetY {
      let shiftAmount = fieldOriginalBottom - targetY
      UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseInOut]) {
        self.contentView.transform = CGAffineTransform(translationX: 0, y: -shiftAmount)
      }
    }
  }

  @objc private func modalKeyboardWillHide(notification: Notification) {
    guard
      let animationDuration = notification.userInfo?[
        UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
    else { return }

    // Delay the reset slightly. If another keyboardWillShow arrives within that window
    // (user switched fields), the work item is cancelled and the modal stays put.
    let workItem = DispatchWorkItem { [weak self] in
      UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseInOut]) {
        self?.contentView.transform = .identity
      }
    }
    keyboardHideWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
  }

  /// Returns the original (pre-transform) bottom Y of the currently focused input
  /// in the view controller's view coordinate space.
  private func activeInputOriginalBottomY() -> CGFloat {
    func findFirstResponder(in searchView: UIView) -> UIView? {
      if searchView.isFirstResponder { return searchView }
      for sub in searchView.subviews {
        if let found = findFirstResponder(in: sub) { return found }
      }
      return nil
    }

    guard let responder = findFirstResponder(in: contentView) else {
      // No active input — fall back to the modal's natural bottom edge.
      return view.bounds.height
    }

    // Convert the responder's frame into contentView-local coordinates.
    // This is unaffected by contentView's own transform, so it gives us
    // the original layout position.
    let frameInContentView = responder.convert(responder.bounds, to: contentView)

    // contentView is bottom-anchored to view, so its original top = view.height - contentView.height.
    let originalContentTopY = view.bounds.height - contentView.bounds.height
    return originalContentTopY + frameInContentView.maxY
  }
}
