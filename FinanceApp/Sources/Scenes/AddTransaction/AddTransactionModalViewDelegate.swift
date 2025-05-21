//
//  AddTransactionViewDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/05/25.
//

import Foundation

public protocol AddTransactionModalViewDelegate: AnyObject {
    func handleError(message: String)
    func sendTransactionData(title: String, amount: Int, date: String, category: String, transactionType: String)
    func closeModal()
}
