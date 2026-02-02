//
//  BudgetAllocationModel.swift
//  Finova
//
//  Created by Arthur Rios on 01/02/26.
//

import UIKit

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
    
    var localizedLabel: String {
        switch self {
        case .underBudget: return "allocation.status.under".localized
        case .nearLimit: return "allocation.status.near".localized
        case .overBudget: return "allocation.status.over".localized
        }
    }
}

// MARK: - Display Model (minimal for scaffolding)

struct BudgetAllocation {
    let id: Int?
    let monthDate: Int
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
    
    static func mock(
        category: TransactionCategory = .meals,
        allocated: Int = 50000,
        used: Int = 37500
    ) -> BudgetAllocation {
        var allocation = BudgetAllocation(
            id: 1,
            monthDate: Int(Date().timeIntervalSince1970),
            category: category,
            allocatedAmount: allocated,
            isRecurring: false,
            parentAllocationId: nil
        )
        allocation.usedAmount = used
        return allocation
    }
}

// MARK: - Unallocated Summary (minimal)

struct UnallocatedBudgetSummary {
    let monthDate: Int
    let totalBudget: Int
    let totalAllocated: Int
    let totalUsedInUnallocatedCategories: Int
    
    var unallocatedAmount: Int { totalBudget - totalAllocated }
    
    static func mock() -> UnallocatedBudgetSummary {
        UnallocatedBudgetSummary(
            monthDate: Int(Date().timeIntervalSince1970),
            totalBudget: 200000,
            totalAllocated: 150000,
            totalUsedInUnallocatedCategories: 25000
        )
    }
}
