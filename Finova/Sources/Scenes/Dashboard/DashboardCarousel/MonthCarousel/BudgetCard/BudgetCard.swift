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
    weak var delegate: MonthCardFlipDelegate?
    private let gradientLayer = Colors.gradientBlack
    private var chartHostingController: UIViewController?

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

    private lazy var percentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing2
        stack.alignment = .trailing
        return stack
    }()

    private lazy var percentTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.text = "budget.percent.label".localized
        label.textColor = Colors.gray400
        return label
    }()

    private lazy var percentValueLabel: UILabel = {
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

        // Footer setup - matching MonthBudgetCard
        allocatedStackView.addArrangedSubview(allocatedTextLabel)
        allocatedStackView.addArrangedSubview(allocatedValueLabel)

        percentStackView.addArrangedSubview(percentTextLabel)
        percentStackView.addArrangedSubview(percentValueLabel)

        footerStackView.addArrangedSubview(allocatedStackView)
        footerStackView.addArrangedSubview(percentStackView)

        addSubview(headerHorizontalStackView)
        addSubview(chartContainerView)
        addSubview(footerStackView)
        addSubview(progressBar)

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
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    @objc private func flipBack() {
        delegate?.didRequestFlip(isShowingBudgetView: false)
    }

    // MARK: - Configuration

    func configure(
        month: String,
        year: String,
        allocations: [BudgetAllocation],
        unallocatedSummary: UnallocatedBudgetSummary
    ) {
        self.allocations = allocations
        self.unallocatedSummary = unallocatedSummary

        // Header - matching MonthBudgetCard format with "/ " prefix on year
        monthLabel.text = month
        monthLabel.applyStyle()
        yearLabel.text = "/ " + year

        // Footer values
        allocatedValueLabel.text = unallocatedSummary.totalAllocated.currencyString

        let allocatedPercent = unallocatedSummary.totalBudget > 0
            ? Float(unallocatedSummary.totalAllocated) / Float(unallocatedSummary.totalBudget)
            : 0

        percentValueLabel.text = String(
            format: "budget.allocated.percent".localized,
            Int(allocatedPercent * 100)
        )

        // Progress bar
        progressBar.setProgress(min(allocatedPercent, 1.0), animated: true)

        if allocatedPercent > 1.0 {
            progressBar.progressTintColor = Colors.warningAmber
            percentValueLabel.textColor = Colors.warningAmber
        } else {
            progressBar.progressTintColor = Colors.mainMagenta
            percentValueLabel.textColor = Colors.gray100
        }

        // Embed donut chart
        embedChart()
    }

    private func embedChart() {
        // Remove existing chart if any
        chartHostingController?.view.removeFromSuperview()
        chartHostingController = nil

        guard #available(iOS 17.0, *) else { return }

        let chartView = BudgetDonutChartView(
            allocations: allocations,
            unallocatedAmount: unallocatedSummary?.unallocatedAmount ?? 0,
            onSegmentTapped: { [weak self] category in
                self?.delegate?.didSelectAllocationCategory(category)
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
