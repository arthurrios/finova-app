//
//  MonthCarouselCell.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation
import UIKit

protocol MonthCarouselCellDelegate: AnyObject {
    func monthCarouselCell(_ cell: MonthCarouselCell, didChangeSearchText text: String)
    func monthCarouselCellDidTapFilter(_ cell: MonthCarouselCell)
}

struct TransactionFilters: Equatable {
    var categories: Set<TransactionCategory> = []
    var types: Set<TransactionType> = []
    var modes: Set<TransactionMode> = []
    var startDay: Int? = nil
    var endDay: Int? = nil
    var totalDaysInMonth: Int = 31
    /// When true, uses global filter settings (ignores day range for cross-month consistency)
    var useGlobalFilter: Bool = true

    var isEmpty: Bool {
        let hasDayFilter = !useGlobalFilter &&
        startDay != nil && endDay != nil && !(startDay == 1 && endDay == totalDaysInMonth)
        return categories.isEmpty && types.isEmpty && modes.isEmpty && !hasDayFilter
    }

    mutating func clear() {
        categories.removeAll()
        types.removeAll()
        modes.removeAll()
        startDay = nil
        endDay = nil
        useGlobalFilter = true
    }

    /// Compares filter values only, ignoring totalDaysInMonth which varies by month
    func hasSameFilterValues(as other: TransactionFilters) -> Bool {
        return categories == other.categories &&
               types == other.types &&
               modes == other.modes &&
               startDay == other.startDay &&
               endDay == other.endDay &&
               useGlobalFilter == other.useGlobalFilter
    }

    /// Returns a copy of this filter without day range filters.
    /// Day range filters are date-specific and don't translate well across different months,
    /// so they should only apply to the month where the filter was originally set.
    func withoutDayFilter() -> TransactionFilters {
        var copy = self
        copy.startDay = nil
        copy.endDay = nil
        return copy
    }

    /// Returns true if this filter has a day range set (only applies when not using global filter)
    var hasDayFilter: Bool {
        return !useGlobalFilter && startDay != nil && endDay != nil && !(startDay == 1 && endDay == totalDaysInMonth)
    }
}

class MonthCarouselCell: UICollectionViewCell {
    static let reuseID = "MonthCarouselCell"

    weak var searchDelegate: MonthCarouselCellDelegate?

    // MARK: - Navigation Closures

    var onAllocationTapped: ((BudgetAllocation) -> Void)?
    var onUnallocatedSpendingTapped: ((UnallocatedCategorySpending) -> Void)?
    var onBudgetsConfigTapped: ((Int) -> Void)?
    var onDefineBudgetTapped: ((Int) -> Void)?
    var onBudgetViewStateChanged: ((Int, Bool) -> Void)?  // (monthAnchor, isShowingBudgetView)
    var onBalanceVisibilityToggled: ((Bool) -> Void)?

    // MARK: - Properties

    let monthCard = MonthBudgetCard()
    var transactions: [Transaction] = []
    var filteredTransactions: [Transaction] = []
    private var tableHeightConstraint: NSLayoutConstraint?
    private var allocationsTableHeightConstraint: NSLayoutConstraint?
    private var monthCardHeightConstraint: NSLayoutConstraint?
    private var originalMonthCardHeight: CGFloat = 0  // Stored once, never changes
    private var isSearchActive: Bool = false
    var currentFilters = TransactionFilters()
    private(set) var isShowingBudgetView = false
    private var currentAllocations: [BudgetAllocation] = []
    private var currentUnallocatedSpending: [UnallocatedCategorySpending] = []
    private(set) var currentMonthAnchor: Int = 0
    private let allocationService = BudgetAllocationService()
    private let tagService = AllocationTagService.shared

    private var tagBreakdown: AllocationTagBreakdown = .empty
    /// The tag the list and donut are filtered to, or nil. Cleared on reuse and clamped on every
    /// rebuild - a tag with no members in the newly shown month would otherwise filter the list to
    /// nothing with no chip left to clear it.
    private var selectedTagId: String?

    /// The rows the table actually shows. Precomputed rather than filtered inside the data source,
    /// which runs per row per layout pass.
    private var visibleAllocations: [BudgetAllocation] = []
    private var visibleUnallocatedSpending: [UnallocatedCategorySpending] = []

    /// Single source of truth for "how many rows are there", so the count badge, the table height and
    /// `numberOfRowsInSection` can never disagree.
    private var visibleRowCount: Int {
        visibleAllocations.count + visibleUnallocatedSpending.count
    }

    /// Resolves the displayed month's ledger row on demand, for the budget card's projected
    /// balance. Deliberately pull-based rather than a stored snapshot: while the budget face is
    /// showing, the dashboard refreshes its month data but skips `monthCard.refresh(with:)`, so
    /// anything cached here — or read off `monthCard` — would be stale exactly when the
    /// projection is on screen.
    var monthDataProvider: ((Int) -> MonthBudgetCardType?)?

    /// Live ledger row for the month this cell renders, or nil if unavailable.
    private var currentMonthData: MonthBudgetCardType? {
        monthDataProvider?(currentMonthAnchor)
    }

    /// Sets the month anchor for this cell (used for budget allocation operations)
    func setMonthAnchor(_ anchor: Int) {
        currentMonthAnchor = anchor
    }
    
    // MARK: - UI Components
    
