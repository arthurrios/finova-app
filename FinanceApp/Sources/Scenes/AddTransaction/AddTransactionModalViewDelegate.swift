//
//  AddTransactionViewDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/05/25.
//

import Foundation

public protocol AddTransactionModalViewDelegate: AnyObject {
    func handleError(title: String, message: String)
    func sendTransactionData(title: String, amount: Int, date: String, category: String, transactionType: String)
    func sendRecurringTransactionData(title: String, amount: Int, date: String, category: String, transactionType: String)
    func sendInstallmentTransactionData(title: String, totalAmount: Int, date: String, category: String, transactionType: String, installments: Int)
    func closeModal()
}
