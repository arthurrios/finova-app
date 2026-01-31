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

  // Height constraint for dynamic modal sizing
  private var heightConstraint: NSLayoutConstraint?

  // Track if we're in edit mode for keyboard handling
  private var isEditMode = false

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
    // Adjust height for edit mode (smaller modal)
    viewController.adjustHeightForEditMode()
    return viewController
  }

  // MARK: - Height Adjustment
  private func adjustHeightForEditMode() {
    // Update height constraint for edit mode (smaller modal)
    heightConstraint?.isActive = false
    heightConstraint = contentView.heightAnchor.constraint(
      equalTo: view.heightAnchor, multiplier: 0.42)  // Reduced from 0.56 to 0.42
    heightConstraint?.priority = UILayoutPriority(999)
    heightConstraint?.isActive = true

    // Update minimum height for edit mode
    contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
  }

  private func configureForEdit(with transaction: Transaction) {
    isEditMode = true
    contentView.configureForEdit(with: transaction)

    // For installment transactions, set the total amount instead of individual amount
    if transaction.mode == .installments {
      // Calculate total amount from all related installments
      let allTransactions = SecureLocalDataManager.shared.loadTransactions()
      let installmentGroupId = transaction.parentTransactionId ?? transaction.id
      let relatedTransactions = allTransactions.filter { t in
        t.id == installmentGroupId || t.parentTransactionId == installmentGroupId
      }

      if !relatedTransactions.isEmpty {
        let totalAmount = relatedTransactions.reduce(0) { $0 + $1.amount }
        contentView.setTotalAmountForInstallment(totalAmount)
        print(
          "🔍 INSTALLMENT EDIT: Calculated total amount \(totalAmount) from \(relatedTransactions.count) installments"
        )
      }
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    // 🔒 Authenticate SecureLocalDataManager for UID-isolated data access
    if let user = UserDefaultsManager.getUser(), let firebaseUID = user.firebaseUID {
      SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)
      print("🔒 AddTransactionModal: SecureLocalDataManager authenticated for user: \(firebaseUID)")
    }

    contentView.delegate = self
    contentView.incomeSelectorButton.delegate = self
    contentView.expenseSelectorButton.delegate = self

    setupView()
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
    print("🔍 KEYBOARD: viewDidLayoutSubviews - contentView frame: \(contentView.frame)")
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

    // Use a priority-based approach for flexible height
    heightConstraint = contentView.heightAnchor.constraint(
      equalTo: view.heightAnchor, multiplier: 0.56)
    heightConstraint?.priority = UILayoutPriority(999)
    heightConstraint?.isActive = true

    // Add a minimum height constraint to ensure content is always visible
    contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true

    // Add a maximum height constraint to prevent oversizing
    contentView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.75)
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
    let result = viewModel.addTransactionWithInstallments(data)
    handleTransactionResult(result)
  }

  func handleError(title: String, message: String) {
    let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
    let retryAction = UIAlertAction(title: "alert.ok".localized, style: .default)
    alertController.addAction(retryAction)
    self.present(alertController, animated: true)
  }

  func sendTransactionData(_ data: AddTransactionData) {
    let result = viewModel.addTransaction(
      title: data.title,
      amount: data.amount,
      dateString: data.date,
      categoryKey: data.category,
      typeRaw: data.transactionType)

    handleTransactionResult(result)
  }

  func sendRecurringTransactionData(_ data: AddTransactionData) {
    let result = viewModel.addTransaction(
      title: data.title,
      amount: data.amount,
      dateString: data.date,
      categoryKey: data.category,
      typeRaw: data.transactionType,
      isRecurring: true
    )

    handleTransactionResult(result)
  }

  func updateTransactionData(id: Int, _ data: AddTransactionData) {
    let result = viewModel.updateTransaction(
      id: id,
      title: data.title,
      amount: data.amount,
      dateString: data.date,
      categoryKey: data.category,
      typeRaw: data.transactionType
    )
    handleUpdateResult(result)
  }

  func updateRecurringTransactionData(id: Int, _ data: AddTransactionData) {
    let result = viewModel.updateTransaction(
      id: id,
      title: data.title,
      amount: data.amount,
      dateString: data.date,
      categoryKey: data.category,
      typeRaw: data.transactionType
    )
    handleUpdateResult(result)
  }

  func updateInstallmentTransactionData(id: Int, _ data: InstallmentTransactionData) {
    let result = viewModel.updateTransactionWithInstallments(id: id, data)
    handleUpdateResult(result)
  }

  func updateSingleRecurringTransactionData(id: Int, _ data: AddTransactionData) {
    let result = viewModel.updateSingleTransaction(
      id: id,
      title: data.title,
      amount: data.amount,
      dateString: data.date,
      categoryKey: data.category,
      typeRaw: data.transactionType
    )
    handleUpdateResult(result)
  }

  func updateSingleInstallmentTransactionData(id: Int, _ data: InstallmentTransactionData) {
    let result = viewModel.updateSingleTransactionWithInstallments(id: id, data)
    handleUpdateResult(result)
  }

  func updateRecurringTransactionDataWithOption(
    id: Int, _ data: AddTransactionData, editOption: RecurringEditOption
  ) {
    // Dismiss modal immediately for better UX (optimistic update)
    dismissModal()

    // Run editing in background
    viewModel.updateRecurringTransactionWithOptionAsync(
      id: id,
      title: data.title,
      amount: data.amount,
      dateString: data.date,
      categoryKey: data.category,
      typeRaw: data.transactionType,
      editOption: editOption
    ) { [weak self] result in
      switch result {
      case .success:
        // Notify delegate to refresh data
        self?.flowDelegate?.didUpdateTransaction()
      case .failure(let error):
        // Show error alert even after modal is dismissed
        print("❌ Error updating recurring transaction: \(error)")
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
  }

  func closeModal() {
    dismissModal()
  }

  // MARK: - Custom Keyboard Handling
  private func startCustomKeyboardObservers() {
    print("🔍 KEYBOARD: Setting up keyboard observers, isEditMode: \(isEditMode)")
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
    print("🔍 KEYBOARD: modalKeyboardWillShow called, isEditMode: \(isEditMode)")

    guard
      let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
        as? CGRect,
      let animationDuration = notification.userInfo?[
        UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
    else {
      print("🔍 KEYBOARD: Failed to get keyboard frame or animation duration")
      return
    }

    // Calculate the available space above the keyboard
    let keyboardHeight = keyboardFrame.height
    let viewHeight = view.frame.height
    let keyboardTopY = viewHeight - keyboardHeight

    // Get the modal's current position and height
    let modalHeight = contentView.frame.height
    let modalTopY = contentView.frame.minY
    let modalBottomY = contentView.frame.maxY

    print("🔍 KEYBOARD: keyboardHeight: \(keyboardHeight), viewHeight: \(viewHeight)")
    print(
      "🔍 KEYBOARD: keyboardTopY: \(keyboardTopY), modalTopY: \(modalTopY), modalBottomY: \(modalBottomY)"
    )

    // Check if the modal is being covered by the keyboard
    if modalBottomY > keyboardTopY {
      // Modal is being covered - calculate how much to shift up
      let overlap = modalBottomY - keyboardTopY
      // Shift by more of the overlap to ensure keyboard clearance
      let shiftAmount = min(overlap * 0.7, 200)  // Max 200px shift, or 70% of overlap

      print("🔍 KEYBOARD: Modal is covered by keyboard, shifting up by: \(shiftAmount)")

      UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseInOut]) {
        self.contentView.transform = CGAffineTransform(translationX: 0, y: -shiftAmount)
      }
    } else {
      print("🔍 KEYBOARD: Modal is not covered by keyboard")
    }
  }

  @objc private func modalKeyboardWillHide(notification: Notification) {
    guard
      let animationDuration = notification.userInfo?[
        UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
    else { return }

    UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseInOut]) {
      self.contentView.transform = .identity
    }
  }
}
