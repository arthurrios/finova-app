//
//  EarlyPaymentInstallmentRow.swift
//  Finova
//

import UIKit

/// A single selectable installment: label + amount on the left, checkbox on the right.
///
/// A stack of these rather than a `UITableView`: an installment series is bounded (a handful of rows,
/// never more than a couple of dozen), and the surrounding screen already scrolls. A nested table
/// would mean computing and maintaining an explicit height constraint for no benefit.
final class EarlyPaymentInstallmentRow: UIView {
    var onTap: (() -> Void)?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let amountLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let checkbox: UIView = {
        let view = UIView()
        view.layer.cornerRadius = CornerRadius.small
        view.layer.borderWidth = 2
        view.layer.borderColor = Colors.gray400.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let checkmark: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "checkmark")?.withRenderingMode(.alwaysTemplate)
        imageView.tintColor = Colors.gray100
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    init() {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = true

        let textStack = UIStackView(arrangedSubviews: [titleLabel, amountLabel])
        textStack.axis = .vertical
        textStack.spacing = Metrics.spacing1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textStack)
        addSubview(checkbox)
        checkbox.addSubview(checkmark)

        NSLayoutConstraint.activate([
            // A fixed height, not a `>=` against the text: inside a stack view a plain UIView has no
            // intrinsic height, so an inequality alone leaves the row's height ambiguous. 56pt fits
            // the two-line label comfortably and keeps every row the same height.
            heightAnchor.constraint(equalToConstant: Metrics.buttonHeight + Metrics.spacing2),

            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            checkbox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkbox.widthAnchor.constraint(equalToConstant: 24),
            checkbox.heightAnchor.constraint(equalToConstant: 24),
            checkbox.leadingAnchor.constraint(
                greaterThanOrEqualTo: textStack.trailingAnchor, constant: Metrics.spacing3),

            checkmark.centerXAnchor.constraint(equalTo: checkbox.centerXAnchor),
            checkmark.centerYAnchor.constraint(equalTo: checkbox.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 14),
            checkmark.heightAnchor.constraint(equalToConstant: 14),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @objc private func tapped() { onTap?() }

    func configure(title: String, amount: Int?, isSelected: Bool) {
        titleLabel.text = title
        if let amount = amount {
            amountLabel.text = amount.currencyString
            amountLabel.isHidden = false
        } else {
            amountLabel.isHidden = true
        }
        setSelected(isSelected)
    }

    func setSelected(_ isSelected: Bool) {
        checkmark.isHidden = !isSelected
        checkbox.backgroundColor = isSelected ? Colors.mainMagenta : .clear
        checkbox.layer.borderColor =
            isSelected ? Colors.mainMagenta.cgColor : Colors.gray400.cgColor
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
    }
}
