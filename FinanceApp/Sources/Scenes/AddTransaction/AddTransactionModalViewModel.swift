//
//  AddTransactionModalViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/05/25.
//

import Foundation

final class AddTransactionModalViewModel {
    private let transactionRepo: TransactionRepository
    
    enum TransactionError: Error {
        case invalidDateFormat
        case invalidCategory
        case invalidType
    }
    
    init(transactionRepo: TransactionRepository = TransactionRepository()) {
        self.transactionRepo = transactionRepo
    }
    
    func addTransaction(title: String, amount: Int, dateString: String, categoryKey: String, typeRaw: String) -> Result<Void, Error> {
        
        guard let date = DateFormatter.fullDateFormatter.date(from: dateString) else {
            return .failure(TransactionError.invalidDateFormat)
        }
        
        let timestamp = Int(date.timeIntervalSince1970)
        
        guard let category = TransactionCategory.allCases
                .first(where: { $0.key == categoryKey })
        else {
            return .failure(TransactionError.invalidCategory)
        }

        guard let type = TransactionType.allCases
                .first(where: { $0.key == typeRaw })
        else {
            return .failure(TransactionError.invalidType)
        }
        
        let anchor = date.monthAnchor
        
        let model = TransactionModel(
            title: title,
            category: category.key,
            amount: amount,
            type: type.key,
            dateTimestamp: timestamp,
            budgetMonthDate: anchor
        )
        
        do {
            try transactionRepo.insertTransaction(model)
            print(#function, "Transaction added successfully")
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
