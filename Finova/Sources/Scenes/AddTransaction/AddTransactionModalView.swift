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

  // Simplified content stack for edit mode (no mode controls)
  private lazy var editModeContentStackView: UIStackView = {
    let sv = UIStackView(
      axis: .vertical, spacing: Metrics.spacing7, distribution: .fill,
      arrangedSubviews: [
        headerStackView, editModeInputStackView, transactionButtonsStackView, separator, saveButton,
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
      arrangedSubviews: [moneyAndFxStack, totalValueLabel]
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
      transactionTitleTextField, categoryPickerView, moneyAndFxStack,
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

  private lazy var horizontalInputsStackView: UIStackView = {
    let stackView = UIStackView(
      axis: .horizontal, spacing: Metrics.spacing3, distribution: .fillEqually,
      arrangedSubviews: [moneyColumnStack, dateColumnStack])
    stackView.alignment = .top
    return stackView
  }()

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

  /// The business-day rule for this transaction. Pre-filled from the global default for a new one,
  /// and from the transaction itself when editing.
  private(set) var selectedBusinessDayRule: BusinessDayRule =
    UserDefaultsManager.getDefaultBusinessDayRule() {
    didSet { updateBusinessDayUI() }
  }

  private lazy var businessDayRuleButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.contentHorizontalAlignment = .leading
    button.titleLabel?.font = Fonts.textXS.font
    button.setTitleColor(Colors.gray500, for: .normal)
    button.addTarget(self, action: #selector(businessDayRuleTapped), for: .touchUpInside)
    return button
  }()

  /// Shows the date the transaction will actually land on, but only when the rule moves it. A rule
  /// that silently changed the saved date with nothing on screen would look like a bug.
  private lazy var effectiveDateHintLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray500
    label.numberOfLines = 1
    label.isHidden = true
    return label
  }()

  // MARK: Foreign-currency income

  /// The currency the amount is typed in. The app currency unless the user picked another one
  /// (income only, not installments).
  private(set) var selectedCurrency: String = AppConfig.currencyCode
  /// A rate typed by hand when none is cached (offline), in micros.
  private var manualRateMicros: Int?
  /// The provider difference saved as the default for one currency, in micros. Key + currency.
  static let providerDiffKeyPrefix = "fxProviderDiffMicros."

  /// The provider fee saved as the default for one currency, in basis points. Key + currency.
  static let providerFeeKeyPrefix = "fxProviderFeeBps."

  static func savedProviderFeeBps(for currency: String) -> Int {
    UserDefaults.standard.integer(forKey: providerFeeKeyPrefix + currency)
  }

  static func savedProviderDiffMicros(for currency: String) -> Int {
    UserDefaults.standard.integer(forKey: providerDiffKeyPrefix + currency)
  }

  // The FX card: one full-width block under the amount and the date.
  //
  //   YOU RECEIVE
  //   ≈ R$ 28.000,00
  //   Market 5,6513 → You get 5,6013
  //   Market rate · 18:59                      (tap: type the rate)
  //   ─────────────────────────────
  //   Provider difference          [ R$ 0,05 ]
  //   per US$ 1 · Your default for USD   / Save as default for USD

  private lazy var fxTitleLabel: UILabel = {
    let label = UILabel()
    label.fontStyle = Fonts.title2XS
    label.textColor = Colors.gray500
    label.text = "fx.card.title".localized
    label.applyStyle()
    return label
  }()

  /// `≈ R$ 28.000,00`
  private lazy var fxApproxLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.titleMD.font
    label.textColor = Colors.gray700
    label.numberOfLines = 1
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.7
    return label
  }()

  /// `Market 5,6513 → You get 5,6013`
  private lazy var fxMathLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textSM.font
    label.textColor = Colors.gray600
    label.numberOfLines = 0
    return label
  }()

  /// `Market rate · 18:59`, or "Type the rate" when there is none.
  private lazy var fxRateButton: UIButton = {
    let button = UIButton(type: .system)
    button.contentHorizontalAlignment = .leading
    button.titleLabel?.font = Fonts.textXS.font
    button.titleLabel?.numberOfLines = 1
    button.titleLabel?.adjustsFontSizeToFitWidth = true
    button.titleLabel?.minimumScaleFactor = 0.8
    button.setTitleColor(Colors.gray500, for: .normal)
    button.addTarget(self, action: #selector(fxRateTapped), for: .touchUpInside)
    return button
  }()

  private lazy var fxDivider: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray300
    view.heightAnchor.constraint(equalToConstant: 1).isActive = true
    return view
  }()

  private lazy var fxDiffTitleLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textSMBold.font
    label.textColor = Colors.gray700
    label.text = "fx.diff.title".localized
    label.numberOfLines = 0
    return label
  }()

  /// `per US$ 1`
  private lazy var fxDiffUnitLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray500
    label.numberOfLines = 0
    return label
  }()

  /// R$ 0,05: how much less than the market the user's provider pays per 1 unit.
  private lazy var fxDiffField: Input = {
    let input = Input(type: .currency, placeholder: "0,00")
    input.textField.accessibilityLabel = "fx.diff.title".localized
    input.widthAnchor.constraint(equalToConstant: 128).isActive = true
    input.setContentCompressionResistancePriority(.required, for: .horizontal)
    input.setContentHuggingPriority(.required, for: .horizontal)
    input.textField.addTarget(self, action: #selector(fxInputsChanged), for: .editingChanged)
    return input
  }()

  private lazy var fxFeeTitleLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textSMBold.font
    label.textColor = Colors.gray700
    label.text = "fx.feeRow.title".localized
    label.numberOfLines = 0
    return label
  }()

  private lazy var fxFeeUnitLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray500
    label.text = "fx.feeRow.unit".localized
    label.numberOfLines = 0
    return label
  }()

  /// 0,9 %: the provider's fee, taken from the converted total.
  private lazy var fxFeeField: Input = {
    let input = Input(type: .normal, placeholder: "0,00")
    input.textField.keyboardType = .decimalPad
    input.textField.textAlignment = .left
    input.textField.accessibilityLabel = "fx.feeRow.title".localized
    let suffix = UILabel()
    suffix.text = "%"
    suffix.font = Fonts.input.font
    suffix.textColor = Colors.gray500
    suffix.sizeToFit()
    input.textField.rightView = suffix
    input.textField.rightViewMode = .always
    input.widthAnchor.constraint(equalToConstant: 128).isActive = true
    input.setContentCompressionResistancePriority(.required, for: .horizontal)
    input.setContentHuggingPriority(.required, for: .horizontal)
    input.textField.addTarget(self, action: #selector(fxInputsChanged), for: .editingChanged)
    return input
  }()

  private lazy var fxFeeRow: UIStackView = {
    let texts = UIStackView(
      axis: .vertical, spacing: Metrics.spacing1, arrangedSubviews: [fxFeeTitleLabel, fxFeeUnitLabel])
    let row = UIStackView(
      axis: .horizontal, spacing: Metrics.spacing3, arrangedSubviews: [texts, fxFeeField])
    row.alignment = .center
    return row
  }()

  /// `Fee 0,9% · −R$ 252,07`, under the math line, so the ≈ total adds up.
  private lazy var fxFeeLineLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textSM.font
    label.textColor = Colors.gray600
    label.numberOfLines = 0
    label.isHidden = true
    return label
  }()

  /// "Save as default for USD", or "✓ Your default for USD" when both values are the default.
  private lazy var fxDefaultButton: UIButton = {
    let button = UIButton(type: .system)
    button.contentHorizontalAlignment = .leading
    button.titleLabel?.font = Fonts.textXS.font
    button.titleLabel?.numberOfLines = 0
    button.addTarget(self, action: #selector(fxSaveDefaultTapped), for: .touchUpInside)
    return button
  }()

  private lazy var fxDiffRow: UIStackView = {
    let texts = UIStackView(
      axis: .vertical, spacing: Metrics.spacing1, arrangedSubviews: [fxDiffTitleLabel, fxDiffUnitLabel])
    let row = UIStackView(
      axis: .horizontal, spacing: Metrics.spacing3, arrangedSubviews: [texts, fxDiffField])
    row.alignment = .center
    return row
  }()

  private lazy var fxCard: UIView = {
    let stack = UIStackView(
      axis: .vertical, spacing: Metrics.spacing1,
      arrangedSubviews: [
        fxTitleLabel, fxApproxLabel, fxMathLabel, fxFeeLineLabel, fxRateButton, fxDivider, fxDiffRow,
        fxFeeRow, fxDefaultButton,
      ])
    stack.setCustomSpacing(Metrics.spacing3, after: fxRateButton)
    stack.setCustomSpacing(Metrics.spacing3, after: fxDivider)
    stack.setCustomSpacing(Metrics.spacing4, after: fxDiffRow)
    stack.setCustomSpacing(Metrics.spacing2, after: fxFeeRow)
    stack.translatesAutoresizingMaskIntoConstraints = false
    let card = UIView()
    card.layer.cornerRadius = CornerRadius.extraLarge
    card.layer.borderWidth = 1
    card.layer.borderColor = Colors.gray300.cgColor
    card.backgroundColor = Colors.gray200.withAlphaComponent(0.5)
    card.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: card.topAnchor, constant: Metrics.spacing4),
      stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Metrics.spacing4),
      stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Metrics.spacing4),
      stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Metrics.spacing3),
    ])
    card.isHidden = true
    return card
  }()

  /// The amount + date row, then the FX card under it at full width.
  private lazy var moneyAndFxStack = UIStackView(
    axis: .vertical, spacing: Metrics.spacing3, arrangedSubviews: [horizontalInputsStackView, fxCard])

  /// False when the fee box holds text that is not a percent from 0 to 99,99 ("100", "1,2,3").
  private var feeTextIsValid: Bool { FxMath.feeBps(fromText: fxFeeField.textField.text ?? "") != nil }

  /// The provider fee typed, in basis points (0,9 → 90). 0 when empty or not a percent.
  private var typedFeeBps: Int { FxMath.feeBps(fromText: fxFeeField.textField.text ?? "") ?? 0 }

  /// 90 → "0,9" in the phone's format (up to 2 decimals).
  static func feeDisplay(_ bps: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = .autoupdatingCurrent
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSDecimalNumber(decimal: Decimal(bps) / 100)) ?? FxMath.feeText(bps: bps)
  }

  /// The provider difference typed, in rate micros (R$ 0,05 → 50000).
  private var typedSpreadMicros: Int {
    let digits = CurrencyUtils.fractionDigits(for: AppConfig.currencyCode)
    let minor = fxDiffField.centsValue
    return minor * Int(truncating: NSDecimalNumber(decimal: pow(10, max(0, 6 - digits))))
  }

  private lazy var moneyColumnStack = UIStackView(
    axis: .vertical, spacing: Metrics.spacing1, arrangedSubviews: [moneyTextField])

  private lazy var dateColumnStack = UIStackView(
    axis: .vertical, spacing: Metrics.spacing1,
    arrangedSubviews: [dateTextField, businessDayRuleButton, effectiveDateHintLabel])

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
    // `selectedBusinessDayRule`'s `didSet` only fires on a change, so the selector needs its title
    // filling in once up front or it renders blank until the user touches something.
    updateBusinessDayUI()
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

    contentStackView.setCustomSpacing(Metrics.spacing3, after: headerStackView)

    saveButton.addTarget(self, action: #selector(didTapSaveTransaction), for: .touchUpInside)

    // Add Done button toolbar to inputs that need it
    transactionTitleTextField.addDoneButtonToolbar()
    moneyTextField.addDoneButtonToolbar()
    totalValueTextField.addDoneButtonToolbar()
    installmentsInputWithSuffix.addDoneButtonToolbar()

    setupTransactionModeControl()
    setupInstallmentsConstraints()
    setupDateChangeListener()
    setupCoachMarkTargets()
    setupCurrencyPicker()

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

  private func setupCoachMarkTargets() {
    let fields: [(Input, CoachMarkTarget)] = [
      (transactionTitleTextField, .transactionTitle), (categoryPickerView, .transactionCategory),
      (moneyTextField, .transactionAmount), (dateTextField, .transactionDate),
    ]
    fields.forEach { field, target in field.reportCoachMarkFill(as: target) }
    businessDayRuleButton.accessibilityIdentifier = CoachMarkTarget.transactionDateRule.rawValue
    transactionButtonsStackView.accessibilityIdentifier = CoachMarkTarget.transactionType.rawValue
    saveButton.accessibilityIdentifier = CoachMarkTarget.transactionSave.rawValue
  }

  private func setupDateChangeListener() {
    dateTextField.textField.addTarget(self, action: #selector(dateDidChange), for: .editingChanged)
  }

  @objc private func dateDidChange() {
    // Refreshes the business-day hint too — see `updateStatementInfoBanner`.
    updateStatementInfoBanner()
  }

  private func setupTransactionModeControl() {
    transactionModelControl.accessibilityIdentifier = CoachMarkTarget.transactionMode.rawValue
    transactionModelControl.onSelectionChanged = { [weak self] mode in
      self?.handleTransactionModeChange(mode)
      if mode == .recurring { CoachMarkCenter.shared.post(.transactionModeRecurring) }
    }
  }

  private func handleTransactionModeChange(_ mode: TransactionMode) {
    updateCurrencyAvailability()
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

    // The constraint and the stack spacing change outside the animation block, and only the
    // top-most view is laid out inside it. The other order hung the app. The scroll view
    // sizes itself from its own content, so laying out this view and then its view
    // controller's view inside the block re-entered the layout pass, and every pass attached
    // one more animation to each layer it touched. -[CALayer animationForKey:] then had a
    // longer list to walk on the next pass, layout never settled, and the main thread spun
    // at 100% with the whole app unresponsive - only killing it recovered.
    // Repro: expense -> credit card -> installments -> recurring.
    installmentsHeightConstraint?.constant = targetHeight
    transactionModeStackView.spacing = shouldShowInstallments ? Metrics.spacing3 : 0

    let layoutRoot = findViewController()?.view ?? self
    layoutRoot.setNeedsLayout()

    UIView.animate(
      withDuration: 0.3,
      delay: 0,
      usingSpringWithDamping: 0.8,
      initialSpringVelocity: 0,
      options: [.beginFromCurrentState, .allowUserInteraction],
      animations: {
        self.installmentsInputContainer.alpha = shouldShowInstallments ? 1.0 : 0.0
        layoutRoot.layoutIfNeeded()
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

  private func setDateRestrictionsForInstallment(around transactionDate: Date) {
    // For installment transactions, restrict date picker to the series' start month only
    let calendar = Calendar.current

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

  /// The date the series STARTED, which is what the rebuild on save re-derives every installment
  /// from. The row being edited is one installment, and its own date is its statement's due date:
  /// pre-filling that restarted the whole series at that installment, so the earlier ones vanished.
  func setInitialDateForInstallment(_ startDate: Date) {
    initialDateTextField.text = DateFormatter.fullDateFormatter.string(from: startDate)
    setDateRestrictionsForInstallment(around: startDate)
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
      editModeInputStackView.addArrangedSubview(moneyAndFxStack)

      // Hide the labels for total value and initial date (not needed for normal/recurring)
      totalValueLabel.isHidden = true
      initialDateLabel.isHidden = true

      // Reset height constraint for non-installment transactions
      installmentsHeightConstraint?.constant = 0
    }
  }

  @objc
  private func businessDayRuleTapped() {
    delegate?.didRequestBusinessDayRulePicker(current: selectedBusinessDayRule) { [weak self] rule in
      self?.selectedBusinessDayRule = rule
    }
  }

  /// Keeps the selector title and the "effective date" hint in step with the rule, the picked date
  /// and the payment method.
  func updateBusinessDayUI() {
    // A card purchase's effective date is the statement due date, which the card owns — so the rule
    // has nothing to act on and the selector would be misleading.
    let isCreditCard = getSelectedCreditCardId() != nil
    businessDayRuleButton.isHidden = isCreditCard

    if isCreditCard {
      effectiveDateHintLabel.text = "addTransactionModal.businessDay.creditCardHint".localized
      effectiveDateHintLabel.isHidden = false
      return
    }

    businessDayRuleButton.setTitle("\(selectedBusinessDayRule.title) ▾", for: .normal)

    guard selectedBusinessDayRule.shiftsDates, let picked = currentlyPickedDate() else {
      effectiveDateHintLabel.isHidden = true
      return
    }

    var calendar = Calendar.current
    calendar.timeZone = .current
    let adjusted = BusinessDayAdjuster.adjust(
      picked, rule: selectedBusinessDayRule, calendar: calendar)

    // Nothing to say when the picked date is already a business day.
    guard adjusted != picked else {
      effectiveDateHintLabel.isHidden = true
      return
    }

    effectiveDateHintLabel.text = "addTransactionModal.businessDay.effective".localized(
      DateFormatter.fullDateFormatter.string(from: adjusted))
    effectiveDateHintLabel.isHidden = false
  }

  private func currentlyPickedDate() -> Date? {
    if let value = dateTextField.dateValue { return value }
    guard let text = dateTextField.textField.text, !text.isEmpty else { return nil }
    return DateFormatter.fullDateFormatter.date(from: text)
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

    let isTransactionTypeError =
      incomeSelectorButton.superview != nil && incomeSelectorButton.variant != .selected
        && expenseSelectorButton.superview != nil && expenseSelectorButton.variant != .selected

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

    // Foreign-currency income: convert now, so `amount` is in the app currency everywhere below.
    let fx: FxEditPlanner.Result?
    let fxTouched = selectedCurrency != AppConfig.currencyCode || editingTransaction?.foreign != nil
    if fxTouched, editingTransaction?.mode != .installments {
      // A fee that is not a percent from 0 to 99,99 must never be saved as 0: stop and show it.
      guard feeTextIsValid else {
        fxFeeField.setError(true)
        fxFeeField.textField.becomeFirstResponder()
        return
      }
      let pickedDate = DateFormatter.fullDateFormatter.date(from: date) ?? Date()
      let old = editingTransaction?.foreign
      let live = currentRateMicros()
      fx = FxEditPlanner.apply(
        old: old, oldDate: editingTransaction?.dateTimestamp ?? Int(pickedDate.timeIntervalSince1970),
        newDate: Int(pickedDate.timeIntervalSince1970), currency: selectedCurrency,
        typedAmount: amount, appCurrency: AppConfig.currencyCode,
        liveRateMicros: live?.micros, liveRateDate: live?.date,
        feeBps: typedFeeBps, spreadMicros: typedSpreadMicros)
      if fx == nil {
        // No rate anywhere: ask for one, then the user taps Save again.
        fxRateTapped()
        return
      }
    } else {
      fx = nil
    }
    let amountToSave = fx?.amount ?? amount
    func withForeign(_ data: AddTransactionData) -> AddTransactionData {
      var data = data
      data.foreign = fx?.foreign
      data.foreignTouched = fx != nil
      return data
    }

    // Get transaction type and mode based on current mode
    let typeEnum: TransactionType
    let typeKey: String
    let selectedMode: TransactionMode

    // Always get type from UI controls (selectors are now visible in edit mode too)
    typeEnum = incomeSelectorButton.variant == .selected ? .income : .expense
    typeKey = String(describing: typeEnum)

    if isEditMode, let editingTransaction = editingTransaction {
      selectedMode = editingTransaction.mode
    } else {
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
          creditCardId: getSelectedCreditCardId(), businessDayRule: selectedBusinessDayRule)
        delegate?.updateInstallmentTransactionData(id: transactionId, installmentData)
      } else if editingTransaction.mode == .recurring {
        // For recurring transactions, show alert with options
        showEditScopeAlert(
          transactionId: transactionId,
          transactionData: withForeign(AddTransactionData(
            title: title, amount: amountToSave, date: date, category: categoryKey,
            transactionType: typeKey, creditCardId: getSelectedCreditCardId(), businessDayRule: selectedBusinessDayRule)),
          installmentData: nil,
          mode: selectedMode
        )
      } else {
        // Normal transaction - proceed with edit (include payment method change)
        delegate?.updateTransactionData(
          id: transactionId,
          withForeign(AddTransactionData(
            title: title, amount: amountToSave, date: date, category: categoryKey,
            transactionType: typeKey, creditCardId: getSelectedCreditCardId(), businessDayRule: selectedBusinessDayRule))
        )
      }
    } else {
      // Add mode
      let creditCardId = getSelectedCreditCardId()

      switch selectedMode {
      case .normal:
        delegate?.sendTransactionData(
          withForeign(AddTransactionData(
            title: title, amount: amountToSave, date: date, category: categoryKey,
            transactionType: typeKey, creditCardId: creditCardId,
            businessDayRule: selectedBusinessDayRule))
        )
      case .recurring:
        delegate?.sendRecurringTransactionData(
          withForeign(AddTransactionData(
            title: title, amount: amountToSave, date: date, category: categoryKey,
            transactionType: typeKey, creditCardId: creditCardId,
            businessDayRule: selectedBusinessDayRule))
        )
      case .installments:
        let installmentsCount = Int(installmentsInputWithSuffix.textField.text ?? "1") ?? 1
        delegate?.sendInstallmentTransactionData(
          InstallmentTransactionData(
            title: title, totalAmount: amount, date: date, category: categoryKey,
            transactionType: typeKey, installments: installmentsCount, creditCardId: creditCardId,
            businessDayRule: selectedBusinessDayRule))
      }
    }
  }

  // MARK: - Foreign-currency income

  private func setupCurrencyPicker() {
    moneyTextField.textField.addTarget(
      self, action: #selector(fxInputsChanged), for: .editingChanged)
    dateTextField.textField.addTarget(self, action: #selector(fxInputsChanged), for: .editingChanged)
    fxDiffField.addDoneButtonToolbar()
    fxFeeField.addDoneButtonToolbar()
    updateCurrencyAvailability()
  }

  /// A row's own difference and fee when editing it; otherwise the defaults saved for `currency`.
  private func prefillProviderDiff(currency: String, foreign: ForeignAmount?) {
    let micros: Int
    let fee: Int
    if let foreign = foreign, foreign.currency == currency {
      micros = foreign.spreadMicros ?? 0
      fee = foreign.feeBps ?? 0
    } else {
      micros = Self.savedProviderDiffMicros(for: currency)
      fee = Self.savedProviderFeeBps(for: currency)
    }
    fxFeeField.textField.text = fee > 0 ? Self.feeDisplay(fee) : nil
    let digits = CurrencyUtils.fractionDigits(for: AppConfig.currencyCode)
    let unit = Int(truncating: NSDecimalNumber(decimal: pow(10, max(0, 6 - digits))))
    fxDiffField.setCentsValue(micros / unit)
    if micros == 0 { fxDiffField.textField.text = nil }  // Show the grey "0,00" hint, not a value.
  }

  @objc private func fxSaveDefaultTapped() {
    guard selectedCurrency != AppConfig.currencyCode else { return }
    guard feeTextIsValid else {
      fxFeeField.setError(true)
      return
    }
    UserDefaults.standard.set(typedSpreadMicros, forKey: Self.providerDiffKeyPrefix + selectedCurrency)
    UserDefaults.standard.set(typedFeeBps, forKey: Self.providerFeeKeyPrefix + selectedCurrency)
    updateFxHint()
  }

  /// The picker exists only for income, never for installments, and only when the app currency is
  /// one the rate provider covers. Anything else resets the field to the app currency.
  func updateCurrencyAvailability() {
    let isIncome = incomeSelectorButton.variant == .selected
    let mode = isEditMode ? (editingTransaction?.mode ?? .normal) : transactionModelControl.getSelectedMode()
    let available = isIncome && mode != .installments && ForeignCurrencyService.shared.isAvailable
    if available {
      moneyTextField.setCurrencyMenu(makeCurrencyMenu())
    } else {
      moneyTextField.setCurrencyMenu(nil)
      if selectedCurrency != AppConfig.currencyCode { selectCurrency(AppConfig.currencyCode) }
    }
    updateFxHint()
  }

  private func makeCurrencyMenu() -> UIMenu {
    let app = AppConfig.currencyCode
    func action(_ code: String) -> UIAction {
      UIAction(
        title: "\(code) · \(ForeignCurrencyService.symbol(for: code))",
        state: code == selectedCurrency ? .on : .off
      ) { [weak self] _ in self?.selectCurrency(code) }
    }
    let common = ([app] + ForeignCurrencyService.commonCurrencies.filter { $0 != app }).map(action)
    let rest = ForeignCurrencyService.allCurrencies
      .filter { $0 != app && !ForeignCurrencyService.commonCurrencies.contains($0) }
      .map(action)
    return UIMenu(
      title: "fx.picker.title".localized,
      children: [
        UIMenu(options: .displayInline, children: common),
        UIMenu(title: "fx.picker.more".localized, children: rest),
      ])
  }

  private func selectCurrency(_ code: String) {
    selectedCurrency = code
    manualRateMicros = nil
    moneyTextField.setCurrency(code)
    if moneyTextField.currencyCode != code { return }
    if code != AppConfig.currencyCode { prefillProviderDiff(currency: code, foreign: editingTransaction?.foreign) }
    // Rebuild so the checkmark follows the choice.
    if incomeSelectorButton.variant == .selected { moneyTextField.setCurrencyMenu(makeCurrencyMenu()) }
    updateFxHint()
    guard code != AppConfig.currencyCode else { return }
    Task { [weak self] in
      await ForeignCurrencyService.shared.latest(for: code)
      await MainActor.run { self?.updateFxHint() }
    }
  }

  @objc private func fxInputsChanged() { updateFxHint() }

  /// The rate to convert with now: the newest cached one, or the one typed by hand. `date` is the
  /// market's quote time (or the ECB day for the fallback).
  private func currentRateMicros() -> (micros: Int, date: Int?, quote: FxQuote?)? {
    if let manual = manualRateMicros { return (manual, Int(Date().timeIntervalSince1970), nil) }
    guard let quote = ForeignCurrencyService.shared.cachedLatest(for: selectedCurrency) else {
      return nil
    }
    return (quote.rateMicros, quote.quotedAt ?? FxDay.epoch(of: quote.date), quote)
  }

  /// Fills the FX card. Locked rows show their locked rate; the provider difference still applies.
  func updateFxHint() {
    let app = AppConfig.currencyCode
    guard selectedCurrency != app else {
      fxCard.isHidden = true
      return
    }
    fxCard.isHidden = false
    let symbol = ForeignCurrencyService.symbol(for: selectedCurrency)
    fxDiffUnitLabel.text = "fx.diff.unit".localized("\(symbol) 1")
    updateDefaultButton()

    let fee = typedFeeBps
    fxFeeField.setError(!feeTextIsValid)
    let spread = typedSpreadMicros

    let rateMicros: Int
    if let fx = editingTransaction?.foreign, fx.isLocked, fx.currency == selectedCurrency,
      let locked = fx.rateMicros
    {
      rateMicros = locked
      let day = fx.lockedAt.map { ForeignCurrencyService.shortDate(epoch: $0) } ?? ""
      fxRateButton.setTitle("fx.card.locked".localized(day), for: .normal)
      fxRateButton.setTitleColor(Colors.gray500, for: .disabled)
      fxRateButton.setTitleColor(Colors.gray500, for: .normal)
      fxRateButton.isEnabled = false
    } else if let rate = currentRateMicros() {
      rateMicros = rate.micros
      let source = rate.quote.map(ForeignCurrencyService.sourceText) ?? "fx.hint.manual".localized
      fxRateButton.setTitle(source, for: .normal)
      fxRateButton.setTitleColor(Colors.gray500, for: .normal)
      fxRateButton.isEnabled = true
    } else {
      fxApproxLabel.text = "fx.hint.noRate".localized
      fxMathLabel.text = nil
      fxMathLabel.isHidden = true
      fxFeeLineLabel.isHidden = true
      fxRateButton.setTitle("fx.hint.typeRate".localized, for: .normal)
      fxRateButton.setTitleColor(Colors.mainMagenta, for: .normal)
      fxRateButton.isEnabled = true
      return
    }
    // Difference first (the rate), then the fee off the total: the same order FxMath uses.
    let beforeFee = FxConversion.convert(
      fxAmount: moneyTextField.centsValue, currency: selectedCurrency, rateMicros: rateMicros,
      appCurrency: app, spreadMicros: spread)
    let converted = FxConversion.convert(
      fxAmount: moneyTextField.centsValue, currency: selectedCurrency, rateMicros: rateMicros,
      appCurrency: app, feeBps: fee, spreadMicros: spread)
    fxApproxLabel.text = "≈ " + converted.currencyString
    fxMathLabel.isHidden = false
    fxMathLabel.attributedText = mathText(marketMicros: rateMicros, spreadMicros: spread)
    fxFeeLineLabel.isHidden = fee == 0
    fxFeeLineLabel.text = fee == 0 ? nil : "fx.card.feeLine".localized(
      Self.feeDisplay(fee) + "%", "\u{2212}" + (beforeFee - converted).currencyString)
  }

  /// `Market 5,6513 → You get 5,6013`, the second number bold. Just `Market 5,6513` with no difference.
  private func mathText(marketMicros: Int, spreadMicros: Int) -> NSAttributedString {
    let market = Self.plainRate(marketMicros)
    let regular: [NSAttributedString.Key: Any] = [.font: Fonts.textSM.font, .foregroundColor: Colors.gray600]
    guard spreadMicros > 0 else {
      return NSAttributedString(string: "fx.card.marketOnly".localized(market), attributes: regular)
    }
    let effective = FxMath.effectiveRateMicros(rateMicros: marketMicros, spreadMicros: spreadMicros)
    let text = NSMutableAttributedString(
      string: "fx.card.market".localized(market) + "  →  ", attributes: regular)
    text.append(NSAttributedString(
      string: "fx.card.youGet".localized(Self.plainRate(effective)),
      attributes: [.font: Fonts.textSMBold.font, .foregroundColor: Colors.gray700]))
    return text
  }

  /// 5651550 → "5,65155" in the phone's format, 2 to 6 decimals: the full rate the amount uses, so
  /// amount × rate on screen adds up.
  static func plainRate(_ micros: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = .autoupdatingCurrent
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 6
    let value = Decimal(micros) / Decimal(FxMath.microsPerUnit)
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
  }

  private func updateDefaultButton() {
    guard feeTextIsValid else {
      // Nothing to save until the fee is a real percent.
      fxDefaultButton.setTitle("fx.diff.saveDefault".localized(selectedCurrency), for: .normal)
      fxDefaultButton.setTitleColor(Colors.gray400, for: .disabled)
      fxDefaultButton.isEnabled = false
      return
    }
    let typed = (typedSpreadMicros, typedFeeBps)
    let saved = (
      Self.savedProviderDiffMicros(for: selectedCurrency), Self.savedProviderFeeBps(for: selectedCurrency))
    if typed == saved {
      let hasAny = typed.0 > 0 || typed.1 > 0
      fxDefaultButton.setTitle(
        hasAny ? "fx.diff.isDefault".localized(selectedCurrency) : "fx.diff.hint".localized,
        for: .normal)
      fxDefaultButton.setTitleColor(Colors.gray500, for: .normal)
      fxDefaultButton.setTitleColor(Colors.gray500, for: .disabled)
      fxDefaultButton.isEnabled = false
    } else {
      fxDefaultButton.setTitle("fx.diff.saveDefault".localized(selectedCurrency), for: .normal)
      fxDefaultButton.setTitleColor(Colors.mainMagenta, for: .normal)
      fxDefaultButton.isEnabled = true
    }
  }

  @objc private func fxRateTapped() {
    delegate?.didRequestManualRate(currency: selectedCurrency) { [weak self] micros in
      guard let self = self, let micros = micros else { return }
      self.manualRateMicros = micros
      self.updateFxHint()
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
      } else if let firstCard = availableCards.first, let cardId = firstCard.id {
        // No default card — auto-select the first available card so the picker
        // doesn't stay at cardId 0 when the user taps Done without scrolling
        selectedPaymentMethod = .creditCard(cardId: cardId)
        selectedCard = firstCard
        cardPickerInput.selectPickerValue(at: 0)
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
    // Every payment-method change funnels through here, so the business-day selector hides and shows
    // with the card without each assignment site having to remember.
    updateBusinessDayUI()

    guard let card = selectedCard else {
      statementInfoBanner.isHidden = true
      return
    }

    // Use the selected transaction date instead of today's date
    let transactionDate: Date
    if let selectedDate = dateTextField.dateValue {
      transactionDate = selectedDate
    } else if let dateText = dateTextField.textField.text,
              !dateText.isEmpty,
              let parsedDate = DateFormatter.fullDateFormatter.date(from: dateText) {
      transactionDate = parsedDate
    } else {
      transactionDate = Date()
    }

    let service = CreditCardService()
    let closingDate = service.calculateClosingDate(card: card, transactionDate: transactionDate)
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
    if show && isEditMode && paymentMethodSection.superview == nil {
      // Insert after editModeInputStackView in the edit mode stack
      if let inputIndex = editModeContentStackView.arrangedSubviews.firstIndex(of: editModeInputStackView) {
        editModeContentStackView.insertArrangedSubview(paymentMethodSection, at: inputIndex + 1)
        editModeContentStackView.setCustomSpacing(Metrics.spacing3, after: editModeInputStackView)
      }
    }

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

    // The row's own rule, not the global default: editing a transaction must not silently re-rule it
    // to whatever the user has since chosen for new ones.
    selectedBusinessDayRule = transaction.businessDayRule

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
      editModeContentStackView.insertArrangedSubview(paymentMethodSection, at: 3)
      editModeContentStackView.setCustomSpacing(Metrics.spacing3, after: editModeInputStackView)
    } else {
      paymentMethodSection.isHidden = true
    }

    // Populate fields with transaction data
    populateFields(with: transaction)

    // Set date restrictions for installment transactions
    if transaction.mode == .installments {
      setDateRestrictionsForInstallment(around: transaction.date)
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

    if let fx = transaction.foreign, transaction.mode != .installments {
      // Foreign income is edited in the money it was received in.
      selectedCurrency = fx.currency
      moneyTextField.setCurrency(fx.currency)
      moneyTextField.text = String(fx.amount)
      prefillProviderDiff(currency: fx.currency, foreign: fx)
    } else {
      moneyTextField.text = String(amountInCents)
    }
    // Trigger currency formatting
    moneyTextField.textField.sendActions(for: .editingChanged)

    // Populate date with the date the user originally PICKED, not the one a business-day rule moved
    // it to. Showing the shifted date would re-adjust it on every save, walking the transaction a few
    // days further each time. The shifted date is shown separately by the "effective" hint.
    let dateString = DateFormatter.fullDateFormatter.string(from: transaction.unadjustedDate)
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

    // Populate transaction type (both add and edit mode)
    if transaction.type == .income {
      incomeSelectorButton.variant = .selected
      expenseSelectorButton.variant = .normal
    } else {
      incomeSelectorButton.variant = .normal
      expenseSelectorButton.variant = .selected
    }
    updateCurrencyAvailability()

    if !isEditMode {
      // Populate transaction mode (only in add mode)
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
