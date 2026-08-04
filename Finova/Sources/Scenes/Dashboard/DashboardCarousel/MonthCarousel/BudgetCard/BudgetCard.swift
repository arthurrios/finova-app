//
//  BudgetCard.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import UIKit
import SwiftUI

final class BudgetCard: UIView {

    /// Accessibility identifiers for the two projection corner blocks. Named so layout tests can
    /// single them out from the header and footer stacks, which are also direct `UIStackView`
    /// subviews of this card.
    static let balanceBlockIdentifier = "budgetCard.balanceBlock"
    static let projectionBlockIdentifier = "budgetCard.projectionBlock"
    static let unallocatedValueIdentifier = "budgetCard.unallocatedValue"
    static let usedValueIdentifier = "budgetCard.usedValue"
    static let headlineValueIdentifier = "budgetCard.headlineValue"
    static let marginLabelIdentifier = "budgetCard.margin"
    static let noBudgetStateIdentifier = "budgetCard.noBudgetState"

    // MARK: - Properties

    private var allocations: [BudgetAllocation] = []
    private var unallocatedSummary: UnallocatedBudgetSummary?
    private var unallocatedSpending: [UnallocatedCategorySpending] = []
    weak var delegate: MonthCardFlipDelegate?
    private let gradientLayer = Colors.gradientBlack
    private var chartHostingController: UIViewController?
    private var currentMonthAnchor: Int = 0
    private var isValuesHidden: Bool = false
    private var projection: AllocationBalanceProjection?
    private var balanceBasis: BalanceBasis?
    private var currentUsedValue: Int?
    private var currentBudgetLimit: Int?

    /// The trailing block loses its third line on an open month, so its height follows the tense.
    /// 3 rows need 45pt, 4 need 58pt. Varying it is safe: the block declares only a top anchor, so
    /// it is not part of the chain that fixes the card's own height.
    private var projectionBlockHeight: NSLayoutConstraint?
    private enum ProjectionBlockHeight {
        static let withoutOutcome: CGFloat = 45
        static let withOutcome: CGFloat = 60
    }

    /// Which balance the leading block is showing, and the day it is anchored to.
    ///
    /// Both numbers on this card are end-of-period figures, so the caption has to name the day
    /// or "Balance" is ambiguous - the transaction face has the same problem and solves it the
    /// same way, with "Balance on the 31st".
    private struct BalanceBasis {
        let amount: Int
        /// Day of the displayed month the amount refers to.
        let dayOfMonth: Int
    }

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

    private lazy var hideValuesToggleContainer: UIView = {
        let container = UIView()
        container.backgroundColor = .clear
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = true

        container.addSubview(hideValuesIcon)
        NSLayoutConstraint.activate([
            hideValuesIcon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            hideValuesIcon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            hideValuesIcon.widthAnchor.constraint(equalToConstant: 24),
            hideValuesIcon.heightAnchor.constraint(equalToConstant: 24),

            container.widthAnchor.constraint(equalToConstant: 36),
            container.heightAnchor.constraint(equalToConstant: 36),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleHideValues))
        container.addGestureRecognizer(tap)

        return container
    }()

    private let hideValuesIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.gray100
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
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

    private let headerSeparator: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.opaqueWhite
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
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

