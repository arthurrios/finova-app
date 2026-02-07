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

    // Balance display properties
    private var isShowingBudgetedBalance: Bool = false
    private var finalBalance: Int = 0
    private var budgetedBalance: Int = 0
    private var savedAmount: Int = 0
    private var animatedBalanceHost: UIHostingController<AnimatedNumberLabel>?
    private var isValuesHidden: Bool = false


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

    // Balance section
    private lazy var balanceSectionView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var balanceHeaderStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var balanceLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray400
        label.text = "monthCard.availableBudget".localized
        return label
    }()

    private lazy var balanceToggleButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.setImage(UIImage(systemName: "arrow.left.arrow.right", withConfiguration: config), for: .normal)
        button.tintColor = Colors.gray400
        button.addTarget(self, action: #selector(toggleBalanceView), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 32)
        ])
        return button
    }()

    private lazy var balanceValueContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var balanceValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleLG.font
        label.textColor = Colors.gray100
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var savedIndicatorLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.brightGreen
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private lazy var chartContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
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

        // Balance section setup
        balanceHeaderStackView.addArrangedSubview(balanceLabel)
        balanceHeaderStackView.addArrangedSubview(UIView()) // Spacer
        balanceHeaderStackView.addArrangedSubview(balanceToggleButton)

        balanceValueContainer.addSubview(balanceValueLabel)
        balanceValueContainer.addSubview(savedIndicatorLabel)

        balanceSectionView.addSubview(balanceHeaderStackView)
        balanceSectionView.addSubview(balanceValueContainer)

        // Footer removed - values moved to allocation table header

        addSubview(headerHorizontalStackView)
        addSubview(balanceSectionView)
        addSubview(chartContainerView)
        addSubview(progressBar)

        // No budget state setup
        noBudgetStackView.addArrangedSubview(noBudgetIconView)
        noBudgetStackView.addArrangedSubview(noBudgetLabel)
        noBudgetStackView.addArrangedSubview(defineBudgetButton)
        noBudgetStateView.addSubview(noBudgetStackView)
        addSubview(noBudgetStateView)

        setupConstraints()
        setupAnimatedBalanceLabel()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Header
            headerHorizontalStackView.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.spacing6),
            headerHorizontalStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing6),
            headerHorizontalStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing6),

            // Balance section - below header
            balanceSectionView.topAnchor.constraint(equalTo: headerHorizontalStackView.bottomAnchor, constant: Metrics.spacing4),
            balanceSectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing6),
            balanceSectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing6),

            balanceHeaderStackView.topAnchor.constraint(equalTo: balanceSectionView.topAnchor),
            balanceHeaderStackView.leadingAnchor.constraint(equalTo: balanceSectionView.leadingAnchor),
            balanceHeaderStackView.trailingAnchor.constraint(equalTo: balanceSectionView.trailingAnchor),

            balanceValueContainer.topAnchor.constraint(equalTo: balanceHeaderStackView.bottomAnchor, constant: Metrics.spacing1),
            balanceValueContainer.leadingAnchor.constraint(equalTo: balanceSectionView.leadingAnchor),
            balanceValueContainer.trailingAnchor.constraint(equalTo: balanceSectionView.trailingAnchor),
            balanceValueContainer.bottomAnchor.constraint(equalTo: balanceSectionView.bottomAnchor),
            balanceValueContainer.heightAnchor.constraint(equalToConstant: 36),

            balanceValueLabel.leadingAnchor.constraint(equalTo: balanceValueContainer.leadingAnchor),
            balanceValueLabel.centerYAnchor.constraint(equalTo: balanceValueContainer.centerYAnchor),

            savedIndicatorLabel.trailingAnchor.constraint(equalTo: balanceValueContainer.trailingAnchor),
            savedIndicatorLabel.centerYAnchor.constraint(equalTo: balanceValueContainer.centerYAnchor),

            // Chart container - between balance section and progress bar
            chartContainerView.topAnchor.constraint(equalTo: balanceSectionView.bottomAnchor, constant: Metrics.spacing3),
            chartContainerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            chartContainerView.bottomAnchor.constraint(equalTo: progressBar.topAnchor, constant: -Metrics.spacing6),
            chartContainerView.widthAnchor.constraint(equalTo: chartContainerView.heightAnchor),
            // Minimum size for the chart to ensure it's big enough
            chartContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),

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
        monthAnchor: Int,
        cumulativeBalance: Int
    ) {
        self.allocations = allocations
        self.unallocatedSummary = unallocatedSummary
        self.unallocatedSpending = unallocatedSpending
        self.currentMonthAnchor = monthAnchor
        self.isValuesHidden = UserDefaultsManager.getHideValues()

        // Calculate remaining allocations (positive values only - money that can still be saved)
        let remainingAllocations = allocations.reduce(0) { total, allocation in
            let remaining = allocation.allocatedAmount - allocation.usedAmount
            return total + max(0, remaining)
        }

        // Calculate net saved amount (can be negative if overspent in some categories)
        // This is the sum of (allocated - used) for ALL allocations, including overspending
        self.savedAmount = allocations.reduce(0) { $0 + ($1.allocatedAmount - $1.usedAmount) }

        // Final Balance = cumulative balance + remaining allocations
        // Shows: "Your balance if you don't spend the remaining allocations"
        self.finalBalance = cumulativeBalance + remainingAllocations

        // Budgeted Balance = cumulative balance (actual)
        // The saved indicator shows how much was saved/overspent vs allocations
        self.budgetedBalance = cumulativeBalance

        // Header - matching MonthBudgetCard format with "/ " prefix on year
        monthLabel.text = month
        monthLabel.applyStyle()
        yearLabel.text = "/ " + year

        // Check if budget is set
        let hasBudget = unallocatedSummary.totalBudget > 0

        if hasBudget {
            // Show chart and metrics
            showBudgetMetrics(unallocatedSummary: unallocatedSummary)
            updateBalanceDisplay()
        } else {
            // Show "define budget" state
            showNoBudgetState()
        }
    }

    private func showBudgetMetrics(unallocatedSummary: UnallocatedBudgetSummary) {
        // Hide no budget state
        noBudgetStateView.isHidden = true

        // Show balance section, chart and progress bar
        balanceSectionView.isHidden = false
        chartContainerView.isHidden = false
        progressBar.isHidden = false

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
        // Hide balance section, chart and progress bar
        balanceSectionView.isHidden = true
        chartContainerView.isHidden = true
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
            totalBudget: unallocatedSummary?.totalBudget ?? 0,
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

    // MARK: - Balance Display

    private func setupAnimatedBalanceLabel() {
        let balanceView = AnimatedNumberLabel(
            value: finalBalance,
            font: Fonts.titleLG.font,
            color: Colors.gray100,
            currencyCode: AppConfig.currencyCode
        )

        let hostingController = UIHostingController(rootView: balanceView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        balanceValueContainer.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: balanceValueContainer.leadingAnchor),
            hostingController.view.centerYAnchor.constraint(equalTo: balanceValueContainer.centerYAnchor)
        ])

        animatedBalanceHost = hostingController

        // Hide the static label since we're using animated
        balanceValueLabel.isHidden = true
    }

    @objc private func toggleBalanceView() {
        isShowingBudgetedBalance.toggle()
        updateBalanceDisplay()
    }

    private func updateBalanceDisplay() {
        if isShowingBudgetedBalance {
            // Show Budgeted Balance (actual cumulative balance)
            // Saved indicator shows net savings vs allocations (+/-)
            balanceLabel.text = "budget.balance.budgeted".localized

            // Update animated label
            if let host = animatedBalanceHost {
                host.rootView = AnimatedNumberLabel(
                    value: isValuesHidden ? 0 : budgetedBalance,
                    font: Fonts.titleLG.font,
                    color: Colors.gray100,
                    currencyCode: AppConfig.currencyCode
                )
            }

            // Show saved indicator
            if !isValuesHidden {
                savedIndicatorLabel.isHidden = false
                if savedAmount >= 0 {
                    savedIndicatorLabel.text = "+\(savedAmount.currencyString)"
                    savedIndicatorLabel.textColor = Colors.brightGreen
                } else {
                    savedIndicatorLabel.text = savedAmount.currencyString
                    savedIndicatorLabel.textColor = Colors.brightRed
                }
            } else {
                savedIndicatorLabel.isHidden = true
            }
        } else {
            // Show Final Balance (projected - cumulative + remaining allocations)
            // This shows balance if remaining allocations are NOT spent
            balanceLabel.text = "monthCard.availableBudget".localized

            // Update animated label
            if let host = animatedBalanceHost {
                host.rootView = AnimatedNumberLabel(
                    value: isValuesHidden ? 0 : finalBalance,
                    font: Fonts.titleLG.font,
                    color: Colors.gray100,
                    currencyCode: AppConfig.currencyCode
                )
            }

            // Hide saved indicator in final balance view
            savedIndicatorLabel.isHidden = true
        }

        // Handle hidden values state
        if isValuesHidden {
            balanceValueLabel.text = "****"
            balanceValueLabel.isHidden = false
            animatedBalanceHost?.view.isHidden = true
        } else {
            balanceValueLabel.isHidden = true
            animatedBalanceHost?.view.isHidden = false
        }
    }
}
