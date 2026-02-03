//
//  AllocationCell.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import UIKit

final class AllocationCell: UITableViewCell {

    static let reuseIdentifier = "AllocationCell"

    // MARK: - Properties

    private var tapAction: (() -> Void)?

    // MARK: - UI Components

    private lazy var iconContainer: UIView = {
        let view = UIView()
        view.layer.cornerRadius = CornerRadius.medium
        view.backgroundColor = Colors.gray200
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.borderWidth = 1
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.mainMagenta
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var textStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var categoryLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray700
        return label
    }()

    private lazy var usageLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        return label
    }()

    private lazy var remainingStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var arrowImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var remainingLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textAlignment = .right
        return label
    }()

    // MARK: - Initialization

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = .clear
        contentView.backgroundColor = Colors.gray100
        selectionStyle = .none

        // Add content
        contentView.addSubview(iconContainer)
        iconContainer.addSubview(iconView)
        contentView.addSubview(textStackView)
        textStackView.addArrangedSubview(categoryLabel)
        textStackView.addArrangedSubview(usageLabel)
        contentView.addSubview(remainingStackView)
        remainingStackView.addArrangedSubview(arrowImageView)
        remainingStackView.addArrangedSubview(remainingLabel)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Icon container
            iconContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing5),
            iconContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: Metrics.spacing8),
            iconContainer.heightAnchor.constraint(equalToConstant: Metrics.spacing8),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.spacing5),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.spacing5),

            // Text stack
            textStackView.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: Metrics.spacing3),
            textStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStackView.trailingAnchor.constraint(lessThanOrEqualTo: remainingStackView.leadingAnchor, constant: -Metrics.spacing3),

            // Remaining amount with arrow
            remainingStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing5),
            remainingStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            arrowImageView.widthAnchor.constraint(equalToConstant: 16),
            arrowImageView.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    // MARK: - Configuration

    func configure(with allocation: BudgetAllocation) {
        // Reset to allocated style
        resetToAllocatedStyle()

        // Set icon
        let iconName = allocation.category.iconName(for: .expense)
        iconView.image = UIImage(named: iconName)

        // Set category name
        categoryLabel.text = allocation.category.displayName

        // Set spent / allocated below category name
        usageLabel.text = "\(compactCurrency(allocation.usedAmount)) / \(compactCurrency(allocation.allocatedAmount))"

        // Set remaining amount with arrow and color
        let remaining = allocation.remainingAmount
        let isPositive = remaining >= 0

        // Arrow image (up for positive/under budget, down for negative/over budget)
        let arrowName = isPositive ? "arrowUp" : "arrowDown"
        arrowImageView.image = UIImage(named: arrowName)?.withRenderingMode(.alwaysTemplate)

        // Arrow color based on remaining (green for positive, red for negative)
        arrowImageView.tintColor = isPositive ? Colors.mainGreen : Colors.mainRed
        // Value uses dark gray like transaction values
        remainingLabel.textColor = Colors.gray700
        remainingLabel.text = compactCurrency(abs(remaining))
    }

    func configure(with unallocatedSpending: UnallocatedCategorySpending) {
        // Apply unallocated style (grayed out)
        applyUnallocatedStyle()

        // Set icon (grayed out - darker for better visibility)
        let iconName = unallocatedSpending.category.iconName(for: .expense)
        iconView.image = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = Colors.gray500

        // Set category name
        categoryLabel.text = unallocatedSpending.category.displayName

        // Show "Unallocated" as subtitle
        usageLabel.text = "allocation.unallocated.label".localized

        // Show spent amount as deficit (red, down arrow)
        arrowImageView.image = UIImage(named: "arrowDown")?.withRenderingMode(.alwaysTemplate)
        arrowImageView.tintColor = Colors.mainRed
        remainingLabel.textColor = Colors.gray700
        remainingLabel.text = compactCurrency(unallocatedSpending.spentAmount)
    }

    private func resetToAllocatedStyle() {
        // Reset icon container to normal style
        iconContainer.backgroundColor = Colors.gray200
        iconContainer.layer.borderColor = Colors.gray300.cgColor
        iconView.tintColor = Colors.mainMagenta

        // Reset labels
        categoryLabel.textColor = Colors.gray700
        usageLabel.textColor = Colors.gray500
    }

    private func applyUnallocatedStyle() {
        // Gray out the icon container
        iconContainer.backgroundColor = Colors.gray200
        iconContainer.layer.borderColor = Colors.gray300.cgColor

        // Labels remain the same color but icon is grayed
        categoryLabel.textColor = Colors.gray700
        usageLabel.textColor = Colors.gray400  // Slightly more muted for "Unallocated"
    }

    // MARK: - Helpers

    private func compactCurrency(_ amount: Int) -> String {
        if amount >= 1_000_000_00 {
            let millions = Double(amount) / 1_000_000_00
            return "R$ \(String(format: "%.1f", millions)) mi"
        } else if amount >= 100_000_00 {
            let thousands = Double(amount) / 1_000_00
            return "R$ \(String(format: "%.0f", thousands)) mil"
        } else if amount >= 1_000_00 {
            let thousands = Double(amount) / 1_000_00
            return "R$ \(String(format: "%.1f", thousands)) mil"
        } else {
            return amount.currencyString
        }
    }

    func setTapAction(_ action: @escaping () -> Void) {
        self.tapAction = action
        let tap = UITapGestureRecognizer(target: self, action: #selector(cellTapped))
        contentView.addGestureRecognizer(tap)
    }

    @objc private func cellTapped() {
        tapAction?()
    }

    func highlight() {
        UIView.animate(withDuration: 0.2) {
            self.contentView.backgroundColor = Colors.lowMagenta
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 0.3) {
                self.contentView.backgroundColor = Colors.gray100
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        tapAction = nil
        contentView.gestureRecognizers?.forEach { contentView.removeGestureRecognizer($0) }
        resetToAllocatedStyle()
    }
}