    private lazy var unallocatedStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing2
        stack.alignment = .leading
        return stack
    }()

    private lazy var unallocatedTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray400
        return label
    }()

    private lazy var unallocatedValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray100
        label.accessibilityIdentifier = BudgetCard.unallocatedValueIdentifier
        return label
    }()

    private lazy var usedStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing2
        stack.alignment = .trailing
        return stack
    }()

    private lazy var usedTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        // Same word the transaction face uses for the same quantity.
        label.text = "monthCard.usedBudget".localized
        label.textColor = Colors.gray400
        return label
    }()

    private lazy var usedValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray100
        label.accessibilityIdentifier = BudgetCard.usedValueIdentifier
        return label
    }()

    // Projection blocks - occupy the empty top corners either side of the donut.
    // The donut is a circle inscribed in a 170pt square, so its top corners are dead space.
    private lazy var balanceBlock: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing1
        stack.alignment = .leading
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        // Backstop: nothing may bleed over the donut even if a future label is added.
        stack.clipsToBounds = true
        stack.accessibilityIdentifier = BudgetCard.balanceBlockIdentifier
        return stack
    }()

    private lazy var balanceTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.title2XS.font
        label.textColor = Colors.gray400
        return label
    }()

    private lazy var balanceValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray100
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        return label
    }()

    private lazy var projectionBlock: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing1
        stack.alignment = .trailing
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        // Backstop: nothing may bleed over the donut even if a future label is added.
        stack.clipsToBounds = true
        stack.accessibilityIdentifier = BudgetCard.projectionBlockIdentifier
        return stack
    }()

    private lazy var projectionTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.title2XS.font
        label.textColor = Colors.gray400
        label.textAlignment = .right
        return label
    }()

    private lazy var projectionValueLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = BudgetCard.headlineValueIdentifier
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray100
        label.textAlignment = .right
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        return label
    }()

    private lazy var projectionBar: SegmentedBarView = {
        let bar = SegmentedBarView()
        bar.trackTintColor = Colors.gray600
        bar.cornerRadius = 2.0
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    /// Net saved for the month - "R$3.9k saved" in green, "R$420 overspent" in red. Sits under the
    /// bar, which shows the same two quantities as proportions.
    private lazy var marginLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleXS.font
        label.textColor = Colors.gray400
        label.textAlignment = .right
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.accessibilityIdentifier = BudgetCard.marginLabelIdentifier
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
        view.accessibilityIdentifier = BudgetCard.noBudgetStateIdentifier
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
        setupNotificationObserver()
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
        headerHorizontalStackView.addArrangedSubview(hideValuesToggleContainer)
        headerHorizontalStackView.addArrangedSubview(flipBackButton)
        headerHorizontalStackView.addArrangedSubview(configButton)
        headerHorizontalStackView.setCustomSpacing(Metrics.spacing2, after: hideValuesToggleContainer)
        headerHorizontalStackView.setCustomSpacing(Metrics.spacing3, after: flipBackButton)

        // Footer setup - two columns: Remaining (potential savings), Saved (actual performance)
        unallocatedStackView.addArrangedSubview(unallocatedTextLabel)
        unallocatedStackView.addArrangedSubview(unallocatedValueLabel)

        usedStackView.addArrangedSubview(usedTextLabel)
        usedStackView.addArrangedSubview(usedValueLabel)

        footerStackView.addArrangedSubview(unallocatedStackView)
        footerStackView.addArrangedSubview(usedStackView)

        // Projection blocks setup - two corner columns flanking the donut
        balanceBlock.addArrangedSubview(balanceTextLabel)
        balanceBlock.addArrangedSubview(balanceValueLabel)

        projectionBlock.addArrangedSubview(projectionTextLabel)
        projectionBlock.addArrangedSubview(projectionValueLabel)
        projectionBlock.addArrangedSubview(projectionBar)
        projectionBlock.addArrangedSubview(marginLabel)

        addSubview(headerHorizontalStackView)
        addSubview(headerSeparator)
        addSubview(chartContainerView)
        addSubview(footerStackView)
        addSubview(progressBar)

        // Added last so they sit above the chart in z-order
        addSubview(balanceBlock)
        addSubview(projectionBlock)

        // No budget state setup
        noBudgetStackView.addArrangedSubview(noBudgetIconView)
        noBudgetStackView.addArrangedSubview(noBudgetLabel)
        noBudgetStackView.addArrangedSubview(defineBudgetButton)
        noBudgetStateView.addSubview(noBudgetStackView)
        addSubview(noBudgetStateView)

        setupConstraints()
    }

    private func setupConstraints() {
        // Chart preferred height - extends downward from separator, may overlap footer
        let chartPreferredHeight = chartContainerView.heightAnchor.constraint(equalToConstant: 170)
        chartPreferredHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            // Header
            headerHorizontalStackView.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.spacing6),
            headerHorizontalStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing6),
            headerHorizontalStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing6),

            // Separator - matches MonthBudgetCard spacing
            headerSeparator.topAnchor.constraint(equalTo: headerHorizontalStackView.bottomAnchor, constant: Metrics.spacing3),
            headerSeparator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing6),
            headerSeparator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing6),

            // Chart container - top-anchored below separator, extends downward (may overlap footer)
            chartContainerView.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor, constant: Metrics.spacing5),
            chartContainerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            chartContainerView.widthAnchor.constraint(equalTo: chartContainerView.heightAnchor),
            // Hard limit: don't extend past the progress bar
            chartContainerView.bottomAnchor.constraint(equalTo: progressBar.topAnchor, constant: -Metrics.spacing6),
            chartPreferredHeight,

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
            noBudgetStateView.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor),
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

            // Projection blocks - top corners, flanking the donut.
            //
            // The card has no external height constraint: its height is its own fitting size,
            // fixed by the required chain top -> header -> separator -> chart -> progressBar ->
            // bottom. These blocks must not join that chain, so they declare ONLY a top anchor
            // plus constant width/height. No bottom anchor, no relation to progressBar, and no
            // relation to chartContainerView (whose width == height, so a horizontal squeeze
            // there would make the chart shorter and shrink the card).
            //
            // The constant heights are load-bearing rather than defensive: Fonts.font returns a
            // UIFontMetrics-scaled font, so a content-sized block would grow with Dynamic Type.
            balanceBlock.topAnchor.constraint(
                equalTo: headerSeparator.bottomAnchor, constant: Metrics.spacing3),
            balanceBlock.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing6),
            // 72pt: at the narrowest card (343pt) this leaves ~5pt of clearance to the inscribed
            // donut, the same margin the previous 64pt/58pt block had. The trailing block afforded
            // it by losing a row - 3 rows fit in 45pt where 4 needed 58.
            balanceBlock.widthAnchor.constraint(equalToConstant: 72),
            balanceBlock.heightAnchor.constraint(equalToConstant: 32),

            projectionBlock.topAnchor.constraint(
                equalTo: headerSeparator.bottomAnchor, constant: Metrics.spacing3),
            projectionBlock.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -Metrics.spacing6),
            projectionBlock.widthAnchor.constraint(equalToConstant: 64),

            projectionBar.heightAnchor.constraint(equalToConstant: 4),
            projectionBar.widthAnchor.constraint(equalTo: projectionBlock.widthAnchor),

            // Each label is pinned to its block's width. Without this the stacks' .leading /
            // .trailing alignment leaves the opposite edge free, so a label wider than the block
            // expands outwards past the block's bounds and over the donut. Pinning the width also
            // gives adjustsFontSizeToFitWidth a real width to shrink into.
            balanceTextLabel.widthAnchor.constraint(equalTo: balanceBlock.widthAnchor),
            balanceValueLabel.widthAnchor.constraint(equalTo: balanceBlock.widthAnchor),
            projectionTextLabel.widthAnchor.constraint(equalTo: projectionBlock.widthAnchor),
            projectionValueLabel.widthAnchor.constraint(equalTo: projectionBlock.widthAnchor),
            marginLabel.widthAnchor.constraint(equalTo: projectionBlock.widthAnchor),
        ])

        // 64pt is the widest the block can be at its taller setting without touching the inscribed
        // donut, so the width stays constant across tenses rather than resizing as months change.
        let height = projectionBlock.heightAnchor.constraint(
            equalToConstant: ProjectionBlockHeight.withOutcome)
        height.isActive = true
        projectionBlockHeight = height
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

    @objc private func toggleHideValues() {
        isValuesHidden.toggle()
        UserDefaultsManager.setHideValues(isValuesHidden)
        updateHideValuesIcon()
        updateValuesDisplay()

        // Notify delegate to update all other cards
        delegate?.didToggleBalanceVisibility(isValuesHidden)
    }

    private func updateHideValuesIcon() {
        let iconName = isValuesHidden ? "eye" : "eye-closed"
        hideValuesIcon.image = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate)
    }

    // MARK: - Balance Visibility

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBalanceVisibilityChanged),
            name: NSNotification.Name("BalanceVisibilityChanged"),
            object: nil
        )
    }

    @objc private func handleBalanceVisibilityChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let isHidden = userInfo["isHidden"] as? Bool
        else { return }

        if isHidden != isValuesHidden {
            isValuesHidden = isHidden
            updateHideValuesIcon()
            updateValuesDisplay()
        }
    }

    func updateBalanceVisibility(_ isHidden: Bool) {
        isValuesHidden = isHidden
        updateHideValuesIcon()
        updateValuesDisplay()
    }

    private func updateValuesDisplay() {
        // Ahead of the guard: the projection blocks have their own data and must still mask when
        // there is no unallocated summary, or they'd freeze at their pre-mask text.
        renderProjection()

        guard let summary = unallocatedSummary else { return }
        if isValuesHidden {
            unallocatedValueLabel.text = hiddenValueString
            unallocatedValueLabel.textColor = Colors.gray100
            usedValueLabel.text = hiddenValueString
            usedValueLabel.textColor = Colors.gray100
        } else {
            showBudgetMetrics(unallocatedSummary: summary)
        }
        // Re-embed chart to update center value visibility
        embedChart()
    }

    private var hiddenValueString: String { "••••••" }

    // MARK: - Configuration

    func configure(
        month: String,
        year: String,
        allocations: [BudgetAllocation],
        unallocatedSummary: UnallocatedBudgetSummary,
        unallocatedSpending: [UnallocatedCategorySpending],
        monthAnchor: Int,
        monthData: MonthBudgetCardType? = nil
    ) {
        self.allocations = allocations
        self.unallocatedSummary = unallocatedSummary
        self.unallocatedSpending = unallocatedSpending
        self.currentMonthAnchor = monthAnchor

        // Retained so `updateValuesDisplay()` can refresh the spend gauge and the footer without
        // `monthData` in scope.
        self.currentUsedValue = monthData?.usedValue
        self.currentBudgetLimit = monthData?.budgetLimit

        // The closing balance is meaningful for any month, so the leading block follows only the
        // ledger row's availability. A nil row hides it rather than rendering a zero, which would
        // read as a real balance of nothing.
        self.balanceBasis = monthData.flatMap { balanceBasis(for: $0, monthAnchor: monthAnchor) }

        // The trailing block reports a forecast while the month is open and what the allocations
        // actually consumed once it has closed - `base - unspentAllocations` would be a
        // counterfactual on a closed month.
        self.projection = balanceBasis.map {
            AllocationBalanceProjection(
                base: $0.amount,
                allocations: allocations,
                unallocatedSpending: unallocatedSummary.totalUsedInUnallocatedCategories,
                unallocatedHeadroom: unallocatedSummary.unallocatedAmount,
                tense: isPastMonth ? .actual : .projected
            )
        }

        // Header - matching MonthBudgetCard format with "/ " prefix on year
        monthLabel.text = month
        monthLabel.applyStyle()
        yearLabel.text = "/ " + year

        // Read initial hide values state
        isValuesHidden = UserDefaultsManager.getHideValues()
        updateHideValuesIcon()

        // Check if there is anything to show. Allocations alone are enough: a ledger can hold real
        // allocations with no budget total for the month (a group that never set one, or an
        // allocation created before the budget), and gating purely on the total threw away the
        // donut, the footer metrics and the projection blocks in favour of "define your budget".
        // The donut already treats a zero total as "no remaining slice" rather than dividing by it.
        let hasContent = unallocatedSummary.totalBudget > 0 || !allocations.isEmpty

        if hasContent {
            // Show chart and metrics
            showBudgetMetrics(unallocatedSummary: unallocatedSummary)
            if isValuesHidden {
                updateValuesDisplay()
            }
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

        // Footer slot 1 - Unallocated: budget cap not yet earmarked to any category. A plan-
        // structure number, deliberately not "left to spend": framing leftover budget as available
        // to spend nudges the opposite of what a budgeting app is for. Amber when negative, which is
        // the card's only warning that more has been allocated than the cap allows.
        let unallocated = unallocatedSummary.unallocatedAmount
        unallocatedTextLabel.text = "budget.unallocated".localized
        if unallocated >= 0 {
            unallocatedValueLabel.text = unallocated.currencyString
            unallocatedValueLabel.textColor = Colors.gray100
        } else {
            unallocatedValueLabel.text = "-" + abs(unallocated).currencyString
            unallocatedValueLabel.textColor = Colors.warningAmber
        }

        // Footer slot 2 - Used: everything spent this month, planned or not. Names the progress
        // bar's numerator directly above it, so the bar stops being an unlabelled graphic.
        usedValueLabel.text = (currentUsedValue ?? 0).currencyString
        usedValueLabel.textColor = Colors.gray100

        updateSpendGauge()

        // Projected end-of-month balance in the top corners
        renderProjection()

        // Embed donut chart
        embedChart()
    }

    private var isPastMonth: Bool {
        DateUtils.isPastMonth(date: Date.fromMonthAnchor(currentMonthAnchor))
    }

    /// The bottom bar is a spend gauge: how far through the month's budget the user actually is.
    ///
    /// It used to plot `totalAllocated / totalBudget` - allocation *coverage* - while the
    /// transaction face plots `usedValue / budgetLimit` through an identical 8pt magenta bar in the
    /// identical position. Flipping the card silently changed the bar's meaning, and a nearly-full
    /// bar read as "budget nearly spent" when it meant "budget nearly finished being planned".
    ///
    /// The denominator is `monthData.budgetLimit`, not `unallocatedSummary.totalBudget`: the
    /// summary is personal-scoped today while `usedValue` is scope-aware, so pairing them would
    /// render group spend over a personal budget - a meaningless ratio carrying status colours.
    private func updateSpendGauge() {
        guard let used = currentUsedValue, let limit = currentBudgetLimit, limit > 0 else {
            // Mirrors the transaction face, which hides its bar when no limit is set. The bar keeps
            // its required 8pt height, so the card's height chain is untouched.
            progressBar.isHidden = true
            return
        }

        progressBar.isHidden = false
        let rawFraction = Float(used) / Float(limit)
        progressBar.setProgress(min(max(rawFraction, 0), 1), animated: true)

        // Thresholds copied from MonthBudgetCard so both faces read alike. Set synchronously - a
        // deferred write can land after the next configure and paint a stale status colour, and
        // this card reconfigures on cell reuse and on .allocationDataChanged.
        if rawFraction > 1.0 {
            progressBar.progressTintColor = Colors.mainRed
        } else if rawFraction >= 0.75 {
            progressBar.progressTintColor = Colors.warningAmber
        } else {
            progressBar.progressTintColor = Colors.mainMagenta
        }
    }

    /// Resolves which balance to project from: always the month's closing balance.
    ///
    /// `BalanceDisplayMode` is deliberately not consulted. Its only writer - the balance toggle in
    /// `MonthBudgetCard` - is commented out, so `getBalanceDisplayMode()` can never return anything
    /// but `.final`; branching on it would be dead code pretending to be a feature. If that toggle
    /// is ever revived, this is the single place that has to learn about it.
    private func balanceBasis(
        for monthData: MonthBudgetCardType,
        monthAnchor: Int
    ) -> BalanceBasis? {
        guard let amount = monthData.finalBalance else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let monthDate = Date.fromMonthAnchor(monthAnchor)
        // `.count`, not `.upperBound` - the range is 1..<32 for a 31-day month.
        let lastDay = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 31

        return BalanceBasis(amount: amount, dayOfMonth: lastDay)
    }

    /// Renders the two corner blocks. Single formatting site for both the normal and masked paths.
    ///
    /// The blocks hide independently: the leading one needs only a ledger row, the trailing one
    /// needs an open month. Cells are reused, so every path must set `isHidden` explicitly.
    private func renderProjection() {
        // Leading block - the month's closing balance. Name the day, or "Balance" is ambiguous:
        // every figure on this card is end-of-period, not "right now".
        if let basis = balanceBasis {
            balanceBlock.isHidden = false
            balanceTextLabel.text = "budget.projection.byDay.format".localized(
                shortMonthDayString(day: basis.dayOfMonth))
            if isValuesHidden {
                balanceValueLabel.text = hiddenValueString
                balanceValueLabel.textColor = Colors.gray100
            } else {
                // Compact notation is mandatory: the blocks are 72pt wide, and a full
                // "R$ 12.345,67" cannot fit at any acceptable minimumScaleFactor.
                balanceValueLabel.text = signedCompactString(basis.amount)
                balanceValueLabel.textColor = basis.amount < 0 ? Colors.brightRed : Colors.gray100
            }
        } else {
            balanceBlock.isHidden = true
        }

        // Trailing block - the projection. Absent on closed months.
        guard let projection else {
            projectionBlock.isHidden = true
            return
        }
        projectionBlock.isHidden = false

        // The two corner blocks bracket one outcome rather than reporting two unrelated balances:
        // the leading one is the balance if nothing more is drawn from the plan, this one is the
        // balance if all of it is. The truth lands between, and the gap closes on its own - as the
        // month fills in, `unspentAllocations` falls to zero and the two converge on the real
        // closing balance. There is no room for a connector between them with the donut in the way,
        // so the caption carries the assumption instead of describing the result.
        //
        // A closed month holds what the allocations actually consumed - a spend figure, not a
        // second balance - so it keeps its own caption.
        let isActual = projection.tense == .actual
        projectionTextLabel.text = isActual
            ? "budget.projection.budgetUsed.label".localized
            : "budget.projection.afterBudget.label".localized

        // Of what was spent, how much stayed inside its allocation. Proportions, not amounts, so
        // the bar survives value-hiding; before anything is spent both shares are zero and the
        // bare grey track shows through.
        let shares = projection.barShares
        projectionBar.setSegments([
            SegmentedBarView.Segment(share: shares.withinPlan, color: Colors.brightGreen),
            SegmentedBarView.Segment(share: shares.beyondPlan, color: Colors.brightRed),
        ])
        guard !isValuesHidden else {
            projectionValueLabel.text = hiddenValueString
            projectionValueLabel.textColor = Colors.gray100
            marginLabel.text = hiddenValueString
            marginLabel.textColor = Colors.gray400
            return
        }

        projectionValueLabel.text = signedCompactString(projection.headlineAmount)

        // The figure under the bar is the month's realised outcome, so it only appears once the
        // month has closed. Mid-month it would be reporting an overspend the user may yet absorb,
        // and the allocations header carries that amount instead.
        let outcome = renderPlanOutcome(projection)
        marginLabel.isHidden = !isActual
        projectionBlockHeight?.constant = isActual
            ? ProjectionBlockHeight.withOutcome
            : ProjectionBlockHeight.withoutOutcome

        // Red on either of two independent problems, green only when neither holds:
        //
        //   net negative        the month let more slip than it kept
        //   balance negative    the plan runs the account past zero
        //
        // Deliberately not "anything broke its plan" - a month can leak R$180 and still come out
        // well ahead - and deliberately not the sign of the headline's own digits either, which is
        // what it used to be. `isOverCommitted` is already "projected < 0 on an open month", and a
        // closed month's headline is a spend figure that cannot go negative, so it never fires there.
        let isBadNews = projection.netSaved < 0 || projection.isOverCommitted
        projectionValueLabel.textColor = isBadNews ? Colors.brightRed : Colors.brightGreen

        var spokenParts = [
            projectionTextLabel.text,
            projectionValueLabel.text,
            outcome.text,
        ].compactMap { $0 }

        // The bar carries no visible legend at this width, so spell its two sides out here.
        if projection.tense == .actual, projection.totalSaved > 0 {
            spokenParts.append(
                "budget.net.saved.format".localized(
                    projection.totalSaved.compactCurrencyString))
        }
        if projection.overspent > 0 {
            spokenParts.append(
                "budget.plan.over.format".localized(
                    projection.overspent.compactCurrencyString))
        }

        if projection.isOverCommitted {
            spokenParts.append(
                "budget.projection.overcommitted.format".localized(
                    projection.shortfall.compactCurrencyString))
        }
        projectionBlock.isAccessibilityElement = true
        projectionBlock.accessibilityLabel = spokenParts.joined(separator: ", ")
    }

    /// The block's single verdict: its wording, and whether the month has broken its plan.
    /// Both the headline and the figure under the bar are coloured from this, so they cannot
    /// contradict each other.
    private struct PlanOutcome {
        let text: String
        let isOverPlan: Bool
    }

    /// Renders the figure under the bar and returns the verdict the headline also uses.
    ///
    /// Tense-aware because "saved" is a realised quantity. While a month is open, an unspent
    /// allocation is money still earmarked for spending, so reporting it as kept would show a
    /// number that erodes as the month fills in - the open month reports plan adherence instead.
    /// Once the month closes, the unspent budget really was kept and becomes the outcome.
    private func renderPlanOutcome(_ projection: AllocationBalanceProjection) -> PlanOutcome {
        let text: String
        let isOverPlan: Bool

        switch projection.tense {
        case .projected:
            // Hidden on open months; kept in sync so a flip to a closed month never shows stale text.
            isOverPlan = projection.overspent > 0
            text = isOverPlan
                ? "budget.plan.over.format".localized(projection.overspent.compactCurrencyString)
                : "budget.plan.within.label".localized

        case .actual:
            let net = projection.netSaved
            isOverPlan = net < 0
            let format = isOverPlan ? "budget.net.overspent.format" : "budget.net.saved.format"
            text = format.localized(abs(net).compactCurrencyString)
        }

        marginLabel.text = text
        marginLabel.textColor = isOverPlan ? Colors.brightRed : Colors.brightGreen
        return PlanOutcome(text: text, isOverPlan: isOverPlan)
    }

    /// "Aug 31" - abbreviated month plus the localized day, short enough for a 72pt block.
    private func shortMonthDayString(day: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        let month = formatter.string(from: Date.fromMonthAnchor(currentMonthAnchor))
        return "\(month) \(day.localizedDayOfMonth)"
    }

    /// `compactCurrencyString` has no notion of sign, so negatives are prefixed here - matching
    /// how the footer labels already render an over-allocated Remaining value.
    private func signedCompactString(_ amount: Int) -> String {
        amount < 0
            ? "-" + abs(amount).compactCurrencyString
            : amount.compactCurrencyString
    }

    private func showNoBudgetState() {
        // Hide chart and metrics
        chartContainerView.isHidden = true
        footerStackView.isHidden = true
        progressBar.isHidden = true

        // Hide the projection blocks too - they'd float over the "define budget" empty state,
        // which is anchored to the same headerSeparator.bottom region.
        balanceBlock.isHidden = true
        projectionBlock.isHidden = true

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
            isValuesHidden: isValuesHidden,
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
