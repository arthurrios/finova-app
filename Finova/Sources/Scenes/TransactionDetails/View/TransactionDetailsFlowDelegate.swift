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
}
