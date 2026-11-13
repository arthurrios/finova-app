//
//  StatementPaymentFlowDelegate.swift
//  Finova
//

import Foundation

protocol StatementPaymentFlowDelegate: AnyObject {
    func dismissStatementPayment()
    func didCompleteStatementPayment(paymentId: Int)
}
