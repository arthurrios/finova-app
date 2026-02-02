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

    private var currentProgress: CGFloat = 0
    private var tapAction: (() -> Void)?

    // MARK: - Base Layer (Dark content - visible where progress hasn't reached)

    private lazy var darkContentView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var darkIconContainer: UIView = {
        let view = UIView()
        view.layer.cornerRadius = CornerRadius.medium
        view.backgroundColor = Colors.gray200
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.borderWidth = 1
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var darkIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.mainMagenta
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var darkTextStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var darkCategoryLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray700
        return label
    }()

    private lazy var darkValuesLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        return label
    }()

    private lazy var darkPercentageLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleMD.font
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Progress Layer (clips light content)

    private lazy var progressView: UIView = {
        let view = UIView()
        view.clipsToBounds = true
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var progressWidthConstraint: NSLayoutConstraint?

    // MARK: - Light Layer (White content - visible where progress has reached)

    private lazy var lightContentView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var lightIconContainer: UIView = {
        let view = UIView()
        view.layer.cornerRadius = CornerRadius.medium
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var lightIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var lightTextStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var lightCategoryLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = .white
        return label
    }()

    private lazy var lightValuesLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = .white.withAlphaComponent(0.85)
        return label
    }()

    private lazy var lightPercentageLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleMD.font
        label.textColor = .white
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Separator overlay (white separator on filled portion)

    private lazy var lightSeparatorView: UIView = {
        let view = UIView()
        view.backgroundColor = .white.withAlphaComponent(0.3)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Glass Effect Views

    private var glassEffectView: UIView?

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

        // Add dark content layer (base)
        contentView.addSubview(darkContentView)
        darkContentView.addSubview(darkIconContainer)
        darkIconContainer.addSubview(darkIconView)
        darkContentView.addSubview(darkTextStackView)
        darkTextStackView.addArrangedSubview(darkCategoryLabel)
        darkTextStackView.addArrangedSubview(darkValuesLabel)
        darkContentView.addSubview(darkPercentageLabel)

        // Add progress view (clips light content)
        contentView.addSubview(progressView)

        // Add light content inside progress view
        progressView.addSubview(lightContentView)
        progressView.addSubview(lightSeparatorView)
        lightContentView.addSubview(lightIconContainer)
        lightIconContainer.addSubview(lightIconView)
        lightContentView.addSubview(lightTextStackView)
        lightTextStackView.addArrangedSubview(lightCategoryLabel)
        lightTextStackView.addArrangedSubview(lightValuesLabel)
        lightContentView.addSubview(lightPercentageLabel)

        setupGlassEffect()
        setupConstraints()
    }

    private func setupGlassEffect() {
        #if swift(>=6.0)
        if #available(iOS 26.0, *) {
            setupLiquidGlassEffect()
            return
        }
        #endif

        setupFallbackGlassEffect()
    }

    private func setupLiquidGlassEffect() {
        // iOS 26 liquid glass - placeholder until SDK available
        let blurEffect = UIBlurEffect(style: .systemThinMaterialLight)
        let glassView = UIVisualEffectView(effect: blurEffect)
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.layer.cornerRadius = CornerRadius.medium
        glassView.clipsToBounds = true

        let tintView = UIView()
        tintView.backgroundColor = .white.withAlphaComponent(0.25)
        tintView.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(tintView)

        lightIconContainer.insertSubview(glassView, at: 0)
        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: lightIconContainer.topAnchor),
            glassView.leadingAnchor.constraint(equalTo: lightIconContainer.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: lightIconContainer.trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: lightIconContainer.bottomAnchor),

            tintView.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
            tintView.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor),
            tintView.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor)
        ])

        glassEffectView = glassView
        lightIconContainer.backgroundColor = .clear
    }

    private func setupFallbackGlassEffect() {
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialLight)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = CornerRadius.medium
        blurView.clipsToBounds = true

        lightIconContainer.insertSubview(blurView, at: 0)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: lightIconContainer.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: lightIconContainer.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: lightIconContainer.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: lightIconContainer.bottomAnchor)
        ])

        glassEffectView = blurView
        lightIconContainer.backgroundColor = .white.withAlphaComponent(0.3)
    }

    private func setupConstraints() {
        // Dark content fills the cell
        NSLayoutConstraint.activate([
            darkContentView.topAnchor.constraint(equalTo: contentView.topAnchor),
            darkContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            darkContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            darkContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // Dark icon container - centered vertically
        NSLayoutConstraint.activate([
            darkIconContainer.leadingAnchor.constraint(equalTo: darkContentView.leadingAnchor, constant: Metrics.spacing5),
            darkIconContainer.centerYAnchor.constraint(equalTo: darkContentView.centerYAnchor),
            darkIconContainer.widthAnchor.constraint(equalToConstant: Metrics.spacing8),
            darkIconContainer.heightAnchor.constraint(equalToConstant: Metrics.spacing8),

            darkIconView.centerXAnchor.constraint(equalTo: darkIconContainer.centerXAnchor),
            darkIconView.centerYAnchor.constraint(equalTo: darkIconContainer.centerYAnchor),
            darkIconView.widthAnchor.constraint(equalToConstant: Metrics.spacing5),
            darkIconView.heightAnchor.constraint(equalToConstant: Metrics.spacing5),
        ])

        // Dark text stack - centered vertically with icon
        NSLayoutConstraint.activate([
            darkTextStackView.leadingAnchor.constraint(equalTo: darkIconContainer.trailingAnchor, constant: Metrics.spacing3),
            darkTextStackView.centerYAnchor.constraint(equalTo: darkContentView.centerYAnchor),
            darkTextStackView.trailingAnchor.constraint(lessThanOrEqualTo: darkPercentageLabel.leadingAnchor, constant: -Metrics.spacing3),

            darkPercentageLabel.trailingAnchor.constraint(equalTo: darkContentView.trailingAnchor, constant: -Metrics.spacing5),
            darkPercentageLabel.centerYAnchor.constraint(equalTo: darkContentView.centerYAnchor),
            darkPercentageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
        ])

        // Progress view - full cell height, no padding
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: contentView.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            progressView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        progressWidthConstraint = progressView.widthAnchor.constraint(equalToConstant: 0)
        progressWidthConstraint?.isActive = true

        // Light content - aligned with cell bounds
        NSLayoutConstraint.activate([
            lightContentView.topAnchor.constraint(equalTo: contentView.topAnchor),
            lightContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            lightContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            lightContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // Light separator at bottom of progress view
        NSLayoutConstraint.activate([
            lightSeparatorView.leadingAnchor.constraint(equalTo: progressView.leadingAnchor),
            lightSeparatorView.trailingAnchor.constraint(equalTo: progressView.trailingAnchor),
            lightSeparatorView.bottomAnchor.constraint(equalTo: progressView.bottomAnchor),
            lightSeparatorView.heightAnchor.constraint(equalToConstant: 1),
        ])

        // Light icon container - same position as dark
        NSLayoutConstraint.activate([
            lightIconContainer.leadingAnchor.constraint(equalTo: lightContentView.leadingAnchor, constant: Metrics.spacing5),
            lightIconContainer.centerYAnchor.constraint(equalTo: lightContentView.centerYAnchor),
            lightIconContainer.widthAnchor.constraint(equalToConstant: Metrics.spacing8),
            lightIconContainer.heightAnchor.constraint(equalToConstant: Metrics.spacing8),

            lightIconView.centerXAnchor.constraint(equalTo: lightIconContainer.centerXAnchor),
            lightIconView.centerYAnchor.constraint(equalTo: lightIconContainer.centerYAnchor),
            lightIconView.widthAnchor.constraint(equalToConstant: Metrics.spacing5),
            lightIconView.heightAnchor.constraint(equalToConstant: Metrics.spacing5),
        ])

        // Light text stack - same positions as dark
        NSLayoutConstraint.activate([
            lightTextStackView.leadingAnchor.constraint(equalTo: lightIconContainer.trailingAnchor, constant: Metrics.spacing3),
            lightTextStackView.centerYAnchor.constraint(equalTo: lightContentView.centerYAnchor),
            lightTextStackView.trailingAnchor.constraint(lessThanOrEqualTo: lightPercentageLabel.leadingAnchor, constant: -Metrics.spacing3),

            lightPercentageLabel.trailingAnchor.constraint(equalTo: lightContentView.trailingAnchor, constant: -Metrics.spacing5),
            lightPercentageLabel.centerYAnchor.constraint(equalTo: lightContentView.centerYAnchor),
            lightPercentageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
        ])
    }

    // MARK: - Configuration

    func configure(with allocation: BudgetAllocation) {
        // Set icon (same image for both layers)
        let iconName = allocation.category.iconName(for: .expense)
        let icon = UIImage(named: iconName)
        darkIconView.image = icon
        lightIconView.image = icon

        // Set category name
        darkCategoryLabel.text = allocation.category.displayName
        lightCategoryLabel.text = allocation.category.displayName

        // Set values with compact currency
        let valuesText = String(
            format: "%@ / %@",
            compactCurrency(allocation.usedAmount),
            compactCurrency(allocation.allocatedAmount)
        )
        darkValuesLabel.text = valuesText
        lightValuesLabel.text = valuesText

        // Set percentage
        let percentage = Int(allocation.usagePercentage)
        let percentageText = "\(percentage)%"
        darkPercentageLabel.text = percentageText
        lightPercentageLabel.text = percentageText

        // Set colors based on status
        let statusColor = allocation.status.color
        darkPercentageLabel.textColor = statusColor
        progressView.backgroundColor = statusColor

        // Calculate progress (capped at 100% for visual)
        currentProgress = min(CGFloat(allocation.usagePercentage) / 100.0, 1.0)

        // Update progress after layout
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Calculate progress width (full cell width)
        let availableWidth = contentView.bounds.width
        let progressWidth = availableWidth * currentProgress

        progressWidthConstraint?.constant = progressWidth
    }

    // MARK: - Helpers

    private func compactCurrency(_ amount: Int) -> String {
        let absAmount = abs(amount)
        let prefix = amount < 0 ? "-" : ""

        if absAmount >= 1_000_000_00 {
            let millions = Double(absAmount) / 1_000_000_00
            return "\(prefix)R$ \(String(format: "%.1f", millions)) mi"
        } else if absAmount >= 100_000_00 {
            let thousands = Double(absAmount) / 1_000_00
            return "\(prefix)R$ \(String(format: "%.0f", thousands)) mil"
        } else if absAmount >= 1_000_00 {
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
            self.contentView.backgroundColor = Colors.lowMagenta
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 0.3) {
                self.contentView.backgroundColor = Colors.gray100
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        progressWidthConstraint?.constant = 0
        currentProgress = 0
        tapAction = nil
        contentView.gestureRecognizers?.forEach { contentView.removeGestureRecognizer($0) }
    }
}
