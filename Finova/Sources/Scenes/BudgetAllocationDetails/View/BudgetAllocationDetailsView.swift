//
//  BudgetAllocationDetailsView.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import UIKit

protocol BudgetAllocationDetailsViewDelegate: AnyObject {
    func didTapEdit()
    func didTapDelete()
    func didTapBack()
    func didTapTransaction(_ transaction: Transaction)
    func didRequestDeleteTransaction(_ transaction: Transaction, completion: @escaping (Bool) -> Void)
}

final class BudgetAllocationDetailsView: UIView {

    weak var delegate: BudgetAllocationDetailsViewDelegate?

    // MARK: - UI Components

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Header

    private let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight).isActive = true
        return view
    }()

    private let headerItemsView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing4, leading: Metrics.spacing5, bottom: Metrics.spacing5,
            trailing: Metrics.spacing5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private(set) lazy var backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false

        if #available(iOS 26.0, *) {
            button.tintColor = Colors.gray700
        } else {
            button.tintColor = Colors.gray500
        }

        return button
    }()

    private lazy var backButtonGlassContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    private lazy var headerTextStackView: UIStackView = {
        let stack = UIStackView(
            axis: .vertical, spacing: Metrics.spacing1,
            arrangedSubviews: [headerTitleLabel, headerSubtitleLabel])
        return stack
    }()

    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.textColor = Colors.gray700
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let headerSubtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Summary Section

    private lazy var summaryHeaderView = CardHeader(
        headerTitle: "allocation.details.summary.header".localized)

    private lazy var summaryContentView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.borderWidth = 1
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var summaryStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Metrics.spacing6
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var circularProgressView: CircularProgressView = {
        let view = CircularProgressView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var detailsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing3
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var allocatedValueLabel: UILabel!
    private var usedValueLabel: UILabel!
    private var remainingValueLabel: UILabel!

    private lazy var recurringBadge: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.lowMagenta
        view.layer.cornerRadius = CornerRadius.small
        view.layer.borderWidth = 1
        view.layer.borderColor = Colors.mainMagenta.cgColor
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var recurringBadgeStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Metrics.spacing1
        stack.alignment = .center
        stack.layoutMargins = UIEdgeInsets(
            top: Metrics.spacing1, left: Metrics.spacing2,
            bottom: Metrics.spacing1, right: Metrics.spacing2)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var recurringIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "reload")
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.mainMagenta
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var recurringLabel: UILabel = {
        let label = UILabel()
        label.text = "allocation.details.summary.recurring".localized
        label.font = Fonts.textXS.font
        label.textColor = Colors.mainMagenta
        return label
    }()

    private lazy var warningBanner: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.lowAmber
        view.layer.cornerRadius = CornerRadius.medium
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var warningStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Metrics.spacing2
        stack.alignment = .center
        stack.layoutMargins = UIEdgeInsets(
            top: Metrics.spacing3, left: Metrics.spacing4,
            bottom: Metrics.spacing3, right: Metrics.spacing4)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var warningIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "exclamationmark.triangle.fill")
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.warningAmber
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var warningLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.warningAmber
        label.numberOfLines = 0
        return label
    }()

    // MARK: - Transactions Section

    private lazy var transactionsHeaderView = CardHeader(
        headerTitle: "allocation.details.transactions.header".localized)

    private lazy var transactionsTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Colors.gray100
        tableView.layer.cornerRadius = CornerRadius.extraLarge
        tableView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        tableView.layer.borderWidth = 1
        tableView.layer.borderColor = Colors.gray300.cgColor
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets.zero
        tableView.clipsToBounds = true
        tableView.separatorColor = Colors.gray300
        tableView.isScrollEnabled = true  // Enable scrolling to allow swipe-to-delete
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(TransactionCell.self, forCellReuseIdentifier: TransactionCell.reuseID)
        tableView.dataSource = self
        tableView.delegate = self
        return tableView
    }()

    private var transactionsTableHeightConstraint: NSLayoutConstraint?
    private var transactionsTableMaxHeightConstraint: NSLayoutConstraint?
    private var transactions: [Transaction] = []
    private var summaryStackBottomConstraint: NSLayoutConstraint?
    private var warningBannerBottomConstraint: NSLayoutConstraint?

    /// Maximum height for transactions table to ensure it doesn't overlap with footer
    private let maxTransactionsTableHeight: CGFloat = 300

    private lazy var emptyStateView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        view.layer.borderWidth = 1
        view.layer.borderColor = Colors.gray300.cgColor
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var emptyIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "iconBankSlip")
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.gray400
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var emptyMessageLabel: UILabel = {
        let label = UILabel()
        label.text = "allocation.details.transactions.empty".localized
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Action Buttons

    private lazy var actionButtonsContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var footerBorderView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var actionButtonsStackView: UIStackView = {
        let stackView = UIStackView(
            axis: .vertical,
            spacing: Metrics.spacing3,
            arrangedSubviews: [editButton, deleteButton]
        )
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing4, leading: Metrics.spacing4, bottom: Metrics.spacing4,
            trailing: Metrics.spacing4)
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }()

    private lazy var editButton = Button(
        variant: .base,
        label: "allocation.details.action.edit".localized
    )

    private lazy var deleteButton = Button(
        variant: .outlined,
        label: "allocation.details.action.delete".localized
    )

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        backgroundColor = Colors.gray200

        // Header
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        setupBackButtonGlassEffect()
        headerItemsView.addSubview(headerTextStackView)

        // Scroll view
        addSubview(scrollView)
        scrollView.addSubview(contentView)

        // Summary section
        contentView.addSubview(summaryHeaderView)
        contentView.addSubview(summaryContentView)
        setupSummaryContent()

        // Transactions section
        contentView.addSubview(transactionsHeaderView)
        contentView.addSubview(transactionsTableView)
        contentView.addSubview(emptyStateView)
        setupEmptyState()

        // Action buttons
        addSubview(actionButtonsContainerView)
        actionButtonsContainerView.addSubview(footerBorderView)
        actionButtonsContainerView.addSubview(actionButtonsStackView)

        // Actions
        backButtonGlassContainer.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(didTapBack)))
        backButton.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)
        editButton.addTarget(self, action: #selector(didTapEdit), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(didTapDelete), for: .touchUpInside)

        setupConstraints()
    }

    private func setupBackButtonGlassEffect() {
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect()
            glassEffect.isInteractive = true
            let glassView = UIVisualEffectView(effect: glassEffect)
            glassView.translatesAutoresizingMaskIntoConstraints = false

            backButtonGlassContainer.insertSubview(glassView, at: 0)
            backButtonGlassContainer.layer.cornerRadius = 18
            backButtonGlassContainer.clipsToBounds = true

            NSLayoutConstraint.activate([
                glassView.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
                glassView.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
                glassView.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor)
            ])
        }
    }

    private func setupSummaryContent() {
        summaryContentView.addSubview(summaryStackView)
        summaryStackView.addArrangedSubview(circularProgressView)
        summaryStackView.addArrangedSubview(detailsStackView)

        // Add detail rows
        detailsStackView.addArrangedSubview(
            createDetailRow(title: "allocation.details.summary.allocated".localized, isAllocated: true))
        detailsStackView.addArrangedSubview(
            createDetailRow(title: "allocation.details.summary.used".localized, isUsed: true))
        detailsStackView.addArrangedSubview(
            createDetailRow(title: "allocation.details.summary.remaining".localized, isRemaining: true))

        // Recurring badge
        recurringBadge.addSubview(recurringBadgeStackView)
        recurringBadgeStackView.addArrangedSubview(recurringIcon)
        recurringBadgeStackView.addArrangedSubview(recurringLabel)
        detailsStackView.addArrangedSubview(recurringBadge)

        // Warning banner
        summaryContentView.addSubview(warningBanner)
        warningBanner.addSubview(warningStackView)
        warningStackView.addArrangedSubview(warningIcon)
        warningStackView.addArrangedSubview(warningLabel)

        // Summary stack constraints
        summaryStackBottomConstraint = summaryStackView.bottomAnchor.constraint(
            equalTo: summaryContentView.bottomAnchor, constant: -Metrics.spacing5)

        // Warning banner bottom constraint (inactive by default)
        warningBannerBottomConstraint = warningBanner.bottomAnchor.constraint(
            equalTo: summaryContentView.bottomAnchor, constant: -Metrics.spacing5)

        NSLayoutConstraint.activate([
            summaryStackView.topAnchor.constraint(equalTo: summaryContentView.topAnchor, constant: Metrics.spacing5),
            summaryStackView.leadingAnchor.constraint(equalTo: summaryContentView.leadingAnchor, constant: Metrics.spacing5),
            summaryStackView.trailingAnchor.constraint(equalTo: summaryContentView.trailingAnchor, constant: -Metrics.spacing5),

            circularProgressView.widthAnchor.constraint(equalToConstant: 120),
            circularProgressView.heightAnchor.constraint(equalToConstant: 120),

            recurringBadgeStackView.topAnchor.constraint(equalTo: recurringBadge.topAnchor),
            recurringBadgeStackView.leadingAnchor.constraint(equalTo: recurringBadge.leadingAnchor),
            recurringBadgeStackView.trailingAnchor.constraint(equalTo: recurringBadge.trailingAnchor),
            recurringBadgeStackView.bottomAnchor.constraint(equalTo: recurringBadge.bottomAnchor),

            recurringIcon.widthAnchor.constraint(equalToConstant: 14),
            recurringIcon.heightAnchor.constraint(equalToConstant: 14),

            warningBanner.topAnchor.constraint(equalTo: summaryStackView.bottomAnchor, constant: Metrics.spacing4),
            warningBanner.leadingAnchor.constraint(equalTo: summaryContentView.leadingAnchor, constant: Metrics.spacing5),
            warningBanner.trailingAnchor.constraint(equalTo: summaryContentView.trailingAnchor, constant: -Metrics.spacing5),

            warningStackView.topAnchor.constraint(equalTo: warningBanner.topAnchor),
            warningStackView.leadingAnchor.constraint(equalTo: warningBanner.leadingAnchor),
            warningStackView.trailingAnchor.constraint(equalTo: warningBanner.trailingAnchor),
            warningStackView.bottomAnchor.constraint(equalTo: warningBanner.bottomAnchor),

            warningIcon.widthAnchor.constraint(equalToConstant: 20),
            warningIcon.heightAnchor.constraint(equalToConstant: 20)
        ])

        // Default: warning banner hidden, so summary stack connects to bottom
        summaryStackBottomConstraint?.isActive = true
    }

    private func createDetailRow(
        title: String,
        isAllocated: Bool = false,
        isUsed: Bool = false,
        isRemaining: Bool = false
    ) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = Fonts.textSM.font
        titleLabel.textColor = Colors.gray500
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.font = Fonts.textSMBold.font
        valueLabel.textColor = Colors.gray700
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        // Store references
        if isAllocated {
            allocatedValueLabel = valueLabel
        } else if isUsed {
            usedValueLabel = valueLabel
        } else if isRemaining {
            remainingValueLabel = valueLabel
        }

        container.addSubview(titleLabel)
        container.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: Metrics.spacing3),

            container.heightAnchor.constraint(equalToConstant: 24)
        ])

        return container
    }

    private func setupEmptyState() {
        emptyStateView.addSubview(emptyIconView)
        emptyStateView.addSubview(emptyMessageLabel)

        NSLayoutConstraint.activate([
            emptyIconView.leadingAnchor.constraint(
                equalTo: emptyStateView.leadingAnchor, constant: Metrics.spacing5),
            emptyIconView.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor),
            emptyIconView.heightAnchor.constraint(equalToConstant: Metrics.spacing8),
            emptyIconView.widthAnchor.constraint(equalToConstant: Metrics.spacing8),

            emptyMessageLabel.leadingAnchor.constraint(
                equalTo: emptyIconView.trailingAnchor, constant: Metrics.spacing5),
            emptyMessageLabel.trailingAnchor.constraint(
                equalTo: emptyStateView.trailingAnchor, constant: -Metrics.spacing4),
            emptyMessageLabel.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor)
        ])
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Header
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

            backButtonGlassContainer.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
            backButtonGlassContainer.leadingAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
            backButtonGlassContainer.widthAnchor.constraint(equalToConstant: 36),
            backButtonGlassContainer.heightAnchor.constraint(equalToConstant: 36),

            backButton.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
            backButton.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
            backButton.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
            backButton.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),

            headerTextStackView.leadingAnchor.constraint(
                equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
            headerTextStackView.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),

            // Scroll view
            scrollView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionButtonsContainerView.topAnchor),

            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Summary section
            summaryHeaderView.topAnchor.constraint(
                equalTo: contentView.topAnchor, constant: Metrics.spacing4),
            summaryHeaderView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
            summaryHeaderView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),

            summaryContentView.topAnchor.constraint(equalTo: summaryHeaderView.bottomAnchor),
            summaryContentView.leadingAnchor.constraint(equalTo: summaryHeaderView.leadingAnchor),
            summaryContentView.trailingAnchor.constraint(equalTo: summaryHeaderView.trailingAnchor),

            // Transactions section
            transactionsHeaderView.topAnchor.constraint(
                equalTo: summaryContentView.bottomAnchor, constant: Metrics.spacing6),
            transactionsHeaderView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
            transactionsHeaderView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),

            transactionsTableView.topAnchor.constraint(equalTo: transactionsHeaderView.bottomAnchor),
            transactionsTableView.leadingAnchor.constraint(equalTo: transactionsHeaderView.leadingAnchor),
            transactionsTableView.trailingAnchor.constraint(equalTo: transactionsHeaderView.trailingAnchor),
            transactionsTableView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -Metrics.spacing4),

            emptyStateView.topAnchor.constraint(equalTo: transactionsHeaderView.bottomAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: transactionsHeaderView.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: transactionsHeaderView.trailingAnchor),
            emptyStateView.heightAnchor.constraint(equalToConstant: Metrics.tableEmptyViewHeight),

            // Action buttons container - extend to bottom of screen
            actionButtonsContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            actionButtonsContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionButtonsContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Footer border (top border like header has bottom border)
            footerBorderView.topAnchor.constraint(equalTo: actionButtonsContainerView.topAnchor),
            footerBorderView.leadingAnchor.constraint(equalTo: actionButtonsContainerView.leadingAnchor),
            footerBorderView.trailingAnchor.constraint(equalTo: actionButtonsContainerView.trailingAnchor),
            footerBorderView.heightAnchor.constraint(equalToConstant: 1),

            // Action buttons stack view - bottom respects safe area
            actionButtonsStackView.topAnchor.constraint(equalTo: footerBorderView.bottomAnchor),
            actionButtonsStackView.leadingAnchor.constraint(equalTo: actionButtonsContainerView.leadingAnchor),
            actionButtonsStackView.trailingAnchor.constraint(equalTo: actionButtonsContainerView.trailingAnchor),
            actionButtonsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
        ])

        // Setup dynamic table height constraint
        transactionsTableHeightConstraint = transactionsTableView.heightAnchor.constraint(equalToConstant: 0)
        transactionsTableHeightConstraint?.isActive = true
    }


    // MARK: - Configuration

    func configure(with viewModel: BudgetAllocationDetailsViewModel) {
        // Header
        headerTitleLabel.text = String(
            format: "allocation.details.title.format".localized,
            viewModel.category.displayName
        )
        headerTitleLabel.applyStyle()
        headerSubtitleLabel.text = viewModel.monthYearString

        // Circular progress
        circularProgressView.configure(
            percentage: viewModel.usagePercentage,
            status: viewModel.status
        )

        // Summary values
        allocatedValueLabel.text = viewModel.formattedAllocated
        usedValueLabel.text = viewModel.formattedUsed
        remainingValueLabel.text = viewModel.formattedRemaining

        // Color remaining based on status
        if viewModel.status == .overBudget {
            remainingValueLabel.textColor = Colors.mainRed
        } else {
            remainingValueLabel.textColor = Colors.gray700
        }

        // Recurring badge
        recurringBadge.isHidden = !viewModel.isRecurring

        // Warning banner
        if let warningMessage = viewModel.overBudgetWarningMessage {
            warningLabel.text = warningMessage
            warningBanner.isHidden = false
        } else {
            warningBanner.isHidden = true
        }

        // Update summary content bottom constraint based on warning banner visibility
        updateSummaryContentHeight()

        // Transactions
        transactions = viewModel.getFilteredTransactions()
        transactionsHeaderView.configure(
            headerTitle: "allocation.details.transactions.header".localized,
            itemsQuantity: "\(transactions.count)"
        )

        if transactions.isEmpty {
            transactionsTableView.isHidden = true
            emptyStateView.isHidden = false
            transactionsTableHeightConstraint?.constant = 0
        } else {
            transactionsTableView.isHidden = false
            emptyStateView.isHidden = true

            // Calculate table height (capped at max height)
            let cellHeight: CGFloat = 67
            let separatorHeight = CGFloat(max(0, transactions.count - 1)) * 1.0
            let contentHeight = CGFloat(transactions.count) * cellHeight + separatorHeight
            let finalHeight = min(contentHeight, maxTransactionsTableHeight)
            transactionsTableHeightConstraint?.constant = finalHeight

            // Enable scrolling only if content exceeds max height
            transactionsTableView.isScrollEnabled = contentHeight > maxTransactionsTableHeight

            transactionsTableView.reloadData()
        }
    }

    private func updateSummaryContentHeight() {
        // Toggle constraints based on warning banner visibility
        if warningBanner.isHidden {
            // Warning banner hidden: summary stack connects directly to bottom
            warningBannerBottomConstraint?.isActive = false
            summaryStackBottomConstraint?.isActive = true
        } else {
            // Warning banner visible: warning banner connects to bottom
            summaryStackBottomConstraint?.isActive = false
            warningBannerBottomConstraint?.isActive = true
        }

        // Force layout update after configuring
        summaryContentView.setNeedsLayout()
        summaryContentView.layoutIfNeeded()
    }

    // MARK: - Public Methods

    func refreshTransactions(with viewModel: BudgetAllocationDetailsViewModel) {
        // Refresh circular progress and summary values
        circularProgressView.configure(
            percentage: viewModel.usagePercentage,
            status: viewModel.status
        )

        usedValueLabel.text = viewModel.formattedUsed
        remainingValueLabel.text = viewModel.formattedRemaining

        // Color remaining based on status
        if viewModel.status == .overBudget {
            remainingValueLabel.textColor = Colors.mainRed
        } else {
            remainingValueLabel.textColor = Colors.gray700
        }

        // Warning banner
        if let warningMessage = viewModel.overBudgetWarningMessage {
            warningLabel.text = warningMessage
            warningBanner.isHidden = false
        } else {
            warningBanner.isHidden = true
        }

        updateSummaryContentHeight()

        // Refresh transactions list
        transactions = viewModel.getFilteredTransactions()
        transactionsHeaderView.configure(
            headerTitle: "allocation.details.transactions.header".localized,
            itemsQuantity: "\(transactions.count)"
        )

        if transactions.isEmpty {
            transactionsTableView.isHidden = true
            emptyStateView.isHidden = false
            transactionsTableHeightConstraint?.constant = 0
        } else {
            transactionsTableView.isHidden = false
            emptyStateView.isHidden = true

            // Calculate table height (capped at max height)
            let cellHeight: CGFloat = 67
            let separatorHeight = CGFloat(max(0, transactions.count - 1)) * 1.0
            let contentHeight = CGFloat(transactions.count) * cellHeight + separatorHeight
            let finalHeight = min(contentHeight, maxTransactionsTableHeight)
            transactionsTableHeightConstraint?.constant = finalHeight

            // Enable scrolling only if content exceeds max height
            transactionsTableView.isScrollEnabled = contentHeight > maxTransactionsTableHeight

            transactionsTableView.reloadData()
        }
    }

    // MARK: - Actions

    @objc private func didTapEdit() {
        delegate?.didTapEdit()
    }

    @objc private func didTapDelete() {
        delegate?.didTapDelete()
    }

    @objc private func didTapBack() {
        delegate?.didTapBack()
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension BudgetAllocationDetailsView: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return transactions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: TransactionCell.reuseID, for: indexPath) as! TransactionCell

        let transaction = transactions[indexPath.row]

        let configuration = TransactionCellConfiguration(
            category: transaction.category,
            title: transaction.title,
            date: transaction.date,
            value: transaction.amount,
            transactionType: transaction.type,
            transactionMode: transaction.mode,
            installmentNumber: transaction.installmentNumber,
            totalInstallments: transaction.totalInstallments
        )

        cell.configure(with: configuration)

        // Set up swipe-to-delete using the cell's custom pan gesture
        cell.onDelete = { [weak self] completion in
            self?.delegate?.didRequestDeleteTransaction(transaction, completion: completion)
        }

        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 67
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let transaction = transactions[indexPath.row]
        delegate?.didTapTransaction(transaction)
    }

}
