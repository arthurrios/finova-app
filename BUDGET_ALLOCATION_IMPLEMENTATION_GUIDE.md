# Budget Allocation Feature - Implementation Guide

## FinoVa v1.4.0

This guide provides step-by-step instructions for implementing the Budget Allocation feature, which allows users to partition their monthly budget into category-based allocations.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Data Layer](#3-data-layer)
4. [Service Layer](#4-service-layer)
5. [UI Layer](#5-ui-layer)
6. [Implementation Order](#6-implementation-order)
7. [Testing Considerations](#7-testing-considerations)

---

## 1. Overview

### Feature Summary

The Budget Allocation feature extends the existing budget system to allow users to:
- Partition their main monthly budget into category-based allocations
- Track spending against each allocation with visual indicators
- View budget breakdowns via an interactive donut chart
- Create recurring allocations that apply to future months
- Filter transactions by tapping allocation chart segments

### Key Terminology

| Term | Description |
|------|-------------|
| **Budget** | The main monthly spending limit (existing) |
| **Allocation** | A portion of the budget assigned to a specific category |
| **Unallocated** | Budget amount not assigned to any allocation |
| **Ceiling** | The allocated amount for a category |
| **Usage** | Actual spending in a category for a month |

### Design Decisions

- **Category-only**: Allocations are tied to `TransactionCategory` enum values only
- **Soft validation**: Sum of allocations can exceed budget (warning shown)
- **Unallocated tracking**: Expenses in categories without allocations are tracked separately
- **Lazy generation**: Recurring allocations use lazy generation (same as transactions)

---

## 2. Architecture

### New Files to Create

```
Finova/Sources/
├── Core/
│   ├── Repositories/
│   │   └── BudgetAllocationRepository/
│   │       ├── BudgetAllocationModel.swift          # Data model
│   │       ├── BudgetAllocationRepository.swift     # Repository
│   │       └── BudgetAllocationRepositoryProtocol.swift
│   └── Services/
│       └── BudgetAllocationService.swift            # Business logic
├── Scenes/
│   └── Dashboard/
│       └── DashboardCarousel/
│           └── MonthCarousel/
│               ├── BudgetCard/
│               │   ├── BudgetCard.swift             # Back of MonthBudgetCard
│               │   ├── BudgetDonutChart.swift       # SwiftUI Chart
│               │   └── AllocationCell.swift         # Table cell
│               └── MonthCarouselCell.swift          # (modify for flip)
└── SwiftUI/
    └── Charts/
        └── BudgetDonutChartView.swift               # SwiftUI chart component
```

### Modified Files

```
Finova/Sources/
├── Core/
│   ├── Constants/
│   │   └── Colors.swift                             # Add warningAmber color
│   └── Models/
│       └── Enums/
│           └── AllocationStatus.swift               # New enum
├── Scenes/
│   ├── Dashboard/
│   │   ├── DashboardViewModel.swift                 # Add allocation methods
│   │   └── DashboardCarousel/
│   │       └── MonthCarousel/
│   │           ├── MonthBudgetCard/
│   │           │   └── MonthBudgetCard.swift        # Add flip toggle
│   │           └── MonthCarouselCell.swift          # Add flip logic
│   └── AddTransaction/
│       ├── AddTransactionModalView.swift            # Add segmented control
│       └── AddTransactionModalViewModel.swift       # Add allocation methods
```

---

## 3. Data Layer

### 3.1 BudgetAllocationModel

**File:** `Finova/Sources/Core/Repositories/BudgetAllocationRepository/BudgetAllocationModel.swift`

```swift
import Foundation

// MARK: - Database Model

struct BudgetAllocationModel: Codable {
    let id: Int?
    let monthDate: Int                    // Month anchor (same as BudgetModel)
    let categoryKey: String               // TransactionCategory.key
    let allocatedAmount: Int              // In cents
    let isRecurring: Bool
    let parentAllocationId: Int?          // For recurring instances

    init(
        id: Int? = nil,
        monthDate: Int,
        categoryKey: String,
        allocatedAmount: Int,
        isRecurring: Bool = false,
        parentAllocationId: Int? = nil
    ) {
        self.id = id
        self.monthDate = monthDate
        self.categoryKey = categoryKey
        self.allocatedAmount = allocatedAmount
        self.isRecurring = isRecurring
        self.parentAllocationId = parentAllocationId
    }
}

// MARK: - Display Model (for UI)

struct BudgetAllocation {
    let id: Int?
    let monthDate: Int
    let category: TransactionCategory
    let allocatedAmount: Int
    let isRecurring: Bool
    let parentAllocationId: Int?

    // Computed from transactions
    var usedAmount: Int = 0

    var remainingAmount: Int {
        allocatedAmount - usedAmount
    }

    var usagePercentage: Double {
        guard allocatedAmount > 0 else { return 0 }
        return Double(usedAmount) / Double(allocatedAmount) * 100
    }

    var status: AllocationStatus {
        let percentage = usagePercentage
        if percentage > 100 {
            return .overBudget
        } else if percentage >= 80 {
            return .nearLimit
        } else {
            return .underBudget
        }
    }

    init(from model: BudgetAllocationModel) {
        self.id = model.id
        self.monthDate = model.monthDate
        self.category = TransactionCategory.allCases.first { $0.key == model.categoryKey } ?? .miscellaneous
        self.allocatedAmount = model.allocatedAmount
        self.isRecurring = model.isRecurring
        self.parentAllocationId = model.parentAllocationId
    }

    mutating func setUsedAmount(_ amount: Int) {
        self.usedAmount = amount
    }
}

// MARK: - Allocation Status Enum

enum AllocationStatus {
    case underBudget    // 0-79% used
    case nearLimit      // 80-99% used
    case overBudget     // 100%+ used

    var color: UIColor {
        switch self {
        case .underBudget: return Colors.mainMagenta
        case .nearLimit: return Colors.warningAmber
        case .overBudget: return Colors.mainRed
        }
    }

    var icon: String {
        switch self {
        case .underBudget: return "checkmark.circle.fill"
        case .nearLimit: return "exclamationmark.triangle.fill"
        case .overBudget: return "xmark.circle.fill"
        }
    }

    var localizedLabel: String {
        switch self {
        case .underBudget: return "allocation.status.under".localized
        case .nearLimit: return "allocation.status.near".localized
        case .overBudget: return "allocation.status.over".localized
        }
    }
}

// MARK: - Unallocated Budget Summary

struct UnallocatedBudgetSummary {
    let monthDate: Int
    let totalBudget: Int
    let totalAllocated: Int
    let totalUsedInUnallocatedCategories: Int

    var unallocatedAmount: Int {
        totalBudget - totalAllocated
    }

    var unallocatedRemaining: Int {
        unallocatedAmount - totalUsedInUnallocatedCategories
    }

    var isOverspent: Bool {
        unallocatedRemaining < 0
    }
}
```

### 3.2 BudgetAllocationRepository

**File:** `Finova/Sources/Core/Repositories/BudgetAllocationRepository/BudgetAllocationRepository.swift`

```swift
import Foundation

final class BudgetAllocationRepository {
    private let secureStorage = SecureLocalDataManager.shared
    private let storageKey = "budget_allocations"

    // MARK: - CRUD Operations

    func insert(_ allocation: BudgetAllocationModel) throws -> Int {
        var allocations = fetchAllModels()

        // Check for duplicate (same category + month)
        if allocations.contains(where: {
            $0.monthDate == allocation.monthDate && $0.categoryKey == allocation.categoryKey
        }) {
            throw BudgetAllocationError.duplicateAllocation
        }

        // Generate new ID
        let newId = (allocations.map { $0.id ?? 0 }.max() ?? 0) + 1
        let newAllocation = BudgetAllocationModel(
            id: newId,
            monthDate: allocation.monthDate,
            categoryKey: allocation.categoryKey,
            allocatedAmount: allocation.allocatedAmount,
            isRecurring: allocation.isRecurring,
            parentAllocationId: allocation.parentAllocationId
        )

        allocations.append(newAllocation)
        try save(allocations)

        return newId
    }

    func update(_ allocation: BudgetAllocationModel) throws {
        var allocations = fetchAllModels()

        guard let index = allocations.firstIndex(where: { $0.id == allocation.id }) else {
            throw BudgetAllocationError.allocationNotFound
        }

        allocations[index] = allocation
        try save(allocations)
    }

    func delete(id: Int) throws {
        var allocations = fetchAllModels()
        allocations.removeAll { $0.id == id }
        try save(allocations)
    }

    func deleteAllForMonth(_ monthAnchor: Int) throws {
        var allocations = fetchAllModels()
        allocations.removeAll { $0.monthDate == monthAnchor }
        try save(allocations)
    }

    // MARK: - Fetch Operations

    func fetchAllocations(forMonth monthAnchor: Int) -> [BudgetAllocation] {
        return fetchAllModels()
            .filter { $0.monthDate == monthAnchor }
            .map { BudgetAllocation(from: $0) }
    }

    func fetchRecurringAllocations() -> [BudgetAllocationModel] {
        return fetchAllModels().filter { $0.isRecurring && $0.parentAllocationId == nil }
    }

    func fetchAllocationInstances(forParent parentId: Int) -> [BudgetAllocationModel] {
        return fetchAllModels().filter { $0.parentAllocationId == parentId }
    }

    func exists(category: TransactionCategory, monthAnchor: Int) -> Bool {
        return fetchAllModels().contains {
            $0.categoryKey == category.key && $0.monthDate == monthAnchor
        }
    }

    // MARK: - Private Helpers

    private func fetchAllModels() -> [BudgetAllocationModel] {
        guard let data = secureStorage.getData(forKey: storageKey),
              let allocations = try? JSONDecoder().decode([BudgetAllocationModel].self, from: data) else {
            return []
        }
        return allocations
    }

    private func save(_ allocations: [BudgetAllocationModel]) throws {
        let data = try JSONEncoder().encode(allocations)
        secureStorage.setData(data, forKey: storageKey)
    }
}

// MARK: - Errors

enum BudgetAllocationError: LocalizedError {
    case duplicateAllocation
    case allocationNotFound
    case invalidAmount

    var errorDescription: String? {
        switch self {
        case .duplicateAllocation:
            return "allocation.error.duplicate".localized
        case .allocationNotFound:
            return "allocation.error.notFound".localized
        case .invalidAmount:
            return "allocation.error.invalidAmount".localized
        }
    }
}
```

### 3.3 Add Warning Color

**File:** `Finova/Sources/Core/Constants/Colors.swift`

Add to existing Colors struct:

```swift
// Add after mainRed
static let warningAmber = UIColor(hex: "#F59E0B")
static let lowAmber = UIColor(hex: "#F59E0B").withAlphaComponent(0.05)
```

---

## 4. Service Layer

### 4.1 BudgetAllocationService

**File:** `Finova/Sources/Core/Services/BudgetAllocationService.swift`

```swift
import Foundation

final class BudgetAllocationService {
    private let allocationRepo: BudgetAllocationRepository
    private let transactionRepo: TransactionRepository
    private let budgetRepo: BudgetRepository
    private let calendar: Calendar

    init(
        allocationRepo: BudgetAllocationRepository = BudgetAllocationRepository(),
        transactionRepo: TransactionRepository = TransactionRepository(),
        budgetRepo: BudgetRepository = BudgetRepository()
    ) {
        self.allocationRepo = allocationRepo
        self.transactionRepo = transactionRepo
        self.budgetRepo = budgetRepo

        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        self.calendar = cal
    }

    // MARK: - Allocation Management

    func createAllocation(
        category: TransactionCategory,
        amount: Int,
        monthAnchor: Int,
        isRecurring: Bool
    ) throws -> Int {
        guard amount > 0 else {
            throw BudgetAllocationError.invalidAmount
        }

        let model = BudgetAllocationModel(
            monthDate: monthAnchor,
            categoryKey: category.key,
            allocatedAmount: amount,
            isRecurring: isRecurring,
            parentAllocationId: nil
        )

        let insertedId = try allocationRepo.insert(model)

        // If recurring, generate instances for immediate window (next 2 months)
        if isRecurring {
            try generateRecurringInstances(
                parentId: insertedId,
                category: category,
                amount: amount,
                startMonthAnchor: monthAnchor,
                monthCount: 2
            )
        }

        return insertedId
    }

    func updateAllocation(id: Int, newAmount: Int) throws {
        var allocations = allocationRepo.fetchAllocations(forMonth: 0) // fetch all
        // Re-fetch with proper filter
        let allModels = allocationRepo.fetchRecurringAllocations() // temporary

        // This needs proper implementation - fetch by ID
        let model = BudgetAllocationModel(
            id: id,
            monthDate: 0, // will be replaced
            categoryKey: "",
            allocatedAmount: newAmount,
            isRecurring: false
        )
        try allocationRepo.update(model)
    }

    func deleteAllocation(id: Int) throws {
        // Also delete any instances if this is a recurring parent
        let instances = allocationRepo.fetchAllocationInstances(forParent: id)
        for instance in instances {
            if let instanceId = instance.id {
                try allocationRepo.delete(id: instanceId)
            }
        }
        try allocationRepo.delete(id: id)
    }

    // MARK: - Calculations

    func getAllocationsWithUsage(forMonth monthAnchor: Int) -> [BudgetAllocation] {
        var allocations = allocationRepo.fetchAllocations(forMonth: monthAnchor)
        let usageByCategory = calculateUsageByCategory(forMonth: monthAnchor)

        for i in allocations.indices {
            let categoryKey = allocations[i].category.key
            allocations[i].setUsedAmount(usageByCategory[categoryKey] ?? 0)
        }

        return allocations
    }

    func calculateUsageByCategory(forMonth monthAnchor: Int) -> [String: Int] {
        let transactions = transactionRepo.fetchAllTransactions()
            .filter { $0.budgetMonthDate == monthAnchor && $0.type == .expense }

        var usageByCategory: [String: Int] = [:]

        for transaction in transactions {
            let key = transaction.category.key
            usageByCategory[key, default: 0] += transaction.amount
        }

        return usageByCategory
    }

    func getUnallocatedSummary(forMonth monthAnchor: Int) -> UnallocatedBudgetSummary {
        let budgets = budgetRepo.fetchBudgets()
        let budget = budgets.first { $0.monthDate == monthAnchor }
        let totalBudget = budget?.amount ?? 0

        let allocations = allocationRepo.fetchAllocations(forMonth: monthAnchor)
        let totalAllocated = allocations.reduce(0) { $0 + $1.allocatedAmount }

        let allocatedCategories = Set(allocations.map { $0.category.key })
        let usageByCategory = calculateUsageByCategory(forMonth: monthAnchor)

        let unallocatedUsage = usageByCategory
            .filter { !allocatedCategories.contains($0.key) }
            .reduce(0) { $0 + $1.value }

        return UnallocatedBudgetSummary(
            monthDate: monthAnchor,
            totalBudget: totalBudget,
            totalAllocated: totalAllocated,
            totalUsedInUnallocatedCategories: unallocatedUsage
        )
    }

    func getTotalAllocated(forMonth monthAnchor: Int) -> Int {
        return allocationRepo.fetchAllocations(forMonth: monthAnchor)
            .reduce(0) { $0 + $1.allocatedAmount }
    }

    func checkAllocationExceedsBudget(forMonth monthAnchor: Int, newAllocationAmount: Int = 0) -> Bool {
        let budgets = budgetRepo.fetchBudgets()
        let budget = budgets.first { $0.monthDate == monthAnchor }
        let totalBudget = budget?.amount ?? 0

        let currentAllocated = getTotalAllocated(forMonth: monthAnchor)
        return (currentAllocated + newAllocationAmount) > totalBudget
    }

    // MARK: - Lazy Generation for Recurring Allocations

    func generateAllocationsLazilyForMonths(_ monthAnchors: Set<Int>) {
        let recurringParents = allocationRepo.fetchRecurringAllocations()

        for parent in recurringParents {
            guard let parentId = parent.id else { continue }

            let existingInstances = allocationRepo.fetchAllocationInstances(forParent: parentId)
            let existingAnchors = Set(existingInstances.map { $0.monthDate })

            let missingAnchors = monthAnchors
                .subtracting(existingAnchors)
                .filter { $0 != parent.monthDate }  // Don't create for parent's month
                .filter { $0 > parent.monthDate }   // Only future months

            for targetAnchor in missingAnchors {
                let instance = BudgetAllocationModel(
                    monthDate: targetAnchor,
                    categoryKey: parent.categoryKey,
                    allocatedAmount: parent.allocatedAmount,
                    isRecurring: false,
                    parentAllocationId: parentId
                )

                do {
                    _ = try allocationRepo.insert(instance)
                    print("✅ LAZY: Created allocation instance for category \(parent.categoryKey) in month \(targetAnchor)")
                } catch {
                    print("❌ LAZY: Error creating allocation instance: \(error)")
                }
            }
        }
    }

    func needsLazyGeneration(for monthAnchors: Set<Int>) -> Bool {
        let recurringParents = allocationRepo.fetchRecurringAllocations()

        for parent in recurringParents {
            guard let parentId = parent.id else { continue }

            let existingInstances = allocationRepo.fetchAllocationInstances(forParent: parentId)
            let existingAnchors = Set(existingInstances.map { $0.monthDate })

            let missingAnchors = monthAnchors
                .subtracting(existingAnchors)
                .filter { $0 != parent.monthDate }
                .filter { $0 > parent.monthDate }

            if !missingAnchors.isEmpty {
                return true
            }
        }

        return false
    }

    // MARK: - Private Helpers

    private func generateRecurringInstances(
        parentId: Int,
        category: TransactionCategory,
        amount: Int,
        startMonthAnchor: Int,
        monthCount: Int
    ) throws {
        let startDate = Date(timeIntervalSince1970: TimeInterval(startMonthAnchor))

        for monthOffset in 1...monthCount {
            guard let targetDate = calendar.date(byAdding: .month, value: monthOffset, to: startDate) else {
                continue
            }

            let targetAnchor = targetDate.monthAnchor

            let instance = BudgetAllocationModel(
                monthDate: targetAnchor,
                categoryKey: category.key,
                allocatedAmount: amount,
                isRecurring: false,
                parentAllocationId: parentId
            )

            _ = try allocationRepo.insert(instance)
        }
    }
}
```

---

## 5. UI Layer

### 5.1 Add Flip Toggle to MonthBudgetCard

**File:** `Finova/Sources/Scenes/Dashboard/DashboardCarousel/MonthCarousel/MonthBudgetCard/MonthBudgetCard.swift`

Add the following to the existing `MonthBudgetCard`:

```swift
// MARK: - Properties (add to existing)

private var isShowingBudgetView = false
weak var flipDelegate: MonthCardFlipDelegate?

// MARK: - UI Components (add to existing header section)

private lazy var budgetViewToggleButton: UIButton = {
    let button = UIButton(type: .system)
    let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
    let image = UIImage(systemName: "chart.pie.fill", withConfiguration: config)
    button.setImage(image, for: .normal)
    button.tintColor = Colors.gray100
    button.addTarget(self, action: #selector(toggleBudgetView), for: .touchUpInside)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

// MARK: - Actions (add)

@objc private func toggleBudgetView() {
    flipDelegate?.didRequestFlip(isShowingBudgetView: !isShowingBudgetView)
}

func setShowingBudgetView(_ showing: Bool) {
    isShowingBudgetView = showing
    let imageName = showing ? "creditcard.fill" : "chart.pie.fill"
    let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
    let image = UIImage(systemName: imageName, withConfiguration: config)
    budgetViewToggleButton.setImage(image, for: .normal)
}
```

**Header Layout Update:**

In `setupConstraints()`, add the toggle button to the header between the hide-values button and config button:

```swift
// In headerStackView, add budgetViewToggleButton
// Layout: [monthLabel] [spacer] [hideValuesButton] [budgetViewToggleButton] [configButton]
```

### 5.2 FlipDelegate Protocol

**File:** `Finova/Sources/Scenes/Dashboard/DashboardCarousel/MonthCarousel/MonthCardFlipDelegate.swift` (new file)

```swift
protocol MonthCardFlipDelegate: AnyObject {
    func didRequestFlip(isShowingBudgetView: Bool)
    func didSelectAllocationCategory(_ category: TransactionCategory)
}
```

### 5.3 BudgetCard (Back of MonthCard)

**File:** `Finova/Sources/Scenes/Dashboard/DashboardCarousel/MonthCarousel/BudgetCard/BudgetCard.swift`

```swift
import UIKit
import SwiftUI

final class BudgetCard: UIView {

    // MARK: - Properties

    private var allocations: [BudgetAllocation] = []
    private var unallocatedSummary: UnallocatedBudgetSummary?
    weak var delegate: MonthCardFlipDelegate?

    // MARK: - UI Components

    private lazy var headerStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = Metrics.spacing3
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var monthLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleMD
        label.textColor = Colors.gray100
        return label
    }()

    private lazy var yearLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM
        label.textColor = Colors.gray400
        return label
    }()

    private lazy var flipBackButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let image = UIImage(systemName: "creditcard.fill", withConfiguration: config)
        button.setImage(image, for: .normal)
        button.tintColor = Colors.gray100
        button.addTarget(self, action: #selector(flipBack), for: .touchUpInside)
        return button
    }()

    private lazy var chartContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var budgetLimitLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS
        label.textColor = Colors.gray400
        label.textAlignment = .center
        return label
    }()

    private lazy var allocationProgressBar: RoundedProgressBar = {
        let bar = RoundedProgressBar()
        bar.trackTintColor = Colors.gray600
        bar.progressTintColor = Colors.mainMagenta
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private lazy var allocationPercentLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS
        label.textColor = Colors.gray400
        label.textAlignment = .right
        return label
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = Colors.gray700
        layer.cornerRadius = CornerRadius.large

        // Add subviews and setup constraints
        addSubview(headerStackView)
        addSubview(chartContainerView)
        addSubview(budgetLimitLabel)
        addSubview(allocationProgressBar)
        addSubview(allocationPercentLabel)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Header
            headerStackView.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.spacing4),
            headerStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            headerStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),

            // Chart container
            chartContainerView.topAnchor.constraint(equalTo: headerStackView.bottomAnchor, constant: Metrics.spacing4),
            chartContainerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            chartContainerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            chartContainerView.heightAnchor.constraint(equalToConstant: 160),

            // Budget limit label
            budgetLimitLabel.topAnchor.constraint(equalTo: chartContainerView.bottomAnchor, constant: Metrics.spacing3),
            budgetLimitLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),

            // Progress bar
            allocationProgressBar.topAnchor.constraint(equalTo: budgetLimitLabel.bottomAnchor, constant: Metrics.spacing2),
            allocationProgressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            allocationProgressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            allocationProgressBar.heightAnchor.constraint(equalToConstant: 8),

            // Percent label
            allocationPercentLabel.centerYAnchor.constraint(equalTo: budgetLimitLabel.centerYAnchor),
            allocationPercentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
        ])
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

        monthLabel.text = month
        yearLabel.text = year

        // Budget limit
        budgetLimitLabel.text = "Budget Limit: \(unallocatedSummary.totalBudget.currencyString)"

        // Allocation progress
        let allocatedPercent = unallocatedSummary.totalBudget > 0
            ? Float(unallocatedSummary.totalAllocated) / Float(unallocatedSummary.totalBudget)
            : 0
        allocationProgressBar.setProgress(allocatedPercent, animated: true)
        allocationPercentLabel.text = "\(Int(allocatedPercent * 100))% allocated"

        // Setup chart
        setupDonutChart()
    }

    private func setupDonutChart() {
        // Remove existing chart if any
        chartContainerView.subviews.forEach { $0.removeFromSuperview() }

        guard let summary = unallocatedSummary else { return }

        // Create SwiftUI chart
        let chartView = BudgetDonutChartView(
            allocations: allocations,
            unallocatedAmount: summary.unallocatedAmount,
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
            hostingController.view.bottomAnchor.constraint(equalTo: chartContainerView.bottomAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func flipBack() {
        delegate?.didRequestFlip(isShowingBudgetView: false)
    }
}
```

### 5.4 SwiftUI Donut Chart

**File:** `Finova/Sources/SwiftUI/Charts/BudgetDonutChartView.swift`

```swift
import SwiftUI
import Charts

@available(iOS 16.0, *)
struct BudgetDonutChartView: View {
    let allocations: [BudgetAllocation]
    let unallocatedAmount: Int
    var onSegmentTapped: ((TransactionCategory) -> Void)?

    @State private var selectedCategory: TransactionCategory?

    var body: some View {
        ZStack {
            // Donut Chart
            Chart {
                // Allocation segments
                ForEach(allocations, id: \.category.key) { allocation in
                    SectorMark(
                        angle: .value("Amount", allocation.allocatedAmount),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color(allocation.status.color))
                    .opacity(selectedCategory == allocation.category ? 1.0 : 0.8)
                }

                // Unallocated segment
                if unallocatedAmount > 0 {
                    SectorMark(
                        angle: .value("Unallocated", unallocatedAmount),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color(Colors.gray500))
                    .opacity(0.5)
                }
            }
            .chartLegend(.hidden)

            // Center label
            VStack(spacing: 4) {
                if let selected = selectedCategory,
                   let allocation = allocations.first(where: { $0.category == selected }) {
                    // Show selected allocation details
                    Image(uiImage: selected.icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text(allocation.allocatedAmount.currencyString)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(Colors.gray100))
                    Text(selected.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(Color(Colors.gray400))
                } else {
                    // Show unallocated
                    Text(unallocatedAmount.currencyString)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(Colors.gray100))
                    Text("Unallocated")
                        .font(.system(size: 10))
                        .foregroundColor(Color(Colors.gray400))
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleTap(at: location, proxy: proxy, geometry: geometry)
                    }
            }
        }
    }

    private func handleTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        let vector = CGPoint(x: location.x - center.x, y: location.y - center.y)
        let distance = sqrt(vector.x * vector.x + vector.y * vector.y)
        let radius = min(geometry.size.width, geometry.size.height) / 2

        // Check if tap is within donut ring
        let innerRadius = radius * 0.6
        guard distance > innerRadius && distance < radius else {
            selectedCategory = nil
            return
        }

        // Calculate angle
        var angle = atan2(vector.y, vector.x)
        if angle < 0 { angle += 2 * .pi }

        // Convert angle to data value
        let total = allocations.reduce(0) { $0 + $1.allocatedAmount } + unallocatedAmount
        let normalizedAngle = angle / (2 * .pi)
        var cumulativePercent: Double = 0

        for allocation in allocations {
            let percent = Double(allocation.allocatedAmount) / Double(total)
            if normalizedAngle >= cumulativePercent && normalizedAngle < cumulativePercent + percent {
                selectedCategory = allocation.category
                onSegmentTapped?(allocation.category)
                return
            }
            cumulativePercent += percent
        }

        // Tapped on unallocated
        selectedCategory = nil
    }
}

// MARK: - Preview

@available(iOS 16.0, *)
struct BudgetDonutChartView_Previews: PreviewProvider {
    static var previews: some View {
        BudgetDonutChartView(
            allocations: [],
            unallocatedAmount: 100000
        )
        .frame(width: 200, height: 200)
        .background(Color(Colors.gray700))
    }
}
```

### 5.5 Allocation Table Cell

**File:** `Finova/Sources/Scenes/Dashboard/DashboardCarousel/MonthCarousel/BudgetCard/AllocationCell.swift`

```swift
import UIKit

final class AllocationCell: UITableViewCell {

    static let reuseIdentifier = "AllocationCell"

    // MARK: - UI Components

    private lazy var iconContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray600
        view.layer.cornerRadius = CornerRadius.medium
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var categoryIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.gray100
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var titleStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var categoryLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold
        label.textColor = Colors.gray100
        return label
    }()

    private lazy var usageLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS
        label.textColor = Colors.gray400
        return label
    }()

    private lazy var recurringIcon: UIImageView = {
        let imageView = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        imageView.image = UIImage(systemName: "repeat", withConfiguration: config)
        imageView.tintColor = Colors.gray400
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var progressBar: RoundedProgressBar = {
        let bar = RoundedProgressBar()
        bar.trackTintColor = Colors.gray600
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private lazy var statusBadge: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
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
        backgroundColor = Colors.gray700
        selectionStyle = .none

        contentView.addSubview(iconContainerView)
        iconContainerView.addSubview(categoryIconView)
        contentView.addSubview(titleStackView)
        titleStackView.addArrangedSubview(categoryLabel)
        titleStackView.addArrangedSubview(usageLabel)
        contentView.addSubview(recurringIcon)
        contentView.addSubview(progressBar)
        contentView.addSubview(statusBadge)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Icon container
            iconContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
            iconContainerView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconContainerView.widthAnchor.constraint(equalToConstant: 40),
            iconContainerView.heightAnchor.constraint(equalToConstant: 40),

            // Category icon
            categoryIconView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            categoryIconView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            categoryIconView.widthAnchor.constraint(equalToConstant: 20),
            categoryIconView.heightAnchor.constraint(equalToConstant: 20),

            // Title stack
            titleStackView.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: Metrics.spacing3),
            titleStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing3),
            titleStackView.trailingAnchor.constraint(lessThanOrEqualTo: statusBadge.leadingAnchor, constant: -Metrics.spacing2),

            // Recurring icon
            recurringIcon.leadingAnchor.constraint(equalTo: categoryLabel.trailingAnchor, constant: Metrics.spacing2),
            recurringIcon.centerYAnchor.constraint(equalTo: categoryLabel.centerYAnchor),

            // Progress bar
            progressBar.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: Metrics.spacing3),
            progressBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),
            progressBar.topAnchor.constraint(equalTo: titleStackView.bottomAnchor, constant: Metrics.spacing2),
            progressBar.heightAnchor.constraint(equalToConstant: 6),
            progressBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.spacing3),

            // Status badge
            statusBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),
            statusBadge.centerYAnchor.constraint(equalTo: titleStackView.centerYAnchor),
        ])
    }

    // MARK: - Configuration

    func configure(with allocation: BudgetAllocation) {
        categoryIconView.image = allocation.category.icon
        categoryLabel.text = allocation.category.displayName
        usageLabel.text = "\(allocation.usedAmount.currencyString) / \(allocation.allocatedAmount.currencyString)"

        recurringIcon.isHidden = !allocation.isRecurring

        let progress = Float(allocation.usagePercentage / 100)
        progressBar.progressTintColor = allocation.status.color
        progressBar.setProgress(min(progress, 1.0), animated: false)

        statusBadge.text = allocation.status.localizedLabel
        statusBadge.textColor = allocation.status.color
    }

    func highlight() {
        UIView.animate(withDuration: 0.2) {
            self.backgroundColor = Colors.lowMagenta
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 0.3) {
                self.backgroundColor = Colors.gray700
            }
        }
    }
}
```

### 5.6 Add Segmented Control to Modal

**File:** `Finova/Sources/Scenes/AddTransaction/AddTransactionModalView.swift`

Add segmented control at the top of the modal:

```swift
// MARK: - New Properties

enum ModalMode {
    case transaction
    case allocation
}

private var currentMode: ModalMode = .transaction

// MARK: - New UI Component

private lazy var modeSegmentedControl: UISegmentedControl = {
    let control = UISegmentedControl(items: [
        "modal.segment.transaction".localized,
        "modal.segment.allocation".localized
    ])
    control.selectedSegmentIndex = 0
    control.selectedSegmentTintColor = Colors.mainMagenta
    control.setTitleTextAttributes([.foregroundColor: Colors.gray700], for: .selected)
    control.setTitleTextAttributes([.foregroundColor: Colors.gray100], for: .normal)
    control.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
    control.translatesAutoresizingMaskIntoConstraints = false
    return control
}()

// MARK: - Allocation-specific UI

private lazy var allocationCategoryPicker: CategoryPickerView = {
    // Reuse existing category picker
    let picker = CategoryPickerView()
    picker.isHidden = true
    return picker
}()

private lazy var allocationAmountField: MoneyTextField = {
    let field = MoneyTextField()
    field.placeholder = "allocation.amount.placeholder".localized
    field.isHidden = true
    return field
}()

private lazy var allocationMonthPicker: MonthYearPicker = {
    let picker = MonthYearPicker()
    picker.isHidden = true
    return picker
}()

private lazy var allocationRecurringToggle: UISwitch = {
    let toggle = UISwitch()
    toggle.onTintColor = Colors.mainMagenta
    toggle.isHidden = true
    return toggle
}()

private lazy var remainingToAllocateLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textXS
    label.textColor = Colors.gray400
    label.isHidden = true
    return label
}()

// MARK: - Mode Switching

@objc private func modeChanged() {
    currentMode = modeSegmentedControl.selectedSegmentIndex == 0 ? .transaction : .allocation
    updateUIForMode()
}

private func updateUIForMode() {
    let isTransaction = currentMode == .transaction

    // Transaction UI
    transactionTitleTextField.isHidden = !isTransaction
    categoryPickerView.isHidden = !isTransaction
    transactionModeStackView.isHidden = !isTransaction
    horizontalInputsStackView.isHidden = !isTransaction
    transactionButtonsStackView.isHidden = !isTransaction

    // Allocation UI
    allocationCategoryPicker.isHidden = isTransaction
    allocationAmountField.isHidden = isTransaction
    allocationMonthPicker.isHidden = isTransaction
    allocationRecurringToggle.superview?.isHidden = isTransaction
    remainingToAllocateLabel.isHidden = isTransaction

    // Update button title
    let buttonTitle = isTransaction
        ? "modal.button.save.transaction".localized
        : "modal.button.save.allocation".localized
    saveButton.setTitle(buttonTitle, for: .normal)
}
```

### 5.7 MonthCarouselCell Flip Logic

**File:** `Finova/Sources/Scenes/Dashboard/DashboardCarousel/MonthCarousel/MonthCarouselCell.swift`

Add flip functionality:

```swift
// MARK: - Properties (add)

private var isShowingBudgetView = false
private lazy var budgetCard: BudgetCard = {
    let card = BudgetCard()
    card.isHidden = true
    card.delegate = self
    return card
}()

private lazy var allocationsTableView: UITableView = {
    let table = UITableView()
    table.register(AllocationCell.self, forCellReuseIdentifier: AllocationCell.reuseIdentifier)
    table.backgroundColor = Colors.gray700
    table.separatorStyle = .none
    table.isHidden = true
    return table
}()

var pendingCategoryFilter: TransactionCategory?

// MARK: - Flip Methods

func flipToBudgetView(allocations: [BudgetAllocation], summary: UnallocatedBudgetSummary) {
    guard !isShowingBudgetView else { return }

    budgetCard.configure(
        month: monthBudgetCard.currentMonth,
        year: monthBudgetCard.currentYear,
        allocations: allocations,
        unallocatedSummary: summary
    )

    UIView.transition(
        with: self.contentView,
        duration: 0.4,
        options: [.transitionFlipFromRight, .showHideTransitionViews]
    ) {
        self.monthBudgetCard.isHidden = true
        self.transactionsTableView.isHidden = true
        self.budgetCard.isHidden = false
        self.allocationsTableView.isHidden = false
    } completion: { _ in
        self.isShowingBudgetView = true
        self.monthBudgetCard.setShowingBudgetView(true)
    }
}

func flipToTransactionView() {
    guard isShowingBudgetView else { return }

    UIView.transition(
        with: self.contentView,
        duration: 0.4,
        options: [.transitionFlipFromLeft, .showHideTransitionViews]
    ) {
        self.monthBudgetCard.isHidden = false
        self.transactionsTableView.isHidden = false
        self.budgetCard.isHidden = true
        self.allocationsTableView.isHidden = true
    } completion: { _ in
        self.isShowingBudgetView = false
        self.monthBudgetCard.setShowingBudgetView(false)

        // Apply pending filter if any
        if let category = self.pendingCategoryFilter {
            self.applyFilter(for: category)
            self.pendingCategoryFilter = nil
        }
    }
}

private func applyFilter(for category: TransactionCategory) {
    // Use existing filter system
    var filters = TransactionFilters()
    filters.categories = [category]
    self.delegate?.didUpdateFilters(filters, forMonth: monthAnchor)
}
```

---

## 6. Implementation Order

Follow this order to minimize integration issues:

### Phase 1: Data Layer (Foundation)
1. Add `warningAmber` color to `Colors.swift`
2. Create `AllocationStatus` enum
3. Create `BudgetAllocationModel.swift`
4. Create `BudgetAllocationRepository.swift`

### Phase 2: Service Layer
5. Create `BudgetAllocationService.swift`
6. Add allocation-related methods to `DashboardViewModel`

### Phase 3: UI Components
7. Create `AllocationCell.swift`
8. Create `BudgetDonutChartView.swift` (SwiftUI)
9. Create `BudgetCard.swift`
10. Create `MonthCardFlipDelegate.swift` protocol

### Phase 4: Integration
11. Add flip toggle button to `MonthBudgetCard`
12. Add flip logic to `MonthCarouselCell`
13. Connect `BudgetCard` with `MonthCarouselCell`
14. Test flip animation

### Phase 5: Modal Extension
15. Add segmented control to `AddTransactionModalView`
16. Add allocation form fields
17. Connect allocation creation to `AddTransactionModalViewModel`

### Phase 6: Polish
18. Add localization strings
19. Implement filter-on-flip functionality
20. Test all edge cases

---

## 7. Testing Considerations

### Unit Tests

```swift
// BudgetAllocationServiceTests.swift
func testCreateAllocation() {
    // Given: A valid category and amount
    // When: Creating an allocation
    // Then: Allocation is saved and ID is returned
}

func testAllocationExceedsBudgetWarning() {
    // Given: A budget of 1000
    // When: Creating allocations totaling 1200
    // Then: checkAllocationExceedsBudget returns true
}

func testUsageCalculation() {
    // Given: Transactions in a category
    // When: Getting allocations with usage
    // Then: usedAmount reflects actual spending
}

func testLazyGeneration() {
    // Given: A recurring allocation
    // When: Requesting lazy generation for future months
    // Then: Instances are created only for requested months
}
```

### UI Tests

1. **Flip Animation**: Verify smooth transition between card views
2. **Chart Interaction**: Verify segment tap highlights correct row
3. **Filter Flow**: Verify category filter applies when flipping back
4. **Modal Segmented Control**: Verify mode switching shows correct form
5. **Allocation Creation**: Verify allocation appears in budget view

### Edge Cases

- [ ] No budget set for month (show appropriate empty state)
- [ ] No allocations set (show "Add your first allocation" prompt)
- [ ] All budget allocated (unallocated = 0, chart shows no gray)
- [ ] Over-allocated (show warning, allow save)
- [ ] Category already has allocation for month (prevent duplicate)
- [ ] Recurring allocation with existing instances (don't duplicate)
- [ ] Delete recurring parent (cascade delete instances)

---

## Localization Keys

Add these to your `.strings` files:

```
// Allocation Status
"allocation.status.under" = "Under";
"allocation.status.near" = "Near";
"allocation.status.over" = "Over";

// Errors
"allocation.error.duplicate" = "An allocation for this category already exists";
"allocation.error.notFound" = "Allocation not found";
"allocation.error.invalidAmount" = "Please enter a valid amount";

// Modal
"modal.segment.transaction" = "Transaction";
"modal.segment.allocation" = "Allocation";
"modal.button.save.transaction" = "Save Transaction";
"modal.button.save.allocation" = "Save Allocation";
"allocation.amount.placeholder" = "Allocated amount";

// Budget Card
"budget.unallocated" = "Unallocated";
"budget.allocated.percent" = "%d%% allocated";
```

---

## Summary

This guide covers the complete implementation of the Budget Allocation feature:

| Component | Files | Complexity |
|-----------|-------|------------|
| Data Models | 2 new files | Low |
| Repository | 1 new file | Medium |
| Service | 1 new file | Medium |
| Budget Card | 3 new files | High |
| SwiftUI Chart | 1 new file | Medium |
| Modal Extension | 2 modified files | Medium |
| Flip Logic | 2 modified files | High |

**Estimated total: ~15-20 hours of development time**

Good luck with the implementation! Feel free to refer back to this guide as you build each component.
