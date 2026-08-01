//
//  TransactionDetailsFlowDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 05/09/25.
//

protocol TransactionDetailsFlowDelegate: AnyObject {
    func dismissTransactionDetails()
    func editTransaction(_ transaction: Transaction)
    func didDeleteTransaction()
    /// Opens the installment-selection screen for the series `transaction` belongs to.
    func payInstallmentsEarly(for transaction: Transaction)
    /// The purchase was cancelled; `refundId` is the credit that was created.
    func didCancelInstallmentPurchase(refundId: Int)
}
