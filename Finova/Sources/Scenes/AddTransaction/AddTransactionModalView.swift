//
//  AddTransactionView.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/05/25.
//

import Foundation
import UIKit

final class AddTransactionModalView: UIView {
  weak var delegate: AddTransactionModalViewDelegate?

  let categoryOptions = TransactionCategory.allCases.filter { $0 != .creditCard }

  // MARK: - Edit Mode Properties
  private var isEditMode = false
  private var editingTransaction: Transaction?

  enum EditMode {
    case add
    case edit(transaction: Transaction)

    var title: String {
      switch self {
      case .add:
        return "addTransactionModal.title".localized
      case .edit:
        return "editTransactionModal.title".localized
      }
    }

    var saveButtonTitle: String {
      switch self {
      case .add:
        return "addTransactionModal.button.save".localized
      case .edit:
        return "editTransactionModal.button.update".localized
      }
    }
  }

  private var currentEditMode: EditMode = .add

  // Track ongoing animation to prevent conflicts
  private var isAnimating = false
  private var pendingMode: TransactionMode?

  private var contentHeightConstraint: NSLayoutConstraint?

  private lazy var scrollView: UIScrollView = {
    let sv = UIScrollView()
    sv.showsVerticalScrollIndicator = false
    sv.translatesAutoresizingMaskIntoConstraints = false
    return sv
  }()

  private lazy var contentStackView: UIStackView = {
    let sv = UIStackView(
      axis: .vertical, spacing: Metrics.spacing7, distribution: .fill,
      arrangedSubviews: [
        headerStackView, inputStackView, paymentMethodSection,
        transactionButtonsStackView, separator, saveButton,
      ])
    sv.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: Metrics.spacing10, leading: Metrics.spacing8, bottom: Metrics.spacing4,
      trailing: Metrics.spacing8)
    sv.isLayoutMarginsRelativeArrangement = true

    // Bring payment method section closer to the value/date inputs
    sv.setCustomSpacing(Metrics.spacing3, after: inputStackView)

    sv.setContentHuggingPriority(UILayoutPriority(251), for: .vertical)
    sv.setContentCompressionResistancePriority(UILayoutPriority(751), for: .vertical)

