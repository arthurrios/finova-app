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
        let sv = UIStackView(axis: .vertical, spacing: Metrics.spacing7, distribution: .fill, arrangedSubviews: [headerStackView, inputStackView, transactionButtonsStackView, separator, saveButton])
        sv.directionalLayoutMargins = NSDirectionalEdgeInsets(top: Metrics.spacing10, leading: Metrics.spacing8, bottom: Metrics.spacing4, trailing: Metrics.spacing8)
        sv.isLayoutMarginsRelativeArrangement = true
        return sv
    }()
    
    private lazy var headerStackView = UIStackView(axis: .horizontal, alignment: .center, arrangedSubviews: [headerTitleLabel, closeIconButton])
    
    private lazy var inputStackView = UIStackView(axis: .vertical, spacing: Metrics.spacing3, arrangedSubviews: [transactionTitleTextField, categoryPickerView, horizontalInputsStackView])
    
    private lazy var horizontalInputsStackView = UIStackView(axis: .horizontal, spacing: Metrics.spacing3, distribution: .fillEqually, arrangedSubviews: [moneyTextField, dateTextField])
    
    private lazy var transactionButtonsStackView = UIStackView(axis: .horizontal, spacing: Metrics.spacing3, distribution: .fillEqually, arrangedSubviews: [incomeSelectorButton, expenseSelectorButton])
    
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
            button.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        return button
    }()
    
    private let transactionTitleTextField = Input(placeholder: "addTransactionModal.input.transactionTitle".localized)
    let categoryPickerView = Input(type: .picker(values: TransactionCategory.allCases.map { $0.key }), placeholder: "addTransactionModal.input.category".localized, icon: UIImage(named: "tag"), iconPosition: .left)
    
    private let moneyTextField = Input(type: .currency, placeholder: "0,00")
    
    private let dateTextField = Input(type: .date(style: .fullDate), placeholder: "00/00/0000", icon: UIImage(named: "calendar"))
    
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
    
    @objc private func didTapClose() {
        delegate?.closeModal()
    }
    
    @objc
    private func didTapSaveTransaction() {
        let inputs = [transactionTitleTextField, categoryPickerView, moneyTextField, dateTextField]
    
        let invalids = inputs.filter { !$0.textField.hasText }
        
        let isTransactionTypeError = incomeSelectorButton.variant != .selected && expenseSelectorButton.variant != .selected
    
        invalids.forEach { $0.setError(true) }
    
        guard invalids.isEmpty else { return }
        
        if isTransactionTypeError {
            delegate?.handleError(title: "addTransactionModal.alert.transactionType.title".localized, message: "addTransactionModal.alert.transactionType.description".localized)
        }
        
        let title = transactionTitleTextField.textField.text ?? ""
        let amount = moneyTextField.centsValue
        let date = dateTextField.textField.text ?? ""
        let rawValues    = categoryPickerView.pickerValues ?? []
        let selectedRow  = categoryPickerView.selectedPickerIndex
        let categoryKey  = rawValues.indices.contains(selectedRow)
        ? rawValues[selectedRow]
        : ""
        
        let typeEnum: TransactionType = incomeSelectorButton.variant == .selected
            ? .income
            : .expense
        let typeKey = String(describing: typeEnum)
        
        delegate?.sendTransactionData(title: title, amount: amount, date: date, category: categoryKey, transactionType: typeKey)
    }
}
