//
//  AdjustBalanceModalView.swift
//  Finova
//
//  Created by Arthur Rios on 09/02/26.
//

import UIKit

protocol AdjustBalanceModalViewDelegate: AnyObject {
    func didTapClose()
    func didTapConfirm(realBalanceCents: Int)
}

final class AdjustBalanceModalView: UIView {

    weak var delegate: AdjustBalanceModalViewDelegate?

    // MARK: - UI Components

    private lazy var contentStackView: UIStackView = {
        let sv = UIStackView(
            axis: .vertical, spacing: Metrics.spacing7, distribution: .fill,
            arrangedSubviews: [
                headerStackView, currentBalanceStackView, realBalanceStackView, separator, confirmButton
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

    private lazy var currentBalanceStackView = UIStackView(
        axis: .vertical, spacing: Metrics.spacing2,
        arrangedSubviews: [currentBalanceLabel, currentBalanceValueLabel])

    private lazy var realBalanceStackView = UIStackView(
        axis: .vertical, spacing: Metrics.spacing2,
        arrangedSubviews: [realBalanceLabel, realBalanceInput])

    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleXS
        label.textColor = Colors.gray700
        label.text = "adjustBalance.title".localized
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

    private let currentBalanceLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray400
        label.text = "adjustBalance.currentBalance".localized
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    private let currentBalanceValueLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.textColor = Colors.gray700
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    private let realBalanceLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray400
        label.text = "adjustBalance.realBalance".localized
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    private let realBalanceInput: Input = {
        let input = Input(type: .currency, placeholder: "0,00")
        return input
    }()

    let separator: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let confirmButton = Button(label: "adjustBalance.confirm".localized)

    // MARK: - Initialization

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
        confirmButton.addTarget(self, action: #selector(didTapConfirm), for: .touchUpInside)

        realBalanceInput.addDoneButtonToolbar()

        setupConstraints()
    }

    private func setupConstraints() {
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - Configuration

    func configure(currentBalance: Int) {
        currentBalanceValueLabel.text = currentBalance.currencyString
    }

    // MARK: - Actions

    @objc private func didTapClose() {
        delegate?.didTapClose()
    }

    @objc private func didTapConfirm() {
        let realBalance = realBalanceInput.centsValue
        delegate?.didTapConfirm(realBalanceCents: realBalance)
    }
}