    return sv
  }()

  // Simplified content stack for edit mode (no transaction type buttons or mode controls)
  private lazy var editModeContentStackView: UIStackView = {
    let sv = UIStackView(
      axis: .vertical, spacing: Metrics.spacing7, distribution: .fill,
      arrangedSubviews: [
        headerStackView, editModeInputStackView, separator, saveButton,
      ])
    sv.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: Metrics.spacing10, leading: Metrics.spacing8, bottom: Metrics.spacing4,
      trailing: Metrics.spacing8)
    sv.isLayoutMarginsRelativeArrangement = true

    sv.setContentHuggingPriority(UILayoutPriority(251), for: .vertical)
    sv.setContentCompressionResistancePriority(UILayoutPriority(751), for: .vertical)

    return sv
  }()

  private lazy var headerStackView = UIStackView(
    axis: .horizontal, alignment: .center, arrangedSubviews: [headerTitleLabel, closeIconButton])

  private lazy var moneyInputsContainer: UIStackView = {
    let stackView = UIStackView(
      axis: .vertical,
      spacing: Metrics.spacing2,
      arrangedSubviews: [horizontalInputsStackView, totalValueLabel]
    )
    return stackView
  }()

  private lazy var inputStackView = UIStackView(
    axis: .vertical, spacing: Metrics.spacing3,
    arrangedSubviews: [
      transactionTitleTextField, categoryPickerView, transactionModeStackView,
      moneyInputsContainer,
    ])

  // Simplified input stack for edit mode (only editable fields)
  private lazy var editModeInputStackView = UIStackView(
    axis: .vertical, spacing: Metrics.spacing3,
    arrangedSubviews: [
      transactionTitleTextField, categoryPickerView, horizontalInputsStackView,
    ])

  // Separate input fields for installment editing
  private lazy var totalValueTextField = Input(type: .currency, placeholder: "0,00")

  private lazy var initialDateTextField = Input(
    type: .date(style: .fullDate), placeholder: "00/00/0000", icon: UIImage(named: "calendar"))

  // Labels for installment-specific information in edit mode (styled like totalValueLabel)
  private lazy var initialDateLabel: UILabel = {
    let label = UILabel()
    label.text = "addTransactionModal.label.initialDate".localized
    label.font = Fonts.textSM.font
    label.textColor = Colors.gray400
    label.isHidden = true
    label.translatesAutoresizingMaskIntoConstraints = false

    label.setContentHuggingPriority(.required, for: .vertical)
    label.setContentCompressionResistancePriority(.required, for: .vertical)
    label.heightAnchor.constraint(equalToConstant: Metrics.spacing3).isActive = true

    return label
  }()

  // MARK: - Payment Method Section (Credit Card)
  private var selectedPaymentMethod: PaymentMethod = .cashDebit
  private var availableCards: [CreditCard] = []
  private var selectedCard: CreditCard?

  private lazy var paymentMethodSection: UIStackView = {
    let stack = UIStackView(
      axis: .vertical, spacing: Metrics.spacing3,
      arrangedSubviews: [paymentMethodTitleLabel, paymentOptionsStack, cardSelectorContainer, statementInfoBanner])
    stack.isHidden = true  // Only show for expenses
    return stack
  }()

  private let paymentMethodTitleLabel: UILabel = {
    let label = UILabel()
    label.text = "addTransactionModal.paymentMethod.title".localized
    label.font = Fonts.textSMBold.font
    label.textColor = Colors.gray600
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private lazy var paymentOptionsStack = UIStackView(
    axis: .horizontal, spacing: Metrics.spacing3, distribution: .fillEqually,
    arrangedSubviews: [cashDebitOption, creditCardOption])

  private lazy var cashDebitOption: PaymentMethodOptionView = {
    let view = PaymentMethodOptionView(
      title: "addTransactionModal.paymentMethod.cashDebit".localized,
      subtitle: "addTransactionModal.paymentMethod.cashDebit.subtitle".localized)
    view.setSelected(true)
    view.onTap = { [weak self] in self?.selectPaymentMethod(.cashDebit) }
    return view
  }()

  private lazy var creditCardOption: PaymentMethodOptionView = {
    let view = PaymentMethodOptionView(
      title: "addTransactionModal.paymentMethod.creditCard".localized,
      subtitle: "addTransactionModal.paymentMethod.creditCard.subtitle".localized)
    view.onTap = { [weak self] in self?.selectPaymentMethod(.creditCard(cardId: 0)) }
    return view
  }()

  private lazy var cardSelectorContainer: UIStackView = {
    let stack = UIStackView(axis: .vertical, spacing: Metrics.spacing2,
      arrangedSubviews: [cardPickerInput, createCardButton])
    stack.isHidden = true
    return stack
  }()

  private let cardPickerInput = Input(
    type: .picker(values: []),
    placeholder: "addTransactionModal.paymentMethod.selectCard".localized,
    icon: UIImage(named: "lucide_iconCreditCard"), iconPosition: .left)

  private lazy var createCardButton: Button = {
    let button = Button(variant: .outlined, label: "addTransactionModal.paymentMethod.createCard".localized)
    button.isHidden = true
    button.addTarget(self, action: #selector(didTapCreateCard), for: .touchUpInside)
    return button
  }()

  private let statementInfoBanner: UILabel = {
    let label = UILabel()
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray500
    label.numberOfLines = 0
    label.isHidden = true
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private lazy var transactionModeStackView = UIStackView(
    axis: .vertical,
    arrangedSubviews: [transactionModelControl, installmentsInputContainer])

  // Container for total value input with its label
  private lazy var totalValueInputContainer: UIStackView = {
    let stackView = UIStackView(
      axis: .vertical,
      spacing: Metrics.spacing2,
      arrangedSubviews: [totalValueTextField, totalValueLabel]
    )
    return stackView
  }()

  // Container for initial date input with its label
  private lazy var initialDateInputContainer: UIStackView = {
    let stackView = UIStackView(
      axis: .vertical,
      spacing: Metrics.spacing2,
      arrangedSubviews: [initialDateTextField, initialDateLabel]
    )
    return stackView
  }()

  // Horizontal stack view for the two input containers
  private lazy var installmentInputsContainer: UIStackView = {
    let stackView = UIStackView(
      axis: .horizontal,
      spacing: Metrics.spacing3,
      distribution: .fillEqually,
      arrangedSubviews: [totalValueInputContainer, initialDateInputContainer]
    )
    return stackView
  }()

  private lazy var horizontalInputsStackView = UIStackView(
    axis: .horizontal, spacing: Metrics.spacing3, distribution: .fillEqually,
    arrangedSubviews: [moneyTextField, dateTextField])

  private lazy var installmentsInputContainer: UIStackView = {
    let stackView = UIStackView(
      axis: .vertical, arrangedSubviews: [installmentsInputWithSuffix])
    stackView.alpha = 0

    stackView.setContentHuggingPriority(UILayoutPriority(250), for: .vertical)
    stackView.setContentCompressionResistancePriority(UILayoutPriority(750), for: .vertical)

    return stackView
  }()

  private var installmentsHeightConstraint: NSLayoutConstraint?

  private lazy var transactionButtonsStackView = UIStackView(
    axis: .horizontal, spacing: Metrics.spacing3, distribution: .fillEqually,
    arrangedSubviews: [incomeSelectorButton, expenseSelectorButton])

  private let headerTitleLabel: UILabel = {
    let label = UILabel()
    label.fontStyle = Fonts.titleXS
    label.textColor = Colors.gray700
    label.text = "addTransactionModal.header.title".localized
    label.applyStyle()
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let closeIconButton: UIButton = {
    let button = UIButton(type: .custom)
    button.setImage(UIImage(named: "x"), for: .normal)
    button.tintColor = Colors.gray500
    button.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: 20),
      button.heightAnchor.constraint(equalToConstant: 20),
    ])
    button.accessibilityLabel = "addTransactionModal.button.close".localized

    return button
  }()

  private let transactionTitleTextField = Input(
    placeholder: "addTransactionModal.input.transactionTitle".localized)
  let categoryPickerView = Input(
    type: .picker(values: TransactionCategory.allCases.filter { $0 != .creditCard }.map { $0.key }),
    placeholder: "addTransactionModal.input.category".localized, icon: UIImage(named: "tag"),
    iconPosition: .left)

  private let transactionModelControl = InputSegmentedControl()

  private let installmentsTextField = Input(
    type: .number, placeholder: "installments.placeholder".localized)

  // Custom installments input with suffix inside the field
  private lazy var installmentsInputWithSuffix: Input = {
    let input = Input(type: .number, placeholder: "")

    // Add suffix text to the input field
    let suffixText = " " + "addTransactionModal.label.installments".localized
    input.textField.rightViewMode = .always

    let suffixLabel = UILabel()
    suffixLabel.text = suffixText
    suffixLabel.font = Fonts.textSM.font
    suffixLabel.textColor = Colors.gray400
    suffixLabel.sizeToFit()

    input.textField.rightView = suffixLabel

    return input
  }()

  private let moneyTextField = Input(type: .currency, placeholder: "0,00")

  private let totalValueLabel: UILabel = {
    let label = UILabel()
    label.text = "addTransactionModal.totalValue".localized
    label.font = Fonts.textSM.font
    label.textColor = Colors.gray400
    label.isHidden = true
    label.translatesAutoresizingMaskIntoConstraints = false

    label.setContentHuggingPriority(.required, for: .vertical)
    label.setContentCompressionResistancePriority(.required, for: .vertical)
    label.heightAnchor.constraint(equalToConstant: Metrics.spacing3).isActive = true

    return label
  }()

  private let dateTextField = Input(
    type: .date(style: .fullDate), placeholder: "00/00/0000", icon: UIImage(named: "calendar"))

  var incomeSelectorButton = TransactionTypeSelector()

  var expenseSelectorButton = TransactionTypeSelector(transactionType: .expense)

  let separator: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray300
    view.heightAnchor.constraint(equalToConstant: 1).isActive = true
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  let saveButton = Button(label: "addTransactionModal.button.save".localized)

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupViews()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupViews() {
    backgroundColor = Colors.gray100
    layer.cornerRadius = CornerRadius.bottomSheet

    // Add the default content stack view (for add mode) inside scroll view
    addSubview(scrollView)
    scrollView.addSubview(contentStackView)
    closeIconButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)

    saveButton.addTarget(self, action: #selector(didTapSaveTransaction), for: .touchUpInside)

    // Add Done button toolbar to inputs that need it
    transactionTitleTextField.addDoneButtonToolbar()
    moneyTextField.addDoneButtonToolbar()
    totalValueTextField.addDoneButtonToolbar()
    installmentsInputWithSuffix.addDoneButtonToolbar()

    setupTransactionModeControl()
    setupInstallmentsConstraints()

    setupConstraints()
  }

  private func setupInstallmentsConstraints() {
    installmentsHeightConstraint = installmentsInputContainer.heightAnchor.constraint(
      equalToConstant: 0)
    installmentsHeightConstraint?.isActive = true
  }

  private func setupConstraints() {
    // Get the current content stack view (either regular or edit mode)
    let currentContentStackView = isEditMode ? editModeContentStackView : contentStackView

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

      currentContentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
      currentContentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      currentContentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
      currentContentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
      currentContentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
    ])

    // Self-sizing: scroll view prefers to match content height so the modal grows.
    // Only scrolls when content exceeds the VC's max height cap.
    contentHeightConstraint?.isActive = false
    let heightC = scrollView.heightAnchor.constraint(equalTo: currentContentStackView.heightAnchor)
    heightC.priority = .defaultHigh
    heightC.isActive = true
    contentHeightConstraint = heightC
  }

  private func setupTransactionModeControl() {
    transactionModelControl.onSelectionChanged = { [weak self] mode in
      self?.handleTransactionModeChange(mode)
    }
  }

  private func handleTransactionModeChange(_ mode: TransactionMode) {
    if isAnimating {
      pendingMode = mode
      return
    }

    totalValueLabel.isHidden = (mode != .installments)

    let shouldShowInstallments = mode == .installments

    installmentsInputContainer.layer.removeAllAnimations()

    isAnimating = true
    pendingMode = nil

    let targetHeight: CGFloat = shouldShowInstallments ? Metrics.inputHeight : 0

    UIView.animate(
      withDuration: 0.3,
      delay: 0,
      usingSpringWithDamping: 0.8,
      initialSpringVelocity: 0,
      options: [.beginFromCurrentState, .allowUserInteraction],
      animations: {
        self.installmentsInputContainer.alpha = shouldShowInstallments ? 1.0 : 0.0
        self.installmentsHeightConstraint?.constant = targetHeight
        self.transactionModeStackView.spacing = shouldShowInstallments ? Metrics.spacing3 : 0

        self.layoutIfNeeded()

        if let viewController = self.findViewController() {
          viewController.view.layoutIfNeeded()
        }
      },
      completion: { [weak self] _ in
        guard let self = self else { return }

        self.isAnimating = false

        // Handle any pending mode changes
        if let pendingMode = self.pendingMode {
          self.handleTransactionModeChange(pendingMode)
        }
      }
    )
  }

  @objc private func didTapClose() {
    delegate?.closeModal()
  }

  @objc private func didTapCreateCard() {
    delegate?.didTapCreateCreditCard()
  }

  // MARK: - Validation Helper
  private func isInputValid(_ input: Input) -> Bool {
    // Check if input has text content
    guard let text = input.textField.text, !text.isEmpty else {
      return false
    }

    // Use specific input instances to determine validation logic
    if input === categoryPickerView {
      // Category picker: check if a valid selection is made
      return input.selectedPickerIndex >= 0
        && input.selectedPickerIndex < (input.pickerValues?.count ?? 0)
    } else if input === moneyTextField {
      // Currency input: check if the amount is greater than 0
      return input.centsValue > 0
    } else if input === dateTextField {
      // Date input: check if a valid date is selected or if text exists (for populated fields)
      // In edit mode, we populate the text but dateValue might not be set, so we accept text
      // More lenient validation: check if dateValue exists OR if text is not empty and matches date format
      let hasDateValue = input.dateValue != nil
      let hasValidText = !text.isEmpty && text.count >= 8  // Basic check for "dd/mm/yyyy" format
      let isValid = hasDateValue || hasValidText || (isEditMode && !text.isEmpty)

      return isValid
    } else if input === installmentsTextField || input === installmentsInputWithSuffix {
      // Installments input: check if a valid number is entered
      return Int(text) != nil && Int(text)! > 0
    }

    // For other input types (like title), just check if text exists
    return true
  }

  private func getInputName(_ input: Input) -> String {
    if input === transactionTitleTextField {
      return "Title"
    } else if input === categoryPickerView {
      return "Category"
    } else if input === moneyTextField {
      return "Amount"
    } else if input === dateTextField {
      return "Date"
    } else if input === installmentsTextField || input === installmentsInputWithSuffix {
      return "Installments"
    } else {
      return "Unknown"
    }
  }

  private func setDateRestrictionsForInstallment(transaction: Transaction) {
    // For installment transactions, restrict date picker to the current month only
    let calendar = Calendar.current
    let transactionDate = transaction.date

    // Get the first day of the current transaction's month
    let startOfMonth =
      calendar.dateInterval(of: .month, for: transactionDate)?.start ?? transactionDate

    // Get the last day of the current transaction's month (not the start of next month)
    let year = calendar.component(.year, from: transactionDate)
    let month = calendar.component(.month, from: transactionDate)
    let lastDayOfMonth =
      calendar.range(of: .day, in: .month, for: transactionDate)?.upperBound ?? 31

    var dateComponents = DateComponents()
    dateComponents.year = year
    dateComponents.month = month
    dateComponents.day = lastDayOfMonth - 1  // Subtract 1 because range.upperBound is exclusive

    let endOfMonth = calendar.date(from: dateComponents) ?? transactionDate

    // Set date restrictions to only allow dates within the current month
    initialDateTextField.setDateRestrictions(minimumDate: startOfMonth, maximumDate: endOfMonth)
  }

  func setTotalAmountForInstallment(_ totalAmount: Int) {
    // Set the total amount for installment transactions
    totalValueTextField.text = String(totalAmount)
    totalValueTextField.textField.sendActions(for: .editingChanged)
  }

  private func setupEditModeContent(for transaction: Transaction) {
    // Clear existing arranged subviews
    editModeInputStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

    // Add basic fields
    editModeInputStackView.addArrangedSubview(transactionTitleTextField)
    editModeInputStackView.addArrangedSubview(categoryPickerView)

    // Check if this is an installment transaction (either by mode or by properties)
    let isInstallmentTransaction =
      transaction.mode == .installments
      || (transaction.parentTransactionId != nil && transaction.installmentNumber != nil)

    if isInstallmentTransaction {
      // For installment transactions, show installment-specific fields (like add transaction modal structure)
      editModeInputStackView.addArrangedSubview(installmentsInputContainer)  // Installments field first
      editModeInputStackView.addArrangedSubview(installmentInputsContainer)  // Then total value and initial date

      // Enable installments field for editing
      installmentsInputWithSuffix.isUserInteractionEnabled = true
      installmentsInputWithSuffix.alpha = 1.0
      installmentsInputContainer.alpha = 1.0

      // Show the labels for total value and initial date
      totalValueLabel.isHidden = false
      initialDateLabel.isHidden = false

      // Update height constraint to show the installments field
      installmentsHeightConstraint?.constant = Metrics.inputHeight
    } else {
      // For normal/recurring transactions, show basic fields only
      editModeInputStackView.addArrangedSubview(horizontalInputsStackView)

      // Hide the labels for total value and initial date (not needed for normal/recurring)
      totalValueLabel.isHidden = true
      initialDateLabel.isHidden = true

      // Reset height constraint for non-installment transactions
      installmentsHeightConstraint?.constant = 0
    }
  }

  @objc
  private func didTapSaveTransaction() {
    let basicInputs = [
      transactionTitleTextField, categoryPickerView, moneyTextField, dateTextField,
    ]

    // In edit mode, validate basic inputs plus installment-specific fields if applicable
    let inputsToValidate =
      isEditMode
      ? {
        var editInputs = basicInputs
        // Add installment-specific fields if editing an installment transaction
        if let transaction = editingTransaction, transaction.mode == .installments {
          editInputs = [
            transactionTitleTextField, categoryPickerView, installmentsInputWithSuffix,
            totalValueTextField, initialDateTextField,
          ]
        }
        return editInputs
      }()
      : {
        let selectedMode = transactionModelControl.getSelectedMode()
        var allInputs = basicInputs
        if selectedMode == .installments {
          allInputs.append(installmentsInputWithSuffix)
        }
        return allInputs
      }()

    let invalids = inputsToValidate.filter { input in
      return !isInputValid(input)
    }

    // Only validate transaction type in add mode
    let isTransactionTypeError =
      !isEditMode
      && (incomeSelectorButton.superview != nil && incomeSelectorButton.variant != .selected
        && expenseSelectorButton.superview != nil && expenseSelectorButton.variant != .selected)

    invalids.forEach { $0.setError(true) }

    guard invalids.isEmpty else { return }

    if isTransactionTypeError {
      delegate?.handleError(
        title: "addTransactionModal.alert.transactionType.title".localized,
        message: "addTransactionModal.alert.transactionType.description".localized)
      return
    }

    let title = transactionTitleTextField.textField.text ?? ""
    let rawValues = categoryPickerView.pickerValues ?? []
    let selectedRow = categoryPickerView.selectedPickerIndex
    let categoryKey = rawValues.indices.contains(selectedRow) ? rawValues[selectedRow] : ""

    // Get amount and date based on transaction mode
    let amount: Int
    let date: String

    if isEditMode, let editingTransaction = editingTransaction,
      editingTransaction.mode == .installments
    {
      // For installment transactions in edit mode, use the new input fields
      amount = totalValueTextField.centsValue
      date = initialDateTextField.textField.text ?? ""
    } else {
      // For normal transactions or add mode, use the original input fields
      amount = moneyTextField.centsValue
      date = dateTextField.textField.text ?? ""
    }

    // Get transaction type and mode based on current mode
    let typeEnum: TransactionType
    let typeKey: String
    let selectedMode: TransactionMode

    if isEditMode, let editingTransaction = editingTransaction {
      // In edit mode, use existing transaction data
      typeEnum = editingTransaction.type
      typeKey = String(describing: typeEnum)
      selectedMode = editingTransaction.mode
    } else {
      // In add mode, get from UI controls
      typeEnum = incomeSelectorButton.variant == .selected ? .income : .expense
      typeKey = String(describing: typeEnum)
      selectedMode = transactionModelControl.getSelectedMode()
    }

    // Determine if this is add or edit mode
    if isEditMode, let editingTransaction = editingTransaction,
      let transactionId = editingTransaction.id
    {
      // Edit mode - handle different transaction types
      if editingTransaction.mode == .installments {
        // For installment transactions, directly update all installments (no alert needed)
        let installmentData = InstallmentTransactionData(
          title: title, totalAmount: amount, date: date, category: categoryKey,
          transactionType: typeKey,
          installments: Int(installmentsInputWithSuffix.textField.text ?? "1") ?? 1,
          creditCardId: getSelectedCreditCardId())
        delegate?.updateInstallmentTransactionData(id: transactionId, installmentData)
      } else if editingTransaction.mode == .recurring {
        // For recurring transactions, show alert with options
        showEditScopeAlert(
          transactionId: transactionId,
          transactionData: AddTransactionData(
            title: title, amount: amount, date: date, category: categoryKey,
            transactionType: typeKey, creditCardId: getSelectedCreditCardId()),
          installmentData: nil,
          mode: selectedMode
        )
      } else {
        // Normal transaction - proceed with edit (include payment method change)
        delegate?.updateTransactionData(
          id: transactionId,
          AddTransactionData(
            title: title, amount: amount, date: date, category: categoryKey,
            transactionType: typeKey, creditCardId: getSelectedCreditCardId())
        )
      }
    } else {
      // Add mode
      let creditCardId = getSelectedCreditCardId()

      switch selectedMode {
      case .normal:
        delegate?.sendTransactionData(
          AddTransactionData(
            title: title, amount: amount, date: date, category: categoryKey,
            transactionType: typeKey, creditCardId: creditCardId)
        )
      case .recurring:
        delegate?.sendRecurringTransactionData(
          AddTransactionData(
            title: title, amount: amount, date: date, category: categoryKey,
            transactionType: typeKey, creditCardId: creditCardId)
        )
      case .installments:
        let installmentsCount = Int(installmentsInputWithSuffix.textField.text ?? "1") ?? 1
        delegate?.sendInstallmentTransactionData(
          InstallmentTransactionData(
            title: title, totalAmount: amount, date: date, category: categoryKey,
            transactionType: typeKey, installments: installmentsCount, creditCardId: creditCardId))
      }
    }
  }

  // MARK: - Payment Method Logic

  private func selectPaymentMethod(_ method: PaymentMethod) {
    cashDebitOption.setSelected(method == .cashDebit)
    creditCardOption.setSelected(method != .cashDebit)

    let showCardSelector = method != .cashDebit

    // Update state before animating so layoutIfNeeded reflects all changes
    if case .creditCard = method {
      if let defaultCard = availableCards.first(where: { $0.isDefault }) {
        selectedPaymentMethod = .creditCard(cardId: defaultCard.id ?? 0)
        selectedCard = defaultCard
        if let index = availableCards.firstIndex(where: { $0.id == defaultCard.id }) {
          cardPickerInput.selectPickerValue(at: index)
        }
      } else {
        selectedPaymentMethod = .creditCard(cardId: 0)
        selectedCard = nil
      }
    } else {
      selectedPaymentMethod = .cashDebit
      selectedCard = nil
    }

    UIView.animate(withDuration: 0.25) {
      self.cardSelectorContainer.isHidden = !showCardSelector
      self.cardSelectorContainer.alpha = showCardSelector ? 1 : 0
      self.updateStatementInfoBanner()
      self.layoutIfNeeded()
      if let vc = self.findViewController() { vc.view.layoutIfNeeded() }
    }
  }

  func loadAvailableCards(_ cards: [CreditCard]) {
    availableCards = cards
    let names = cards.map { "\($0.name) ****\($0.lastFourDigits)" }

    cardPickerInput.updatePickerValues(names)

    if cards.isEmpty {
      cardPickerInput.textField.text = "addTransactionModal.paymentMethod.noCards".localized
      cardPickerInput.isUserInteractionEnabled = false
      createCardButton.isHidden = false
    } else {
      cardPickerInput.isUserInteractionEnabled = true
      createCardButton.isHidden = true
    }

    cardPickerInput.onPickerSelectionChanged = { [weak self] index in
      guard let self, index < self.availableCards.count else { return }
      let card = self.availableCards[index]
      self.selectedPaymentMethod = .creditCard(cardId: card.id ?? 0)
      self.selectedCard = card
      self.updateStatementInfoBanner()
    }

    // Pre-select payment method for edit mode
    if isEditMode, let editTx = editingTransaction, editTx.type == .expense {
      if let cardId = editTx.creditCardId, cardId > 0 {
        cashDebitOption.setSelected(false)
        creditCardOption.setSelected(true)
        cardSelectorContainer.isHidden = false
        cardSelectorContainer.alpha = 1

        if let cardIndex = availableCards.firstIndex(where: { $0.id == cardId }) {
          cardPickerInput.selectPickerValue(at: cardIndex)
          selectedCard = availableCards[cardIndex]
          selectedPaymentMethod = .creditCard(cardId: cardId)
          updateStatementInfoBanner()
        }
      } else {
        cashDebitOption.setSelected(true)
        creditCardOption.setSelected(false)
        selectedPaymentMethod = .cashDebit
      }
    }
  }

  private func updateStatementInfoBanner() {
    guard let card = selectedCard else {
      statementInfoBanner.isHidden = true
      return
    }

    let service = CreditCardService()
    let closingDate = service.calculateClosingDate(card: card, transactionDate: Date())
    let dueDate = service.calculateDueDate(closingDate: closingDate, card: card)
    let monthName = DateFormatter.monthFormatter.string(from: closingDate)
    let dueDateStr = DateFormatter.fullDateFormatter.string(from: dueDate)
    statementInfoBanner.text = String(format: "addTransactionModal.paymentMethod.statementInfo".localized, monthName, dueDateStr)
    statementInfoBanner.isHidden = false
  }

  func getSelectedCreditCardId() -> Int? {
    if case .creditCard(let cardId) = selectedPaymentMethod, cardId > 0 {
      return cardId
    }
    return nil
  }

  func showPaymentMethodSection(_ show: Bool) {
    UIView.animate(withDuration: 0.25) {
      self.paymentMethodSection.isHidden = !show
      self.paymentMethodSection.alpha = show ? 1 : 0
      self.layoutIfNeeded()
      if let vc = self.findViewController() { vc.view.layoutIfNeeded() }
    }

    if !show {
      selectPaymentMethod(.cashDebit)
    }
  }

  // MARK: - Edit Mode Configuration
  func configureForEdit(with transaction: Transaction) {
    isEditMode = true
    editingTransaction = transaction
    currentEditMode = .edit(transaction: transaction)

    // Switch to simplified layout for edit mode
    contentStackView.removeFromSuperview()
    scrollView.addSubview(editModeContentStackView)
    setupConstraints()

    // Update UI for edit mode
    headerTitleLabel.text = currentEditMode.title
    headerTitleLabel.applyStyle()  // Ensure uppercase styling is applied
    saveButton.setTitle(currentEditMode.saveButtonTitle, for: .normal)

    // Set up edit mode content based on transaction type
    setupEditModeContent(for: transaction)

    // Show payment method section for expense transactions in edit mode
    if transaction.type == .expense {
      paymentMethodSection.isHidden = false
      editModeContentStackView.insertArrangedSubview(paymentMethodSection, at: 2)
      editModeContentStackView.setCustomSpacing(Metrics.spacing3, after: editModeInputStackView)
    } else {
      paymentMethodSection.isHidden = true
    }

    // Populate fields with transaction data
    populateFields(with: transaction)

    // Set date restrictions for installment transactions
    if transaction.mode == .installments {
      setDateRestrictionsForInstallment(transaction: transaction)
    }

    // Configure date picker for recurring transactions
    if transaction.isRecurring == true {
      dateTextField.configureForRecurringTransaction(referenceDate: transaction.date)
    }

    // Configure initial date picker for installment transactions (if it's also recurring)
    if transaction.mode == .installments && transaction.isRecurring == true {
      initialDateTextField.configureForRecurringTransaction(referenceDate: transaction.date)
    }
  }

  private func populateFields(with transaction: Transaction) {
    // Populate title
    transactionTitleTextField.text = transaction.title

    // Populate category
    if let categoryIndex = categoryPickerView.pickerValues?.firstIndex(of: transaction.category.key)
    {
      categoryPickerView.selectedPickerIndex = categoryIndex
      categoryPickerView.textField.text = transaction.category.description
    }

    // Populate amount - for installment transactions, show total amount
    let amountInCents: Int
    if transaction.mode == .installments {
      // For installment transactions, we need to calculate the total amount
      // This will be handled by the view controller when calling configureForEdit
      amountInCents = transaction.amount  // This will be overridden by the view controller
    } else {
      amountInCents = transaction.amount
    }

    moneyTextField.text = String(amountInCents)
    // Trigger currency formatting
    moneyTextField.textField.sendActions(for: .editingChanged)

    // Populate date
    let dateString = DateFormatter.fullDateFormatter.string(from: transaction.date)
    dateTextField.text = dateString

    // Populate installment-specific fields for installment transactions
    if transaction.mode == .installments {
      // Populate total value field
      totalValueTextField.text = String(amountInCents)
      totalValueTextField.textField.sendActions(for: .editingChanged)

      // Populate initial date field
      let dateString = DateFormatter.fullDateFormatter.string(from: transaction.date)
      initialDateTextField.text = dateString

      // Populate installments field
      if let totalInstallments = transaction.totalInstallments {
        installmentsInputWithSuffix.text = String(totalInstallments)
      }
    }

    // Only populate non-editable fields if not in edit mode
    if !isEditMode {
      // Populate transaction type
      if transaction.type == .income {
        incomeSelectorButton.variant = .selected
        expenseSelectorButton.variant = .normal
      } else {
        incomeSelectorButton.variant = .normal
        expenseSelectorButton.variant = .selected
      }

      // Populate transaction mode
      transactionModelControl.setSelectedMode(transaction.mode)
      if transaction.mode == .installments, let totalInstallments = transaction.totalInstallments {
        installmentsInputWithSuffix.text = String(totalInstallments)
      }

      // Trigger any mode-specific UI updates
      transactionModelControl.onSelectionChanged?(transaction.mode)
    }
  }

  func getEditingTransaction() -> Transaction? {
    return editingTransaction
  }

  func isInEditMode() -> Bool {
    return isEditMode
  }

  private func showEditScopeAlert(
    transactionId: Int,
    transactionData: AddTransactionData,
    installmentData: InstallmentTransactionData?,
    mode: TransactionMode
  ) {
    guard let viewController = findViewController() else { return }

    let alertTitle =
      mode == .recurring
      ? "editTransaction.alert.recurring.title".localized
      : "editTransaction.alert.installments.title".localized

    let alertMessage =
      mode == .recurring
      ? "editTransaction.alert.recurring.message".localized
      : "editTransaction.alert.installments.message".localized

    let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)

    if mode == .installments {
      // For installments, only allow editing all (no single edit option)
      let editAllAction = UIAlertAction(
        title: "editTransaction.alert.editAll".localized,
        style: .default
      ) { [weak self] _ in
        self?.performAllEdit(
          transactionId: transactionId, transactionData: transactionData,
          installmentData: installmentData, mode: mode)
      }

      let cancelAction = UIAlertAction(title: "alert.cancel".localized, style: .cancel)

      alert.addAction(editAllAction)
      alert.addAction(cancelAction)
    } else {
      // For recurring transactions, allow three options
      // Edit only this transaction
      let editSingleAction = UIAlertAction(
        title: "editTransaction.alert.editSingle".localized,
        style: .default
      ) { [weak self] _ in
        self?.performSingleEdit(
          transactionId: transactionId, transactionData: transactionData,
          installmentData: installmentData, mode: mode)
      }

      // Edit future occurrences only
      let editFutureAction = UIAlertAction(
        title: "recurring.edit.future".localized,
        style: .default
      ) { [weak self] _ in
        self?.performFutureEdit(
          transactionId: transactionId, transactionData: transactionData,
          installmentData: installmentData, mode: mode)
      }

      // Edit all related transactions
      let editAllAction = UIAlertAction(
        title: "editTransaction.alert.editAll".localized,
        style: .default
      ) { [weak self] _ in
        self?.performAllEdit(
          transactionId: transactionId, transactionData: transactionData,
          installmentData: installmentData, mode: mode)
      }

      let cancelAction = UIAlertAction(title: "alert.cancel".localized, style: .cancel)

      alert.addAction(editSingleAction)
      alert.addAction(editFutureAction)
      alert.addAction(editAllAction)
      alert.addAction(cancelAction)
    }

    viewController.present(alert, animated: true)
  }

  private func performSingleEdit(
    transactionId: Int,
    transactionData: AddTransactionData,
    installmentData: InstallmentTransactionData?,
    mode: TransactionMode
  ) {
    switch mode {
    case .normal:
      delegate?.updateTransactionData(id: transactionId, transactionData)
    case .recurring:
      delegate?.updateSingleRecurringTransactionData(id: transactionId, transactionData)
    case .installments:
      if let installmentData = installmentData {
        delegate?.updateSingleInstallmentTransactionData(id: transactionId, installmentData)
      }
    }
  }

  private func performFutureEdit(
    transactionId: Int,
    transactionData: AddTransactionData,
    installmentData: InstallmentTransactionData?,
    mode: TransactionMode
  ) {
    switch mode {
    case .normal:
      delegate?.updateTransactionData(id: transactionId, transactionData)
    case .recurring:
      delegate?.updateRecurringTransactionDataWithOption(
        id: transactionId, transactionData, editOption: .futureOnly)
    case .installments:
      if let installmentData = installmentData {
        delegate?.updateInstallmentTransactionData(id: transactionId, installmentData)
      }
    }
  }

  private func performAllEdit(
    transactionId: Int,
    transactionData: AddTransactionData,
    installmentData: InstallmentTransactionData?,
    mode: TransactionMode
  ) {
    switch mode {
    case .normal:
      delegate?.updateTransactionData(id: transactionId, transactionData)
    case .recurring:
      delegate?.updateRecurringTransactionDataWithOption(
        id: transactionId, transactionData, editOption: .all)
    case .installments:
      if let installmentData = installmentData {
        delegate?.updateInstallmentTransactionData(id: transactionId, installmentData)
      }
    }
  }
}
