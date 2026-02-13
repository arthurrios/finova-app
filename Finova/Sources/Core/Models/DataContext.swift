//
//  DataContext.swift
//  Finova
//

import Foundation

enum DataContext: Equatable {
    case personal
    case group(BudgetGroup)

    var groupId: String? {
        switch self {
        case .personal: return nil
        case .group(let group): return group.id
        }
    }

    var displayName: String {
        switch self {
        case .personal: return "dashboard.context.personal".localized
        case .group(let group): return group.name
        }
    }

    static func == (lhs: DataContext, rhs: DataContext) -> Bool {
        switch (lhs, rhs) {
        case (.personal, .personal): return true
        case (.group(let a), .group(let b)): return a.id == b.id
        default: return false
        }
    }
}
