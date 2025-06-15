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

  let categoryOptions = TransactionCategory.allCases

  private lazy var contentStackView: UIStackView = {
    let sv = UIStackView(
      axis: .vertical, spacing: Metrics.spacing7, distribution: .fill,
      arrangedSubviews: [
        headerStackView, inputStackView, transactionButtonsStackView, separator, saveButton,
      ])
    sv.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: Metrics.spacing10, leading: Metrics.spacing8, bottom: Metrics.spacing4,
      trailing: Metrics.spacing8)
    sv.isLayoutMarginsRelativeArrangement = true

    // Improve layout behavior for dynamic content
    sv.setContentHuggingPriority(UILayoutPriority(251), for: .vertical)
    sv.setContentCompressionResistancePriority(UILayoutPriority(751), for: .vertical)

    return sv
  }()

  private lazy var headerStackView = UIStackView(
    axis: .horizontal, alignment: .center, arrangedSubviews: [headerTitleLabel, closeIconButton])

  private lazy var inputStackView = UIStackView(
    axis: .vertical, spacing: Metrics.spacing3,
    arrangedSubviews: [
      transactionTitleTextField, categoryPickerView, transactionModeStackView,
      horizontalInputsStackView,
    ])

  private lazy var transactionModeStackView = UIStackView(
    axis: .vertical, spacing: Metrics.spacing3,
    arrangedSubviews: [transactionModelControl, installmentsInputContainer])

  private lazy var horizontalInputsStackView = UIStackView(
    axis: .horizontal, spacing: Metrics.spacing3, distribution: .fillEqually,
    arrangedSubviews: [moneyTextField, dateTextField])

  private lazy var installmentsInputContainer: UIStackView = {
    let stackView = UIStackView(
      axis: .vertical, spacing: Metrics.spacing1, arrangedSubviews: [installmentsTextField])
    stackView.isHidden = true
    stackView.alpha = 0

    // Set appropriate priorities for smooth animation and layout
    stackView.setContentHuggingPriority(UILayoutPriority(250), for: .vertical)
    stackView.setContentCompressionResistancePriority(UILayoutPriority(750), for: .vertical)

    return stackView
  }()

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

    return button
  }()

  private let transactionTitleTextField = Input(
    placeholder: "addTransactionModal.input.transactionTitle".localized)
  let categoryPickerView = Input(
    type: .picker(values: TransactionCategory.allCases.map { $0.key }),
    placeholder: "addTransactionModal.input.category".localized, icon: UIImage(named: "tag"),
    iconPosition: .left)

  private let transactionModelControl = InputSegmentedControl()

  private let installmentsTextField = Input(
    type: .number, placeholder: "installments.placeholder".localized)

  private let moneyTextField = Input(type: .currency, placeholder: "0,00")

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

  private let saveButton = Button(label: "addTransactionModal.button.save".localized)

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

    addSubview(contentStackView)
    closeIconButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)

    saveButton.addTarget(self, action: #selector(didTapSaveTransaction), for: .touchUpInside)

    setupTransactionModeControl()

    setupConstraints()
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      contentStackView.topAnchor.constraint(equalTo: topAnchor),
      contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
      contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
      contentStackView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  private func setupTransactionModeControl() {
    transactionModelControl.onSelectionChanged = { [weak self] mode in
      self?.handleTransactionModeChange(mode)
    }
  }

  private func handleTransactionModeChange(_ mode: TransactionMode) {
    let shouldShowInstallments = mode == .installments

    UIView.animate(
      withDuration: 0.3,
      animations: {
        self.installmentsInputContainer.isHidden = !shouldShowInstallments
        self.installmentsInputContainer.alpha = shouldShowInstallments ? 1.0 : 0.0

        // Force layout updates for the entire view hierarchy
        self.layoutIfNeeded()
        self.superview?.layoutIfNeeded()

        // If we're in a view controller, update its view as well
        if let viewController = self.findViewController() {
          viewController.view.layoutIfNeeded()
        }
      })
  }

  @objc private func didTapClose() {
    delegate?.closeModal()
  }

  @objc
  private func didTapSaveTransaction() {
    let basicInputs = [
      transactionTitleTextField, categoryPickerView, moneyTextField, dateTextField,
    ]

    let selectedMode = transactionModelControl.getSelectedMode()

    var allInputs = basicInputs
    if selectedMode == .installments {
      allInputs.append(installmentsTextField)
    }

    let invalids = allInputs.filter { !$0.textField.hasText }

    let isTransactionTypeError =
      incomeSelectorButton.variant != .selected && expenseSelectorButton.variant != .selected

    invalids.forEach { $0.setError(true) }

    guard invalids.isEmpty else { return }

    if isTransactionTypeError {
      delegate?.handleError(
        title: "addTransactionModal.alert.transactionType.title".localized,
        message: "addTransactionModal.alert.transactionType.description".localized)
      return
    }

    let title = transactionTitleTextField.textField.text ?? ""
    let amount = moneyTextField.centsValue
    let date = dateTextField.textField.text ?? ""
    let rawValues = categoryPickerView.pickerValues ?? []
    let selectedRow = categoryPickerView.selectedPickerIndex
    let categoryKey =
      rawValues.indices.contains(selectedRow)
      ? rawValues[selectedRow]
      : ""

    let typeEnum: TransactionType =
      incomeSelectorButton.variant == .selected
      ? .income
      : .expense
    let typeKey = String(describing: typeEnum)

    switch selectedMode {
    case .normal:
      delegate?.sendTransactionData(
        title: title, amount: amount, date: date, category: categoryKey, transactionType: typeKey)
    case .recurring:
      delegate?.sendRecurringTransactionData(
        title: title, amount: amount, date: date, category: categoryKey, transactionType: typeKey)
    case .installments:
      let installmentsCount = Int(installmentsTextField.textField.text ?? "1") ?? 1
      delegate?.sendInstallmentTransactionData(
        title: title, totalAmount: amount, date: date, category: categoryKey,
        transactionType: typeKey, installments: installmentsCount)
    }
  }
}
