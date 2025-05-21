//
//  AddTransactionModalViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/05/25.
//

import Foundation

final class AddTransactionModalViewModel {
    func addTransaction(title: String, amount: Int, date: String, category: String, transactionType: String) {
        print(title, amount, date, category, transactionType)
    }
}