    private let tableHeaderView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.heightAnchor.constraint(equalToConstant: Metrics.spacing11).isActive = true
        stackView.layer.cornerRadius = CornerRadius.extraLarge
        stackView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        stackView.backgroundColor = Colors.gray100
        stackView.layoutMargins = UIEdgeInsets(
            top: 0, left: Metrics.spacing5, bottom: 0, right: Metrics.spacing4)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.distribution = .equalSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let tableHeaderTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.title2XS
        label.textColor = Colors.gray500
        label.text = "transactions.header.title".localized
        label.applyStyle()
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let transactionsNumberContainerView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        stackView.layoutMargins = UIEdgeInsets(
            top: 0, left: Metrics.spacing2, bottom: 0, right: Metrics.spacing2)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.backgroundColor = Colors.gray300
        stackView.clipsToBounds = true
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let transactionNumberLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleXS.font
        label.textColor = Colors.gray600
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var searchContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var clearButton: UIButton = {
        let button = UIButton(type: .system)
        
        // Resize the image to be 30% smaller (70% of original size)
        if let originalImage = UIImage(named: "x") {
            let originalSize = Metrics.inputIconSize
            let scaledSize = originalSize * 0.8
            let newSize = CGSize(width: scaledSize, height: scaledSize)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
            originalImage.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            button.setImage(resizedImage?.withRenderingMode(.alwaysTemplate), for: .normal)
        }
        
        button.tintColor = Colors.gray600
        button.addTarget(self, action: #selector(clearButtonTapped), for: .touchUpInside)
        // Add padding for better touch target (icon size + padding on each side)
        let buttonSize = Metrics.inputIconSize + Metrics.spacing2 * 2
        button.frame = CGRect(x: 0, y: 0, width: buttonSize, height: buttonSize)
        button.imageView?.contentMode = .center
        return button
    }()
    
    lazy var searchInput: Input = {
        let input = Input(
            type: .normal,
            placeholder: "transactions.search.placeholder".localized,
            icon: UIImage(named: "search")?.withRenderingMode(.alwaysTemplate),
            iconPosition: .left
        )
        input.layer.backgroundColor = Colors.gray100.cgColor
        input.textField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        input.textField.returnKeyType = .search
        input.textField.delegate = self
        input.textField.rightView = clearButton
        input.textField.rightViewMode = .never
        input.translatesAutoresizingMaskIntoConstraints = false
        return input
    }()
    
    private lazy var filterButton: UIButton = {
        let button = UIButton(type: .system)
        let image = UIImage(named: "filter")?.withRenderingMode(.alwaysTemplate)
        button.setImage(image, for: .normal)
        button.tintColor = Colors.gray600
        button.backgroundColor = Colors.gray100
        button.layer.cornerRadius = Metrics.inputHeight / 2
        button.layer.borderWidth = 1
        button.layer.borderColor = Colors.gray300.cgColor
        button.addTarget(self, action: #selector(filterButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let emptyStateView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.borderWidth = 1
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let emptyStateIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "iconBankSlip")
        imageView.tintColor = Colors.gray400
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let emptyStateDescriptionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.text = "transactions.emptyState.description".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    lazy var transactionTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Colors.gray100
        tableView.layer.borderWidth = 1
        tableView.layer.borderColor = Colors.gray300.cgColor
        tableView.layer.cornerRadius = CornerRadius.extraLarge
        tableView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets.zero
        tableView.clipsToBounds = true
        tableView.separatorColor = Colors.gray300
        tableView.isHidden = true  // Start hidden, show only after data is configured
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        // Set lower priority so the table gets constrained instead of the card
        tableView.setContentHuggingPriority(.defaultLow, for: .vertical)
        tableView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        
        return tableView
    }()
    
    private(set) lazy var budgetCard: BudgetCard = {
        let card = BudgetCard()
        card.isHidden = true
        card.delegate = self
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }()

    // MARK: - Allocations Table Components

    private let allocationsTableHeaderView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.heightAnchor.constraint(equalToConstant: Metrics.spacing11).isActive = true
        stackView.layer.cornerRadius = CornerRadius.extraLarge
        stackView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        stackView.backgroundColor = Colors.gray100
        stackView.layoutMargins = UIEdgeInsets(
            top: 0, left: Metrics.spacing5, bottom: 0, right: Metrics.spacing4)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.distribution = .equalSpacing
        stackView.isHidden = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    /// Per-tag subtotals and the list filter. A sibling between the header and the table, not part of
    /// either: the header's 44pt height constraint is activated inline above with no stored reference,
    /// so it can never be made taller.
    private lazy var allocationTagStripView: AllocationTagStripView = {
        let view = AllocationTagStripView()
        view.delegate = self
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Stored, deliberately unlike the header's, because it has to collapse to zero when a month has no
    /// tag arcs. `isHidden` alone leaves a view that owns a height constraint occupying its height, so
    /// the table would simply sit 44pt lower behind an empty band.
    private var tagStripHeightConstraint: NSLayoutConstraint?

    private let allocationsHeaderTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.title2XS
        label.textColor = Colors.gray500
        label.text = "budget.allocations.title".localized
        label.applyStyle()
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let allocationsNumberContainerView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        stackView.layoutMargins = UIEdgeInsets(
            top: 0, left: Metrics.spacing2, bottom: 0, right: Metrics.spacing2)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.backgroundColor = Colors.gray300
        stackView.clipsToBounds = true
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private let allocationsNumberLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleXS.font
        label.textColor = Colors.gray600
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    lazy var allocationsTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Colors.gray100
        tableView.layer.borderWidth = 1
        tableView.layer.borderColor = Colors.gray300.cgColor
        tableView.layer.cornerRadius = CornerRadius.extraLarge
        tableView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets.zero
        tableView.clipsToBounds = true
        tableView.separatorColor = Colors.gray300
        tableView.isHidden = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.setContentHuggingPriority(.defaultLow, for: .vertical)
        tableView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        tableView.register(AllocationCell.self, forCellReuseIdentifier: AllocationCell.reuseIdentifier)
        return tableView
    }()

    private let allocationsEmptyStateView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.borderWidth = 1
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let allocationsEmptyStateIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "iconBankSlip")
        imageView.tintColor = Colors.gray400
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let allocationsEmptyStateDescriptionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.text = "budget.allocations.emptyState.description".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupNotificationObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAllocationDataChanged),
            name: .allocationDataChanged,
            object: nil
        )
        // Tag edits change the strip and the ring without touching a single allocation, so they need
        // their own signal - `.allocationDataChanged` is never posted for them.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAllocationTagsChanged),
            name: .allocationTagsChanged,
            object: nil
        )
    }

    @objc private func handleAllocationTagsChanged() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.handleAllocationTagsChanged() }
            return
        }
        guard isShowingBudgetView else { return }
        rebuildAllocationsUI()
    }

    // MARK: - Allocations rebuild funnel

    /// The one place the allocations side of this cell is rebuilt.
    ///
    /// Six paths used to each fetch, sort, reload, set the badge and reconfigure the card in their own
    /// near-identical block. Anything added to that work had to be added six times, and the four blocks
    /// that also flipped `isHidden` were one edit away from disagreeing about which views exist.
    ///
    /// Passing nil for any argument fetches it, so callers that already hold fresh data do not pay for
    /// a second read.
    private func rebuildAllocationsUI(
        allocations: [BudgetAllocation]? = nil,
        unallocatedSpending: [UnallocatedCategorySpending]? = nil,
        summary: UnallocatedBudgetSummary? = nil
    ) {
        // No ledger scope on this branch: `LedgerScope` arrives with group sync in 1.6.0, and these
        // service methods take no scope here. Everything is personal-scoped, which is what the rest of
        // this file already assumes.
        let resolvedAllocations =
            allocations ?? allocationService.getAllocationsWithUsage(forMonth: currentMonthAnchor)
        let resolvedSpending =
            unallocatedSpending
            ?? allocationService.getUnallocatedCategoriesWithSpending(forMonth: currentMonthAnchor)
        let resolvedSummary =
            summary ?? allocationService.getUnallocatedSummary(forMonth: currentMonthAnchor)

        // Sorted for the list, as before. The card is handed the same sorted array now rather than the
        // unsorted one, so the donut and the rows beneath it agree about order.
        currentAllocations = resolvedAllocations.sorted { $0.allocatedAmount > $1.allocatedAmount }
        currentUnallocatedSpending = resolvedSpending

        let book = tagService.book
        tagBreakdown = AllocationTagBreakdown(
            allocations: currentAllocations,
            unallocatedSpending: currentUnallocatedSpending,
            unallocatedHeadroom: resolvedSummary.unallocatedAmount,
            totalBudget: resolvedSummary.totalBudget,
            tags: book.orderedTags,
            categoryTagIds: book.categoryTagIds)

        // A tag with no arc this month cannot be shown as selected, so it cannot be cleared either.
        if let selectedTagId, tagBreakdown.arc(id: selectedTagId) == nil {
            self.selectedTagId = nil
        }

        let hasStrip = allocationTagStripView.configure(
            breakdown: tagBreakdown,
            selectedTagId: selectedTagId,
            isValuesHidden: UserDefaultsManager.getHideValues())
        tagStripHeightConstraint?.constant = hasStrip ? AllocationTagStripView.preferredHeight : 0

        budgetCard.configure(
            month: monthCard.currentMonth,
            year: monthCard.currentYear,
            allocations: currentAllocations,
            unallocatedSummary: resolvedSummary,
            unallocatedSpending: currentUnallocatedSpending,
            monthAnchor: currentMonthAnchor,
            monthData: currentMonthData,
            tagBreakdown: tagBreakdown
        )
        budgetCard.setSelectedTag(selectedTagId)

        applyTagFilter()
    }

    /// Recomputes the visible rows from `selectedTagId` and brings the table, badge and empty state in
    /// line. Split from `rebuildAllocationsUI` so a chip tap does not refetch anything.
    private func applyTagFilter() {
        if let selectedTagId {
            visibleAllocations = currentAllocations.filter {
                tagBreakdown.segment("alloc-\($0.category.key)", belongsTo: selectedTagId)
            }
            visibleUnallocatedSpending = currentUnallocatedSpending.filter {
                tagBreakdown.segment("offplan-\($0.category.key)", belongsTo: selectedTagId)
            }
        } else {
            visibleAllocations = currentAllocations
            visibleUnallocatedSpending = currentUnallocatedSpending
        }

        allocationsTableView.reloadData()
        // The honest reading of a number sitting beside a filtered list.
        allocationsNumberLabel.text = "\(visibleRowCount)"
        updateAllocationsTableHeight(count: visibleRowCount)
        allocationTagStripView.setSelectedTag(selectedTagId)

        // A filter that matches nothing shows the empty state with its own wording, rather than a
        // zero-row table that looks like a loading bug.
        allocationsEmptyStateDescriptionLabel.text =
            selectedTagId == nil
            ? "budget.allocations.emptyState.description".localized
            : "budget.allocations.emptyState.filtered".localized

        if isShowingBudgetView {
            let hasContent = visibleRowCount > 0
            allocationsTableView.isHidden = !hasContent
            allocationsEmptyStateView.isHidden = hasContent
        }
    }

    /// Declares the set of views that belong to the allocations face exactly once. Four paths write
    /// these together, and missing one leaves a stray band floating over the transactions list.
    private func setAllocationsViewsHidden(_ hidden: Bool, hasContent: Bool) {
        allocationsTableHeaderView.isHidden = hidden
        allocationTagStripView.isHidden = hidden || (tagStripHeightConstraint?.constant ?? 0) == 0
        allocationsTableView.isHidden = hidden || !hasContent
        allocationsEmptyStateView.isHidden = hidden || hasContent
    }

    @objc private func handleAllocationDataChanged() {
        // This handler touches UIKit directly, and `.allocationDataChanged` is posted from
        // background write/sync paths too — NotificationCenter delivers on the posting thread,
        // so bounce to main before doing anything.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.handleAllocationDataChanged() }
            return
        }

        // Only refresh if currently showing budget view
        guard isShowingBudgetView else { return }

        rebuildAllocationsUI()
    }

    private func setupViews() {
        monthCard.translatesAutoresizingMaskIntoConstraints = false
        monthCard.flipDelegate = self
        budgetCard.delegate = self

        // Set high priority for content hugging and compression resistance
        // to prevent the card from being compressed when the table grows
        monthCard.setContentHuggingPriority(.required, for: .vertical)
        monthCard.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // Set high priority for search container to prevent compression
        searchContainerView.setContentHuggingPriority(.required, for: .vertical)
        searchContainerView.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // Set high priority for search input to maintain its height
        searchInput.setContentHuggingPriority(.required, for: .vertical)
        searchInput.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // Set high priority for filter button to maintain its height
        filterButton.setContentHuggingPriority(.required, for: .vertical)
        filterButton.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // Set high priority for table header to prevent compression
        tableHeaderView.setContentHuggingPriority(.required, for: .vertical)
        tableHeaderView.setContentCompressionResistancePriority(.required, for: .vertical)
        
        contentView.addSubview(monthCard)
        contentView.addSubview(budgetCard)
        contentView.addSubview(searchContainerView)
        searchContainerView.addSubview(searchInput)
        searchContainerView.addSubview(filterButton)
        contentView.addSubview(transactionTableView)
        
        contentView.addSubview(tableHeaderView)
        tableHeaderView.addArrangedSubview(tableHeaderTitleLabel)
        tableHeaderView.addArrangedSubview(transactionsNumberContainerView)
        transactionsNumberContainerView.addArrangedSubview(transactionNumberLabel)
        contentView.addSubview(emptyStateView)
        emptyStateView.addSubview(emptyStateIconImageView)
        emptyStateView.addSubview(emptyStateDescriptionLabel)

        // Allocations table components
        contentView.addSubview(allocationsTableHeaderView)
        allocationsTableHeaderView.addArrangedSubview(allocationsHeaderTitleLabel)
        allocationsTableHeaderView.addArrangedSubview(allocationsNumberContainerView)
        allocationsNumberContainerView.addArrangedSubview(allocationsNumberLabel)
        contentView.addSubview(allocationTagStripView)
        contentView.addSubview(allocationsTableView)
        contentView.addSubview(allocationsEmptyStateView)
        allocationsEmptyStateView.addSubview(allocationsEmptyStateIconImageView)
        allocationsEmptyStateView.addSubview(allocationsEmptyStateDescriptionLabel)

        // Set up allocations table data source and delegate
        allocationsTableView.dataSource = self
        allocationsTableView.delegate = self

        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            monthCard.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing4),
            monthCard.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
            monthCard.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),
            
            // BudgetCard overlays monthCard but doesn't affect its height
            budgetCard.topAnchor.constraint(equalTo: monthCard.topAnchor),
            budgetCard.leadingAnchor.constraint(equalTo: monthCard.leadingAnchor),
            budgetCard.trailingAnchor.constraint(equalTo: monthCard.trailingAnchor),
            
            searchContainerView.topAnchor.constraint(
                equalTo: monthCard.bottomAnchor, constant: Metrics.spacing4),
            searchContainerView.leadingAnchor.constraint(equalTo: monthCard.leadingAnchor),
            searchContainerView.trailingAnchor.constraint(equalTo: monthCard.trailingAnchor),
            searchContainerView.heightAnchor.constraint(equalToConstant: Metrics.inputHeight),
            
            searchInput.topAnchor.constraint(equalTo: searchContainerView.topAnchor),
            searchInput.leadingAnchor.constraint(equalTo: searchContainerView.leadingAnchor),
            searchInput.bottomAnchor.constraint(equalTo: searchContainerView.bottomAnchor),
            searchInput.trailingAnchor.constraint(
                equalTo: filterButton.leadingAnchor, constant: -Metrics.spacing2),
            
            filterButton.centerYAnchor.constraint(equalTo: searchContainerView.centerYAnchor),
            filterButton.trailingAnchor.constraint(equalTo: searchContainerView.trailingAnchor),
            filterButton.widthAnchor.constraint(equalToConstant: Metrics.inputHeight),
            filterButton.heightAnchor.constraint(equalToConstant: Metrics.inputHeight),
        ])
        
        NSLayoutConstraint.activate([
            tableHeaderView.topAnchor.constraint(
                equalTo: searchContainerView.bottomAnchor, constant: Metrics.spacing3),
            tableHeaderView.leadingAnchor.constraint(equalTo: monthCard.leadingAnchor),
            tableHeaderView.trailingAnchor.constraint(equalTo: monthCard.trailingAnchor),
            
            transactionTableView.topAnchor.constraint(equalTo: tableHeaderView.bottomAnchor),
            transactionTableView.leadingAnchor.constraint(equalTo: monthCard.leadingAnchor),
            transactionTableView.trailingAnchor.constraint(equalTo: monthCard.trailingAnchor),
            // Remove bottom constraint - we'll use height constraint only to prevent compression
            // transactionTableView.bottomAnchor.constraint(
            //   lessThanOrEqualTo: contentView.bottomAnchor, constant: -Metrics.spacing4),
            
            emptyStateView.topAnchor.constraint(equalTo: tableHeaderView.bottomAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: monthCard.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: monthCard.trailingAnchor),
            emptyStateView.heightAnchor.constraint(equalToConstant: Metrics.tableEmptyViewHeight),
            
            emptyStateIconImageView.leadingAnchor.constraint(
                equalTo: emptyStateView.leadingAnchor, constant: Metrics.spacing5),
            emptyStateIconImageView.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor),
            emptyStateIconImageView.heightAnchor.constraint(equalToConstant: Metrics.spacing8),
            emptyStateIconImageView.widthAnchor.constraint(equalToConstant: Metrics.spacing8),
            
            emptyStateDescriptionLabel.leadingAnchor.constraint(
                equalTo: emptyStateIconImageView.trailingAnchor, constant: Metrics.spacing5),
            emptyStateDescriptionLabel.trailingAnchor.constraint(
                equalTo: emptyStateView.trailingAnchor, constant: -Metrics.spacing4),
            emptyStateDescriptionLabel.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor),
        ])

        // Allocations table constraints - positioned directly below budgetCard (no search bar)
        NSLayoutConstraint.activate([
            allocationsTableHeaderView.topAnchor.constraint(
                equalTo: budgetCard.bottomAnchor, constant: Metrics.spacing4),
            allocationsTableHeaderView.leadingAnchor.constraint(equalTo: monthCard.leadingAnchor),
            allocationsTableHeaderView.trailingAnchor.constraint(equalTo: monthCard.trailingAnchor),

            // The strip sits between the header and both content views, so those two now hang off it
            // rather than off the header. At zero height it is layout-neutral.
            allocationTagStripView.topAnchor.constraint(
                equalTo: allocationsTableHeaderView.bottomAnchor),
            allocationTagStripView.leadingAnchor.constraint(equalTo: monthCard.leadingAnchor),
            allocationTagStripView.trailingAnchor.constraint(equalTo: monthCard.trailingAnchor),

            allocationsTableView.topAnchor.constraint(equalTo: allocationTagStripView.bottomAnchor),
            allocationsTableView.leadingAnchor.constraint(equalTo: monthCard.leadingAnchor),
            allocationsTableView.trailingAnchor.constraint(equalTo: monthCard.trailingAnchor),

            allocationsEmptyStateView.topAnchor.constraint(equalTo: allocationTagStripView.bottomAnchor),
            allocationsEmptyStateView.leadingAnchor.constraint(equalTo: monthCard.leadingAnchor),
            allocationsEmptyStateView.trailingAnchor.constraint(equalTo: monthCard.trailingAnchor),
            allocationsEmptyStateView.heightAnchor.constraint(equalToConstant: Metrics.tableEmptyViewHeight),

            allocationsEmptyStateIconImageView.leadingAnchor.constraint(
                equalTo: allocationsEmptyStateView.leadingAnchor, constant: Metrics.spacing5),
            allocationsEmptyStateIconImageView.centerYAnchor.constraint(equalTo: allocationsEmptyStateView.centerYAnchor),
            allocationsEmptyStateIconImageView.heightAnchor.constraint(equalToConstant: Metrics.spacing8),
            allocationsEmptyStateIconImageView.widthAnchor.constraint(equalToConstant: Metrics.spacing8),

            allocationsEmptyStateDescriptionLabel.leadingAnchor.constraint(
                equalTo: allocationsEmptyStateIconImageView.trailingAnchor, constant: Metrics.spacing5),
            allocationsEmptyStateDescriptionLabel.trailingAnchor.constraint(
                equalTo: allocationsEmptyStateView.trailingAnchor, constant: -Metrics.spacing4),
            allocationsEmptyStateDescriptionLabel.centerYAnchor.constraint(equalTo: allocationsEmptyStateView.centerYAnchor),
        ])

        tagStripHeightConstraint = allocationTagStripView.heightAnchor.constraint(equalToConstant: 0)
        tagStripHeightConstraint?.isActive = true
    }
    
    func configure(with model: MonthBudgetCardType, transactions: [Transaction]) {
        monthCard.configure(data: model)
        self.transactions = transactions
        self.currentMonthAnchor = model.date.monthAnchor
        
        // Reset table view to a clean state before reloading
        transactionTableView.setContentOffset(.zero, animated: false)
        transactionTableView.isUserInteractionEnabled = true
        transactionTableView.contentInset = .zero
        transactionTableView.scrollIndicatorInsets = .zero
        
        // Reset height constraint to force fresh calculation
        tableHeightConstraint?.isActive = false
        tableHeightConstraint = nil
        
        // Reload data
        transactionTableView.reloadData()
        
        // Update UI elements
        self.transactionNumberLabel.text = "\(transactions.count)"
        if transactions.isEmpty {
            transactionTableView.isHidden = true
            emptyStateView.isHidden = false
        } else {
            transactionTableView.isHidden = false
            emptyStateView.isHidden = true
        }
        
        // Force layout to get accurate card measurements first
        setNeedsLayout()
        layoutIfNeeded()

        // Set fixed height constraint based on the card's natural size
        // This must happen before calculating table height
        updateMonthCardMinHeight()

        // Now update table height with the correct available space
        updateTableHeight(txsCount: transactions.count)

        // Ensure scroll state is recalculated after table view has fully laid out
        // This fixes timing issues where scroll gets locked after adding transactions
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.transactions.isEmpty else { return }
            let txCount = self.isSearchActive ? self.filteredTransactions.count : self.transactions.count
            self.updateTableHeight(txsCount: txCount)
        }
    }
    
    private func updateMonthCardMinHeight() {
        guard monthCard.bounds.width > 0 else { return }

        // Calculate height only once and store it
        if originalMonthCardHeight == 0 {
            // Force the card to layout to get accurate measurements
            monthCard.setNeedsLayout()
            monthCard.layoutIfNeeded()

            let targetSize = CGSize(
                width: monthCard.bounds.width, height: UIView.layoutFittingExpandedSize.height)
            let cardHeight = monthCard.systemLayoutSizeFitting(
                targetSize,
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height

            guard cardHeight > 0 else { return }
            originalMonthCardHeight = cardHeight
        }

        // Create or update constraint to use the stored original height
        if monthCardHeightConstraint == nil {
            monthCardHeightConstraint = monthCard.heightAnchor.constraint(equalToConstant: originalMonthCardHeight)
            monthCardHeightConstraint?.priority = .required
            monthCardHeightConstraint?.isActive = true
        } else {
            // Always force the constraint back to original height
            monthCardHeightConstraint?.constant = originalMonthCardHeight
        }
    }
    
    func updateTableHeight(txsCount: Int) {
        let rowHeight: CGFloat = 67
        let separatorHeight = CGFloat(max(0, txsCount - 1)) * 1.0
        let contentHeight = CGFloat(txsCount) * rowHeight + separatorHeight
        
        // Calculate available space dynamically based on the cell's height
        let availableHeight = calculateAvailableHeightForTable()
        let maxTableHeight = max(0, availableHeight)  // Ensure non-negative
        let finalHeight = min(contentHeight, maxTableHeight)
        
        if tableHeightConstraint == nil {
            tableHeightConstraint = transactionTableView.heightAnchor.constraint(
                equalToConstant: finalHeight)
            tableHeightConstraint?.priority = .required
            tableHeightConstraint?.isActive = true
        } else {
            tableHeightConstraint?.constant = finalHeight
        }
        
        transactionTableView.isScrollEnabled = (contentHeight > maxTableHeight)
        transactionTableView.showsVerticalScrollIndicator = false
        
        layoutIfNeeded()
    }
    
    private func calculateAvailableHeightForTable() -> CGFloat {
        // Get the cell's available height (use contentView for collection view cells)
        let cellHeight = contentView.bounds.height > 0 ? contentView.bounds.height : bounds.height
        guard cellHeight > 0 else {
            // Fallback to default if bounds not set yet
            return Metrics.transactionsTableHeight
        }
        
        // Calculate all fixed-height components and spacing
        let topPadding = Metrics.spacing4
        // Use the constraint value if available, otherwise use bounds (but prefer constraint)
        let monthCardHeight: CGFloat
        if let constraintHeight = monthCardHeightConstraint?.constant, constraintHeight > 0 {
            monthCardHeight = constraintHeight
        } else if monthCard.bounds.height > 0 {
            monthCardHeight = monthCard.bounds.height
        } else {
            // If card height not set yet, use a conservative estimate
            // This should rarely happen, but prevents crashes
            return Metrics.transactionsTableHeight
        }
        let spacingAfterCard = Metrics.spacing4
        let searchContainerHeight = Metrics.inputHeight
        let spacingAfterSearch = Metrics.spacing3
        let tableHeaderHeight = Metrics.spacing11
        let bottomPadding = Metrics.spacing4
        
        // Sum of all fixed components
        let fixedComponentsHeight =
        topPadding + monthCardHeight + spacingAfterCard + searchContainerHeight + spacingAfterSearch
        + tableHeaderHeight + bottomPadding
        
        // Available height for table is total height minus fixed components
        let availableHeight = cellHeight - fixedComponentsHeight
        
        // Return the available height, but ensure it's at least 0 and not more than the default max
        // Use a minimum of 100 to ensure at least one row can be shown
        // Add a small buffer (10 points) to ensure we don't compress the card
        return max(100, min(availableHeight - 10, Metrics.transactionsTableHeight))
    }
    
    func toggleEmptyState(_ show: Bool) {
        transactionTableView.isHidden = show
        emptyStateView.isHidden = !show
    }
    
    // MARK: - Public Methods for Refresh
    
    /// Updates the transaction count and empty state without reconfiguring the month card
    func updateTransactionCount(_ count: Int) {
        transactionNumberLabel.text = "\(count)"
        toggleEmptyState(count == 0)
    }
    
    /// Updates the transactions array and reloads the table view
    func updateTransactions(_ newTransactions: [Transaction]) {
        transactions = newTransactions
        applyFilters()

        // Force recalculate scroll state after layout completes
        // This fixes timing issues where isScrollEnabled gets incorrectly set during batch updates
        DispatchQueue.main.async { [weak self] in
            self?.recalculateScrollState()
        }
    }

    /// Forces recalculation of scroll state for the transaction table
    /// Call this after batch updates to ensure scroll is properly enabled/disabled
    func recalculateScrollState() {
        guard !isShowingBudgetView, !transactions.isEmpty else { return }

        // Force layout to get accurate measurements
        setNeedsLayout()
        layoutIfNeeded()

        let txCount = isSearchActive ? filteredTransactions.count : transactions.count
        let rowHeight: CGFloat = 67
        let separatorHeight = CGFloat(max(0, txCount - 1)) * 1.0
        let contentHeight = CGFloat(txCount) * rowHeight + separatorHeight

        let availableHeight = calculateAvailableHeightForTable()
        let maxTableHeight = max(0, availableHeight)

        // Update height constraint
        let finalHeight = min(contentHeight, maxTableHeight)
        if let constraint = tableHeightConstraint {
            constraint.constant = finalHeight
        }

        // Recalculate scroll enabled state
        transactionTableView.isScrollEnabled = (contentHeight > maxTableHeight)
        transactionTableView.isUserInteractionEnabled = true
    }
    
    /// Clears the search input and resets all filters
    func clearSearch() {
        searchInput.text = ""
        currentFilters.clear()
        isSearchActive = false
        monthCard.clearFilteredState()
        updateClearButtonVisibility()
        applyFilters()
    }
    
    /// Returns the current displayed transactions (filtered or all)
    func getDisplayedTransactions() -> [Transaction] {
        return isSearchActive ? filteredTransactions : transactions
    }
    
    // MARK: - Search Handling
    
    @objc private func searchTextChanged() {
        let searchText = (searchInput.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        isSearchActive = !searchText.isEmpty || !currentFilters.isEmpty
        updateClearButtonVisibility()
        applyFilters()
        searchDelegate?.monthCarouselCell(self, didChangeSearchText: searchText)
    }
    
    @objc private func clearButtonTapped() {
        searchInput.text = ""
        searchInput.textField.resignFirstResponder()
        updateClearButtonVisibility()
        searchTextChanged()
    }
    
    private func updateClearButtonVisibility() {
        let hasText =
        !(searchInput.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        searchInput.textField.rightViewMode = hasText ? .always : .never
    }
    
    @objc private func filterButtonTapped() {
        searchDelegate?.monthCarouselCellDidTapFilter(self)
    }
    
    func applyFilters(_ filters: TransactionFilters? = nil) {
        if let filters = filters {
            currentFilters = filters
        }
        
        let searchText = (searchInput.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        isSearchActive = !searchText.isEmpty || !currentFilters.isEmpty
        
        filteredTransactions = transactions.filter { transaction in
            // Search text filter (case-insensitive and accent-insensitive)
            let normalizedSearchText = searchText.normalizedForSearch()
            let normalizedTitle = transaction.title.normalizedForSearch()
            let matchesSearch =
            normalizedSearchText.isEmpty || normalizedTitle.contains(normalizedSearchText)
            
            // Category filter
            let matchesCategory =
            currentFilters.categories.isEmpty
            || currentFilters.categories.contains(transaction.category)
            
            // Type filter
            let matchesType =
            currentFilters.types.isEmpty || currentFilters.types.contains(transaction.type)
            
            // Mode filter
            let matchesMode =
            currentFilters.modes.isEmpty || currentFilters.modes.contains(transaction.mode)
            
            // Day range filter (supports inverted ranges)
            let matchesDayRange: Bool
            if let startDay = currentFilters.startDay, let endDay = currentFilters.endDay {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone.current
                let transactionDay = calendar.component(.day, from: transaction.date)
                
                if startDay > endDay {
                    // Inverted range: match days from startDay to end of month OR from start of month to endDay
                    // Example: startDay=20, endDay=13 matches days 1-13 and 20-31
                    matchesDayRange = (transactionDay >= startDay) || (transactionDay <= endDay)
                } else {
                    // Normal range: match days from startDay to endDay
                    matchesDayRange = transactionDay >= startDay && transactionDay <= endDay
                }
            } else {
                matchesDayRange = true  // No day filter applied
            }
            
            return matchesSearch && matchesCategory && matchesType && matchesMode && matchesDayRange
        }
        
        updateFilterButtonAppearance()
        updateMonthCardFilterState()
        transactionTableView.reloadData()
        updateTransactionCount(filteredTransactions.count)
        updateTableHeight(txsCount: filteredTransactions.count)
    }
    
    private func updateMonthCardFilterState() {
        if isSearchActive {
            // Calculate sum of filtered transactions
            // Expenses are negative, income is positive
            let sum = filteredTransactions.reduce(0) { result, transaction in
                if transaction.type == .expense {
                    return result - transaction.amount
                } else {
                    return result + transaction.amount
                }
            }
            monthCard.updateFilteredState(isActive: true, sum: sum)
        } else {
            monthCard.clearFilteredState()
        }
    }
    
    private func updateFilterButtonAppearance() {
        if currentFilters.isEmpty {
            // Inactive state - gray background with border
            filterButton.backgroundColor = Colors.gray100
            filterButton.tintColor = Colors.gray600
            filterButton.layer.borderWidth = 1
            filterButton.layer.borderColor = Colors.gray300.cgColor
        } else {
            // Active state - magenta filled with white icon
            filterButton.backgroundColor = Colors.mainMagenta
            filterButton.tintColor = Colors.gray100
            filterButton.layer.borderWidth = 0
        }
    }
    
    func clearFilters() {
        currentFilters.clear()
        monthCard.clearFilteredState()
        applyFilters()
    }

    /// Sets filters without applying them immediately.
    /// Use this when you need to set filters before updateTransactions() is called,
    /// since updateTransactions() calls applyFilters() internally.
    func setFiltersWithoutApplying(_ filters: TransactionFilters) {
        currentFilters = filters
    }

    private func addBordersExceptBottom(to view: UIView, color: UIColor, width: CGFloat = 1.0) {
        view.layer.sublayers?.removeAll(where: { $0.name == "customBorder" })
        
        let bounds = view.bounds
        let cornerRadius = view.layer.cornerRadius
        
        let path = UIBezierPath()
        
        path.move(to: CGPoint(x: 0, y: bounds.height))
        
        path.addLine(to: CGPoint(x: 0, y: cornerRadius))
        
        path.addArc(
            withCenter: CGPoint(x: cornerRadius, y: cornerRadius),
            radius: cornerRadius,
            startAngle: .pi,
            endAngle: 3 * .pi / 2,
            clockwise: true)
        
        path.addLine(to: CGPoint(x: bounds.width - cornerRadius, y: 0))
        
        path.addArc(
            withCenter: CGPoint(x: bounds.width - cornerRadius, y: cornerRadius),
            radius: cornerRadius,
            startAngle: 3 * .pi / 2,
            endAngle: 0,
            clockwise: true)
        
        path.addLine(to: CGPoint(x: bounds.width, y: bounds.height))
        
        let borderLayer = CAShapeLayer()
        borderLayer.name = "customBorder"
        borderLayer.path = path.cgPath
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = color.cgColor
        borderLayer.lineWidth = width
        borderLayer.frame = bounds
        
        view.layer.addSublayer(borderLayer)
    }
    
    // MARK: - Flip Methods
    
    func flipToBudgetView(allocations: [BudgetAllocation], summary: UnallocatedBudgetSummary) {
        guard !isShowingBudgetView else { return }

        // Set state BEFORE animation to prevent icon flash
        isShowingBudgetView = true
        monthCard.setShowingBudgetView(true)
        onBudgetViewStateChanged?(currentMonthAnchor, true)

        rebuildAllocationsUI(allocations: allocations, summary: summary)
        let hasContent = visibleRowCount > 0

        // Disable transaction table interaction BEFORE animation to prevent stale taps
        transactionTableView.isUserInteractionEnabled = false

        // Use flip transition
        UIView.transition(
            with: contentView,
            duration: 0.5,
            options: [.transitionFlipFromRight, .showHideTransitionViews]
        ) {
            self.monthCard.isHidden = true
            self.budgetCard.isHidden = false
            // Hide search bar and transactions table components
            self.searchContainerView.isHidden = true
            self.tableHeaderView.isHidden = true
            self.transactionTableView.isHidden = true
            self.emptyStateView.isHidden = true
            // Show allocations table components
            self.setAllocationsViewsHidden(false, hasContent: hasContent)
        } completion: { _ in
            // Enable allocation table interaction after animation completes
            self.allocationsTableView.isUserInteractionEnabled = true
        }
    }

    func flipToTransactionView() {
        guard isShowingBudgetView else { return }

        // Set state BEFORE animation to prevent icon flash
        isShowingBudgetView = false
        monthCard.setShowingBudgetView(false)
        onBudgetViewStateChanged?(currentMonthAnchor, false)

        let hasTransactions = !transactions.isEmpty

        // Disable allocation table interaction BEFORE animation to prevent stale taps
        allocationsTableView.isUserInteractionEnabled = false

        UIView.transition(
            with: contentView,
            duration: 0.5,
            options: [.transitionFlipFromLeft, .showHideTransitionViews]
        ) {
            self.monthCard.isHidden = false
            self.budgetCard.isHidden = true
            // Show search bar and transactions table components
            self.searchContainerView.isHidden = false
            self.tableHeaderView.isHidden = false
            self.transactionTableView.isHidden = !hasTransactions
            self.emptyStateView.isHidden = hasTransactions
            // Hide allocations table components
            self.setAllocationsViewsHidden(true, hasContent: false)
        } completion: { _ in
            // Enable transaction table interaction after animation completes
            self.transactionTableView.isUserInteractionEnabled = true
        }
    }

    /// Restores budget view state without animation (for when returning from navigation)
    func restoreBudgetViewState(allocations: [BudgetAllocation], summary: UnallocatedBudgetSummary) {
        guard !isShowingBudgetView else { return }

        isShowingBudgetView = true
        monthCard.setShowingBudgetView(true)

        // Reset scroll position and state before reloading
        allocationsTableView.setContentOffset(.zero, animated: false)
        allocationsTableView.contentInset = .zero
        allocationsTableView.scrollIndicatorInsets = .zero

        rebuildAllocationsUI(allocations: allocations, summary: summary)

        // Set state directly without animation
        monthCard.isHidden = true
        budgetCard.isHidden = false
        searchContainerView.isHidden = true
        tableHeaderView.isHidden = true
        transactionTableView.isHidden = true
        emptyStateView.isHidden = true
        setAllocationsViewsHidden(false, hasContent: visibleRowCount > 0)

        // Ensure correct user interaction state for budget view
        transactionTableView.isUserInteractionEnabled = false
        allocationsTableView.isUserInteractionEnabled = true
    }

    /// Refreshes budget view data while staying in budget view (for pull-to-refresh)
    func refreshBudgetView(allocations: [BudgetAllocation], summary: UnallocatedBudgetSummary) {
        guard isShowingBudgetView else { return }

        // Reset scroll position and state before reloading
        allocationsTableView.setContentOffset(.zero, animated: false)
        allocationsTableView.contentInset = .zero
        allocationsTableView.scrollIndicatorInsets = .zero

        rebuildAllocationsUI(allocations: allocations, summary: summary)

        // Ensure correct user interaction state
        transactionTableView.isUserInteractionEnabled = false
        allocationsTableView.isUserInteractionEnabled = true
    }

    private func updateAllocationsTableHeight(count: Int) {
        let rowHeight: CGFloat = 68  // AllocationCell height with new layout
        let separatorHeight = CGFloat(max(0, count - 1)) * 1.0
        let contentHeight = CGFloat(count) * rowHeight + separatorHeight

        let availableHeight = calculateAvailableHeightForAllocationsTable()
        let maxTableHeight = max(0, availableHeight)
        let finalHeight = min(contentHeight, maxTableHeight)

        if allocationsTableHeightConstraint == nil {
            allocationsTableHeightConstraint = allocationsTableView.heightAnchor.constraint(
                equalToConstant: finalHeight)
            allocationsTableHeightConstraint?.priority = .required
            allocationsTableHeightConstraint?.isActive = true
        } else {
            allocationsTableHeightConstraint?.constant = finalHeight
        }

        allocationsTableView.isScrollEnabled = (contentHeight > maxTableHeight)
        allocationsTableView.showsVerticalScrollIndicator = false
    }

    private func calculateAvailableHeightForAllocationsTable() -> CGFloat {
        let cellHeight = contentView.bounds.height > 0 ? contentView.bounds.height : bounds.height
        guard cellHeight > 0 else {
            return Metrics.transactionsTableHeight
        }

        // Calculate components - NO search bar for allocations view
        let topPadding = Metrics.spacing4
        // Use budget card height (it sizes itself)
        let budgetCardHeight = budgetCard.bounds.height > 0 ? budgetCard.bounds.height : 220
        let spacingAfterCard = Metrics.spacing4
        // The chip strip sits between the header and the table, so its height is part of what the
        // table does NOT get. Omitting it makes the table 44pt too tall - and the clamp below absorbs
        // that on tall devices, so it passes casual testing and then clips rows on a small one.
        let tableHeaderHeight = Metrics.spacing11 + (tagStripHeightConstraint?.constant ?? 0)
        let bottomPadding = Metrics.spacing4

        let fixedComponentsHeight = topPadding + budgetCardHeight + spacingAfterCard + tableHeaderHeight + bottomPadding

        let availableHeight = cellHeight - fixedComponentsHeight

        return max(100, min(availableHeight - 10, Metrics.transactionsTableHeight + 100))
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        // Always ensure the month card height is set/restored to original
        if monthCard.bounds.width > 0 {
            updateMonthCardMinHeight()
        }

        // Recalculate table height after layout to account for actual available space
        if monthCardHeightConstraint != nil && !isShowingBudgetView {
            let currentCount = isSearchActive ? filteredTransactions.count : transactions.count
            updateTableHeight(txsCount: currentCount)
        }

        // Update allocations table height when in budget view. Uses `visibleRowCount`, which is what
        // `numberOfRowsInSection` returns - this used to pass `currentAllocations.count`, dropping the
        // unallocated-spending rows, so a month with only off-plan spend never recomputed at all.
        if isShowingBudgetView && visibleRowCount > 0 {
            updateAllocationsTableHeight(count: visibleRowCount)
        }
        
        transactionsNumberContainerView.layoutIfNeeded()
        
        let size = min(
            transactionsNumberContainerView.bounds.width, transactionsNumberContainerView.bounds.height)
        transactionsNumberContainerView.layer.cornerRadius = size / 2
        
        transactionsNumberContainerView.clipsToBounds = true

        tableHeaderView.layer.sublayers?.removeAll(where: { $0 is CAShapeLayer })
        tableHeaderView.layoutIfNeeded()
        addBordersExceptBottom(to: tableHeaderView, color: Colors.gray300)

        // Allocations table header rounded corners
        allocationsNumberContainerView.layoutIfNeeded()
        let allocationsSize = min(
            allocationsNumberContainerView.bounds.width, allocationsNumberContainerView.bounds.height)
        allocationsNumberContainerView.layer.cornerRadius = allocationsSize / 2
        allocationsNumberContainerView.clipsToBounds = true

        allocationsTableHeaderView.layer.sublayers?.removeAll(where: { $0 is CAShapeLayer })
        allocationsTableHeaderView.layoutIfNeeded()
        addBordersExceptBottom(to: allocationsTableHeaderView, color: Colors.gray300)

        // The strip draws its own side hairlines; nothing to do for it here.
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        monthCard.resetForReuse()

        // Reset height values to force recalculation for new content
        monthCardHeightConstraint?.isActive = false
        monthCardHeightConstraint = nil
        originalMonthCardHeight = 0

        // Reset alpha values
        monthCard.alpha = 1
        budgetCard.alpha = 1
        searchContainerView.alpha = 1
        tableHeaderView.alpha = 1
        transactionTableView.alpha = 1
        emptyStateView.alpha = 1
        allocationsTableHeaderView.alpha = 1
        allocationTagStripView.alpha = 1
        allocationsTableView.alpha = 1
        allocationsEmptyStateView.alpha = 1

        // Reset flip state - ensure all views are in transaction view state
        isShowingBudgetView = false
        monthCard.isHidden = false
        monthCard.setShowingBudgetView(false)  // Reset icon to pie chart
        budgetCard.isHidden = true
        searchContainerView.isHidden = false
        tableHeaderView.isHidden = false

        // Reset table height constraint to force recalculation
        tableHeightConstraint?.isActive = false
        tableHeightConstraint = nil

        // Reset allocations table
        allocationsTableHeightConstraint?.isActive = false
        allocationsTableHeightConstraint = nil
        currentAllocations = []
        currentUnallocatedSpending = []

        // Cells are reused, so a filter left set here would apply to a different month - and if that
        // month has no such tag, to a list with no chip left to clear it. Same class of bug that
        // `currentFilters.clear()` below guards for the transaction face.
        selectedTagId = nil
        tagBreakdown = .empty
        visibleAllocations = []
        visibleUnallocatedSpending = []
        tagStripHeightConstraint?.constant = 0

        // Reset scroll state to default
        transactionTableView.isScrollEnabled = false
        transactionTableView.contentInset = .zero
        transactionTableView.scrollIndicatorInsets = .zero

        allocationsTableView.isScrollEnabled = false
        allocationsTableView.contentInset = .zero
        allocationsTableView.scrollIndicatorInsets = .zero

        // Reset filter and search state to prevent stale data
        currentFilters.clear()
        filteredTransactions = []
        isSearchActive = false
        searchInput.text = ""
        updateFilterButtonAppearance()

        // Reset user interaction state - transaction view is default, so enable its table
        transactionTableView.isUserInteractionEnabled = true
        allocationsTableView.isUserInteractionEnabled = false

        // Hide both table and empty state during cell setup to prevent flashing
        transactionTableView.isHidden = true
        emptyStateView.isHidden = true
        setAllocationsViewsHidden(true, hasContent: false)

        clearSearch()
    }
}

// MARK: - UITextFieldDelegate
extension MonthCarouselCell: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - Keyboard Handling
extension MonthCarouselCell {
    func adjustTableForKeyboard(keyboardHeight: CGFloat, animationDuration: Double) {
        UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseInOut]) {
            if keyboardHeight > 0 {
                // Keyboard is showing - adjust content inset to make table scrollable above keyboard
                // This allows the table content to scroll above the keyboard
                self.transactionTableView.contentInset.bottom = keyboardHeight
                self.transactionTableView.scrollIndicatorInsets.bottom = keyboardHeight
                
                // Ensure the table can scroll by checking if content size exceeds visible area
                let contentHeight = self.transactionTableView.contentSize.height
                let visibleHeight = self.transactionTableView.bounds.height
                if contentHeight > visibleHeight - keyboardHeight {
                    // Content is scrollable, ensure we can see it
                    self.transactionTableView.isScrollEnabled = true
                }
            } else {
                // Keyboard is hiding - reset insets
                self.transactionTableView.contentInset.bottom = 0
                self.transactionTableView.scrollIndicatorInsets.bottom = 0
                
                // Recalculate scroll enabled state based on actual content
                let contentHeight = self.transactionTableView.contentSize.height
                let tableHeight = self.tableHeightConstraint?.constant ?? self.transactionTableView.bounds.height
                self.transactionTableView.isScrollEnabled = (contentHeight > tableHeight)
            }
        }
    }
}

// MARK: - MonthCardFlipDelegate

extension MonthCarouselCell: MonthCardFlipDelegate {
    func didRequestFlip(isShowingBudgetView: Bool) {
        if isShowingBudgetView {
            // Guard against invalid month anchor (cell not yet configured)
            guard currentMonthAnchor > 0 else {
                logWarning("MonthCarouselCell: Attempted to flip to budget view with invalid monthAnchor (0)")
                return
            }

            // Fetch real allocations and summary from the service
            let allocations = allocationService.getAllocationsWithUsage(forMonth: currentMonthAnchor)
            let summary = allocationService.getUnallocatedSummary(forMonth: currentMonthAnchor)
            logDebug("MonthCarouselCell: Fetched \(allocations.count) allocations for monthAnchor: \(currentMonthAnchor)")
            flipToBudgetView(allocations: allocations, summary: summary)
        } else {
            flipToTransactionView()
        }
    }
    
    func didSelectAllocationCategory(_ category: TransactionCategory) {
        // Will implement later
        print("Selected category: \(category.displayName)")
    }
    
    func didTapAllocation(_ allocation: BudgetAllocation) {
        onAllocationTapped?(allocation)
    }

    func didTapUnallocatedSpending(_ spending: UnallocatedCategorySpending) {
        onUnallocatedSpendingTapped?(spending)
    }

    func didTapBudgetsConfig(forMonth monthAnchor: Int) {
        onBudgetsConfigTapped?(monthAnchor)
    }

    func didTapDefineBudget(forMonth monthAnchor: Int) {
        onDefineBudgetTapped?(monthAnchor)
    }

    func didToggleBalanceVisibility(_ isHidden: Bool) {
        onBalanceVisibilityToggled?(isHidden)
    }

    func didSelectAllocationTag(_ tagId: String?) {
        applySelectedTag(tagId)
    }
}

// MARK: - AllocationTagStripViewDelegate

extension MonthCarouselCell: AllocationTagStripViewDelegate {
    func didSelectTag(_ tagId: String?) {
        applySelectedTag(tagId)
    }
}

extension MonthCarouselCell {
    /// One entry point for both the donut arc and the chip strip, so the two can never disagree about
    /// what is selected. Deliberately does not refetch: only the filter changed.
    private func applySelectedTag(_ tagId: String?) {
        guard selectedTagId != tagId else { return }
        selectedTagId = tagId
        budgetCard.setSelectedTag(tagId)
        applyTagFilter()
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate for Allocations

extension MonthCarouselCell: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView === allocationsTableView {
            // Total count: allocated items first, then unallocated items. `visible*` rather than
            // `current*` so a tag filter narrows the list.
            return visibleRowCount
        }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView === allocationsTableView {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: AllocationCell.reuseIdentifier,
                for: indexPath
            ) as? AllocationCell else {
                return UITableViewCell()
            }

            // Check if this is an allocated or unallocated row
            if indexPath.row < visibleAllocations.count {
                // Allocated category
                let allocation = visibleAllocations[indexPath.row]
                cell.configure(with: allocation)
                cell.setTapAction { [weak self] in
                    self?.didTapAllocation(allocation)
                }
            } else {
                // Unallocated category with spending
                let unallocatedIndex = indexPath.row - visibleAllocations.count
                let unallocatedSpending = visibleUnallocatedSpending[unallocatedIndex]
                cell.configure(with: unallocatedSpending)
                cell.setTapAction { [weak self] in
                    guard let self = self else { return }
                    // Navigate to unallocated details screen
                    self.onUnallocatedSpendingTapped?(unallocatedSpending)
                }
            }

            return cell
        }
        return UITableViewCell()
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if tableView === allocationsTableView {
            return 68  // AllocationCell with new layout
        }
        return UITableView.automaticDimension
    }
}
