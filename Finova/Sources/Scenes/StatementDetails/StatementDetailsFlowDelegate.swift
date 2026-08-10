//
//  StatementDetailsFlowDelegate.swift
//  Finova
//

import UIKit

protocol StatementDetailsFlowDelegate: AnyObject {
    func dismissStatementDetails()
    func payStatement(card: CreditCard, statement: CreditCardStatement)
    func didMarkStatementAsPaid()
    func didDeleteTransactionInStatement()
    func navigateToTransactionDetails(transaction: Transaction)
}
