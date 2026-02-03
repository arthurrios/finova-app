//
//  BudgetCard.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import UIKit
import SwiftUI

final class BudgetCard: UIView {

    // MARK: - Properties

    private var allocations: [BudgetAllocation] = []
    private var unallocatedSummary: UnallocatedBudgetSummary?
    private var unallocatedSpending: [UnallocatedCategorySpending] = []
    weak var delegate: MonthCardFlipDelegate?
    private let gradientLayer = Colors.gradientBlack
    private var chartHostingController: UIViewController?
    private var currentMonthAnchor: Int = 0

    // MARK: - UI Components

    // Header - matching MonthBudgetCard style
    private lazy var headerHorizontalStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var headerDateStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Metrics.spacing2
        stack.alignment = .center
        return stack
    }()

    private lazy var monthLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.textColor = Colors.gray100
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()

    private lazy var yearLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleXS.font
        label.textColor = Colors.gray400
        return label
    }()

    private lazy var flipBackButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        button.setImage(UIImage(systemName: "creditcard.fill", withConfiguration: config), for: .normal)
        button.tintColor = Colors.gray100
        button.addTarget(self, action: #selector(flipBack), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var configButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "settingsIcon")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = Colors.gray100
        button.addTarget(self, action: #selector(configTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Metrics.spacing6),
            button.heightAnchor.constraint(equalToConstant: Metrics.spacing6)
        ])
        return button
    }()

    private lazy var chartContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // Footer - matching MonthBudgetCard style (two vertical stacks)
    private lazy var footerStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var allocatedStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing2
        return stack
    }()

    private lazy var allocatedTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.text = "budget.allocated.label".localized
        label.textColor = Colors.gray400
        return label
    }()

    private lazy var allocatedValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray100
        return label
    }()

    private lazy var remainingStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing2
        stack.alignment = .center
        return stack
    }()

    private lazy var remainingTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.text = "budget.remaining.label".localized
        label.textColor = Colors.gray400
        return label
    }()

    private lazy var remainingValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray100
        return label
    }()

    private lazy var savedStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing2
        stack.alignment = .trailing
        return stack
    }()

    private lazy var savedTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.text = "budget.saved.label".localized
        label.textColor = Colors.gray400
        return label
    }()

    private lazy var savedValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray100
        return label
    }()

    // Progress bar - edge to edge like MonthBudgetCard
    private lazy var progressBar: RoundedProgressBar = {
        let bar = RoundedProgressBar()
        bar.trackTintColor = Colors.gray600
        bar.progressTintColor = Colors.mainMagenta
        bar.cornerRadius = 4.0
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    // No budget state view
    private lazy var noBudgetStateView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private lazy var noBudgetStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Metrics.spacing4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var noBudgetIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "chart.pie")
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.gray500
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var noBudgetLabel: UILabel = {
        let label = UILabel()
        label.text = "budget.noBudget.message".localized
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray400
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var defineBudgetButton: Button = {
        let button = Button(variant: .outlined, label: "monthCard.defineBudget".localized)
        button.addTarget(self, action: #selector(defineBudgetTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        // Apply gradient background like MonthBudgetCard
        layer.insertSublayer(gradientLayer, at: 0)
        layer.cornerRadius = CornerRadius.extraLarge
        clipsToBounds = true

        // Set low content hugging/compression so this view adapts to MonthBudgetCard's size
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // Header setup - matching MonthBudgetCard
        headerDateStackView.addArrangedSubview(monthLabel)
        headerDateStackView.addArrangedSubview(yearLabel)

        headerHorizontalStackView.addArrangedSubview(headerDateStackView)
        headerHorizontalStackView.addArrangedSubview(UIView()) // Spacer
        headerHorizontalStackView.addArrangedSubview(flipBackButton)
        headerHorizontalStackView.addArrangedSubview(configButton)
        headerHorizontalStackView.setCustomSpacing(Metrics.spacing3, after: flipBackButton)

        // Footer setup - three columns: Allocated, Remaining, Saved
        allocatedStackView.addArrangedSubview(allocatedTextLabel)
        allocatedStackView.addArrangedSubview(allocatedValueLabel)

        remainingStackView.addArrangedSubview(remainingTextLabel)
        remainingStackView.addArrangedSubview(remainingValueLabel)

        savedStackView.addArrangedSubview(savedTextLabel)
        savedStackView.addArrangedSubview(savedValueLabel)

        footerStackView.addArrangedSubview(allocatedStackView)
        footerStackView.addArrangedSubview(remainingStackView)
        footerStackView.addArrangedSubview(savedStackView)

        addSubview(headerHorizontalStackView)
        addSubview(chartContainerView)
        addSubview(footerStackView)
        addSubview(progressBar)

        // No budget state setup
        noBudgetStackView.addArrangedSubview(noBudgetIconView)
        noBudgetStackView.addArrangedSubview(noBudgetLabel)
        noBudgetStackView.addArrangedSubview(defineBudgetButton)
        noBudgetStateView.addSubview(noBudgetStackView)
        addSubview(noBudgetStateView)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Header
            headerHorizontalStackView.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.spacing6),
            headerHorizontalStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing6),
            headerHorizontalStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing6),

            // Chart container - centered between header and footer with minimum size
            chartContainerView.topAnchor.constraint(equalTo: headerHorizontalStackView.bottomAnchor, constant: Metrics.spacing4),
            chartContainerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            chartContainerView.bottomAnchor.constraint(equalTo: footerStackView.topAnchor, constant: -Metrics.spacing4),
            chartContainerView.widthAnchor.constraint(equalTo: chartContainerView.heightAnchor),
            // Minimum size for the chart to ensure it's big enough
            chartContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),

            // Footer - above progress bar
            footerStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing6),
            footerStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing6),
            footerStackView.bottomAnchor.constraint(equalTo: progressBar.topAnchor, constant: -Metrics.spacing4),

            // Progress bar - edge to edge at bottom
            progressBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 8),

            // No budget state view - centered in the card
            noBudgetStateView.topAnchor.constraint(equalTo: headerHorizontalStackView.bottomAnchor),
            noBudgetStateView.leadingAnchor.constraint(equalTo: leadingAnchor),
            noBudgetStateView.trailingAnchor.constraint(equalTo: trailingAnchor),
            noBudgetStateView.bottomAnchor.constraint(equalTo: bottomAnchor),

            noBudgetStackView.centerXAnchor.constraint(equalTo: noBudgetStateView.centerXAnchor),
            noBudgetStackView.centerYAnchor.constraint(equalTo: noBudgetStateView.centerYAnchor),
            noBudgetStackView.leadingAnchor.constraint(
                greaterThanOrEqualTo: noBudgetStateView.leadingAnchor, constant: Metrics.spacing6),
            noBudgetStackView.trailingAnchor.constraint(
                lessThanOrEqualTo: noBudgetStateView.trailingAnchor, constant: -Metrics.spacing6),

            noBudgetIconView.widthAnchor.constraint(equalToConstant: 48),
            noBudgetIconView.heightAnchor.constraint(equalToConstant: 48),

            // Set budget button needs explicit width to prevent compression
            defineBudgetButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    @objc private func flipBack() {
        delegate?.didRequestFlip(isShowingBudgetView: false)
    }

    @objc private func configTapped() {
        delegate?.didTapBudgetsConfig(forMonth: currentMonthAnchor)
    }

    @objc private func defineBudgetTapped() {
        delegate?.didTapDefineBudget(forMonth: currentMonthAnchor)
    }

    // MARK: - Configuration

    func configure(
        month: String,
        year: String,
        allocations: [BudgetAllocation],
        unallocatedSummary: UnallocatedBudgetSummary,
        unallocatedSpending: [UnallocatedCategorySpending],
        monthAnchor: Int
    ) {
        self.allocations = allocations
        self.unallocatedSummary = unallocatedSummary
        self.unallocatedSpending = unallocatedSpending
        self.currentMonthAnchor = monthAnchor

        // Header - matching MonthBudgetCard format with "/ " prefix on year
        monthLabel.text = month
        monthLabel.applyStyle()
        yearLabel.text = "/ " + year

        // Check if budget is set
        let hasBudget = unallocatedSummary.totalBudget > 0

        if hasBudget {
            // Show chart and metrics
            showBudgetMetrics(unallocatedSummary: unallocatedSummary)
        } else {
            // Show "define budget" state
            showNoBudgetState()
        }
    }

    private func showBudgetMetrics(unallocatedSummary: UnallocatedBudgetSummary) {
        // Hide no budget state
        noBudgetStateView.isHidden = true

        // Show chart and metrics
        chartContainerView.isHidden = false
        footerStackView.isHidden = false
        progressBar.isHidden = false

        // Footer values - three columns:
        // 1. Allocated: how much budget is assigned to categories
        allocatedValueLabel.text = unallocatedSummary.totalAllocated.currencyString

        // 2. Remaining: unallocated budget (not assigned to any category)
        remainingValueLabel.text = unallocatedSummary.unallocatedAmount.currencyString
        remainingValueLabel.textColor = Colors.gray100

        // 3. Saved: net savings from actual spending (allocated remaining - unallocated spending)
        // Positive = under budget (money saved), Negative = over budget (overspent)
        let allocatedRemaining = allocations.reduce(0) { $0 + $1.remainingAmount }
        let netSaved = allocatedRemaining - unallocatedSummary.totalUsedInUnallocatedCategories

        if netSaved >= 0 {
            savedValueLabel.text = netSaved.currencyString
            savedValueLabel.textColor = Colors.brightGreen
        } else {
            savedValueLabel.text = "-" + abs(netSaved).currencyString
            savedValueLabel.textColor = Colors.brightRed
        }

        // Progress bar shows allocation progress
        let allocatedPercent = unallocatedSummary.totalBudget > 0
            ? Float(unallocatedSummary.totalAllocated) / Float(unallocatedSummary.totalBudget)
            : 0
        progressBar.setProgress(min(allocatedPercent, 1.0), animated: true)
        progressBar.progressTintColor = Colors.mainMagenta

        // Embed donut chart
        embedChart()
    }

    private func showNoBudgetState() {
        // Hide chart and metrics
        chartContainerView.isHidden = true
        footerStackView.isHidden = true
        progressBar.isHidden = true

        // Remove existing chart
        chartHostingController?.view.removeFromSuperview()
        chartHostingController = nil

        // Show no budget state
        noBudgetStateView.isHidden = false
    }

    private func embedChart() {
        // Remove existing chart if any
        chartHostingController?.view.removeFromSuperview()
        chartHostingController = nil

        guard #available(iOS 17.0, *) else { return }

        let chartView = BudgetDonutChartView(
            allocations: allocations,
            unallocatedAmount: unallocatedSummary?.unallocatedAmount ?? 0,
            unallocatedSpending: unallocatedSpending,
            onSegmentTapped: { [weak self] category in
                self?.delegate?.didSelectAllocationCategory(category)
            },
            onUnallocatedSpendingTapped: { [weak self] spending in
                self?.delegate?.didTapUnallocatedSpending(spending)
            }
        )

        let hostingController = UIHostingController(rootView: chartView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        chartContainerView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: chartContainerView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: chartContainerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: chartContainerView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: chartContainerView.bottomAnchor)
        ])

        chartHostingController = hostingController
    }
}
