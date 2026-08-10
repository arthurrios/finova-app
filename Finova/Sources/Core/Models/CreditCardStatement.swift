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
        // A payment dated in the future is scheduled, not settled. The credit is already applied — so
        // the balance and every forecast are correct from the moment the user confirms — but calling
        // an invoice "paid" weeks before the money moves reads wrong, and banks show it as
        // "pagamento agendado" until the date arrives. This is the only place that distinction lives:
        // nothing is persisted for it, so it flips to `.paid` on its own once the day passes.
        if isPaid { return (paidDate.map { $0 > Date() } ?? false) ? .scheduled : .paid }
        if Date() > dueDate { return .overdue }
        if Date() > closingDate { return .closed }
        return .open
    }
}

enum StatementStatus: String, Codable {
    case open, closed, paid, overdue, scheduled

    var displayName: String {
        "statementStatus.\(rawValue)".localized
    }

    var color: UIColor {
        switch self {
        case .open: return Colors.mainGreen
        case .closed: return Colors.warningAmber
        case .paid: return Colors.gray500
        case .overdue: return Colors.mainRed
        case .scheduled: return Colors.mainGreen
        }
    }
}
