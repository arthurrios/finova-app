//
//  CreditCardStatement.swift
//  Finova
//
//  Created by Arthur Rios on 07/02/26.
//

import Foundation
import UIKit

struct CreditCardStatement: Codable {
    var id: Int?
    var creditCardId: Int
    var closingDate: Date
    var dueDate: Date
    var totalAmount: Int
    var isPaid: Bool
    var paidDate: Date?
    var paidAmount: Int?
    var isDatesOverridden: Bool
    var userId: String
    var createdAt: Date
    var updatedAt: Date
    
    var status: StatementStatus {
        if isPaid { return .paid }
        if Date() > dueDate { return .overdue }
        if Date() > closingDate { return .closed }
        return .open
    }
}

enum StatementStatus: String, Codable {
    case open, closed, paid, overdue
    
    var displayName: String {
        "statementStatus.\(rawValue)".localized
    }
    
    var color: UIColor {
        switch self {
        case .open: return Colors.mainGreen
        case .closed: return Colors.warningAmber
        case .paid: return Colors.gray500
        case .overdue: return Colors.mainRed
        }
    }
}
