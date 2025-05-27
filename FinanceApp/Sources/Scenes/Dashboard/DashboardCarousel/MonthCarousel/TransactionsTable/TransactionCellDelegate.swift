//
//  TransactionCellDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 26/05/25.
//

import Foundation

public protocol TransactionCellDelegate: AnyObject {
    func transactionCellDidRequestDelete(_ cell: TransactionCell)
}
