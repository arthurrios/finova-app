//
//  StatementDetailsFlowDelegate.swift
//  Finova
//

import UIKit

protocol StatementDetailsFlowDelegate: AnyObject {
    func dismissStatementDetails()
    func didMarkStatementAsPaid()
    func didDeleteTransactionInStatement()
    func navigateToTransactionDetails(transaction: Transaction)
}
