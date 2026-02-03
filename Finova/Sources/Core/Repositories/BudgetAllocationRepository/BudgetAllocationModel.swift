//
//  BudgetAllocationModel.swift
//  Finova
//
//  Created by Arthur Rios on 01/02/26.
//

import UIKit

// MARK: - Database Model

struct BudgetAllocationModel: Codable {
    
    let id: Int?
    let monthDate: Int
    let categoryKey: String
    let allocatedAmount: Int
    let isRecurring: Bool
    let parentAllocationId: Int?
    
    init(id: Int? = nil,
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

// MARK: - Allocation Status Enum

enum AllocationStatus {
    
    case underBudget
    case nearLimit
    case overBudget
    
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

// MARK: - Display Model

struct BudgetAllocation: Identifiable {

    let dbId: Int?
    let monthDate: Int

    /// Stable identifier for SwiftUI ForEach - uses category key + monthDate
    var id: String {
        "\(category.key)_\(monthDate)"
    }
    let category: TransactionCategory
    let allocatedAmount: Int
    let isRecurring: Bool
    let parentAllocationId: Int?
    
    var usedAmount: Int = 0
    
    var remainingAmount: Int { allocatedAmount - usedAmount }
    
    var usagePercentage: Double {
        guard allocatedAmount > 0 else { return 0 }
        return Double(usedAmount) / Double(allocatedAmount) * 100
    }
    
    var status: AllocationStatus {
        let pct = usagePercentage
        if pct > 100 { return .overBudget }
        else if pct >= 80 { return .nearLimit }
        else { return .underBudget }
    }
    
    init(
        dbId: Int? = nil,
        monthDate: Int,
        category: TransactionCategory,
        allocatedAmount: Int,
        isRecurring: Bool = false,
        parentAllocationId: Int? = nil,
        usedAmount: Int = 0
    ) {
        self.dbId = dbId
        self.monthDate = monthDate
        self.category = category
        self.allocatedAmount = allocatedAmount
        self.isRecurring = isRecurring
        self.parentAllocationId = parentAllocationId
        self.usedAmount = usedAmount
    }

    init(from model: BudgetAllocationModel) {
        self.dbId = model.id
        self.monthDate = model.monthDate
        self.category = TransactionCategory.allCases.first {
            $0.key == model.categoryKey
        } ?? .miscellaneous
        self.allocatedAmount = model.allocatedAmount
        self.isRecurring = model.isRecurring
        self.parentAllocationId = model.parentAllocationId
        self.usedAmount = 0
    }

    mutating func setUsedAmount(_ amount: Int) {
        self.usedAmount = amount
    }

    static func mock(
        category: TransactionCategory = .meals,
        allocated: Int = 50000,
        isReccuring: Bool = false,
        used: Int = 37500
    ) -> BudgetAllocation {
        BudgetAllocation(
            dbId: Int.random(in: 1...1000),
            monthDate: Int(Date().timeIntervalSince1970),
            category: category,
            allocatedAmount: allocated,
            isRecurring: isReccuring,
            usedAmount: used
        )
    }
}

// MARK: - Unallocated Summary

struct UnallocatedBudgetSummary {
    
    let monthDate: Int
    let totalBudget: Int
    let totalAllocated: Int
    let totalUsedInUnallocatedCategories: Int
    
    var unallocatedAmount: Int { totalBudget - totalAllocated }
    
    var unallocatedRemaining: Int { unallocatedAmount - totalUsedInUnallocatedCategories }
    
    var isOverspent: Bool {
        unallocatedRemaining < 0
    }
    
    static func mock() -> UnallocatedBudgetSummary {
        UnallocatedBudgetSummary(
            monthDate: Int(Date().timeIntervalSince1970),
            totalBudget: 200000,
            totalAllocated: 150000,
            totalUsedInUnallocatedCategories: 25000
        )
    }
}


// MARK: - Allocation Edit Option

enum AllocationEditOption {
    case currentOnly    // Edit only this month's allocation
    case futureOnly     // Edit this month and all future allocations
    case all            // Edit all occurrences (past, present, future)
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
