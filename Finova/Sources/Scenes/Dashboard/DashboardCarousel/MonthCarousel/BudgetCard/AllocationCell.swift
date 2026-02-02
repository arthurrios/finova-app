//
//  AllocationCell.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import UIKit

final class AllocationCell: UITableViewCell {

    static let reuseIdentifier = "AllocationCell"

    // MARK: - UI Components

    private lazy var iconContainerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = CornerRadius.medium
        view.backgroundColor = Colors.gray200
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.borderWidth = 1
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var categoryIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.mainMagenta
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var topRowStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fill
        return stack
    }()

    private lazy var categoryLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray700
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }()

    private lazy var statusBadge: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textAlignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private lazy var valuesLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        return label
    }()

    private lazy var progressBarContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var progressBarFill: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 2
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var progressWidthConstraint: NSLayoutConstraint?

    // MARK: - Tap Handling

    private var tapAction: (() -> Void)?

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

        contentView.addSubview(iconContainerView)
        iconContainerView.addSubview(categoryIconView)
        contentView.addSubview(contentStackView)

        topRowStackView.addArrangedSubview(categoryLabel)
        topRowStackView.addArrangedSubview(statusBadge)

        contentStackView.addArrangedSubview(topRowStackView)
        contentStackView.addArrangedSubview(valuesLabel)
        contentStackView.addArrangedSubview(progressBarContainer)

        progressBarContainer.addSubview(progressBarFill)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            iconContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing5),
            iconContainerView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconContainerView.widthAnchor.constraint(equalToConstant: Metrics.spacing8),
            iconContainerView.heightAnchor.constraint(equalToConstant: Metrics.spacing8),

            categoryIconView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            categoryIconView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            categoryIconView.widthAnchor.constraint(equalToConstant: Metrics.spacing5),
            categoryIconView.heightAnchor.constraint(equalToConstant: Metrics.spacing5),

            contentStackView.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: Metrics.spacing4),
            contentStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing5),
            contentStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            progressBarContainer.heightAnchor.constraint(equalToConstant: 4),

            progressBarFill.leadingAnchor.constraint(equalTo: progressBarContainer.leadingAnchor),
            progressBarFill.topAnchor.constraint(equalTo: progressBarContainer.topAnchor),
            progressBarFill.bottomAnchor.constraint(equalTo: progressBarContainer.bottomAnchor),
        ])

        // Initial width constraint for progress
        progressWidthConstraint = progressBarFill.widthAnchor.constraint(equalToConstant: 0)
        progressWidthConstraint?.isActive = true
    }

    // MARK: - Configuration

    func configure(with allocation: BudgetAllocation) {
        // Use the expense icon since allocations track expenses
        let iconName = allocation.category.iconName(for: .expense)
        categoryIconView.image = UIImage(named: iconName)
        categoryLabel.text = allocation.category.displayName

        // Use compact currency formatting
        valuesLabel.text = String(
            format: "%@ / %@",
            compactCurrency(allocation.usedAmount),
            compactCurrency(allocation.allocatedAmount)
        )

        statusBadge.text = allocation.status.localizedLabel
        statusBadge.textColor = allocation.status.color

        // Progress bar
        progressBarFill.backgroundColor = allocation.status.color

        // Calculate progress percentage (capped at 100% for visual)
        let progress = min(CGFloat(allocation.usagePercentage) / 100.0, 1.0)

        // Update progress width after layout
        setNeedsLayout()
        layoutIfNeeded()

        let containerWidth = progressBarContainer.bounds.width
        progressWidthConstraint?.constant = containerWidth * progress
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Update progress bar width on layout changes
        if let constraint = progressWidthConstraint {
            let containerWidth = progressBarContainer.bounds.width
            if containerWidth > 0 && constraint.constant > containerWidth {
                constraint.constant = containerWidth
            }
        }
    }

    /// Formats currency with compact notation for large values
    private func compactCurrency(_ amount: Int) -> String {
        let absAmount = abs(amount)
        let prefix = amount < 0 ? "-" : ""

        if absAmount >= 1_000_000_00 { // 1 million (in cents)
            let millions = Double(absAmount) / 1_000_000_00
            return "\(prefix)R$ \(String(format: "%.1f", millions)) mi"
        } else if absAmount >= 100_000_00 { // 100k+ (in cents)
            let thousands = Double(absAmount) / 1_000_00
            return "\(prefix)R$ \(String(format: "%.0f", thousands)) mil"
        } else if absAmount >= 1_000_00 { // 1k+ (in cents)
            let thousands = Double(absAmount) / 1_000_00
            return "\(prefix)R$ \(String(format: "%.1f", thousands)) mil"
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
            self.backgroundColor = Colors.lowMagenta
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 0.3) {
                self.backgroundColor = .clear
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        progressWidthConstraint?.constant = 0
        tapAction = nil
    }
}
