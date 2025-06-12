//
//  AddTransactionModalViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/05/25.
//

import Foundation

final class AddTransactionModalViewModel {
    private let transactionRepo: TransactionRepository
    private let recurringManager: RecurringTransactionManager
    
    init(transactionRepo: TransactionRepository = TransactionRepository()) {
        self.transactionRepo = transactionRepo
        self.recurringManager = RecurringTransactionManager(transactionRepo: transactionRepo)
    }
    
    func addTransaction(
        title: String,
        amount: Int,
        dateString: String,
        categoryKey: String,
        typeRaw: String,
        isRecurring: Bool? = nil
    ) -> Result<Void, Error> {
        
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
            .first(where: { String(describing: $0) == typeRaw })
        else {
            return .failure(TransactionError.invalidType)
        }
        
        let anchor = date.monthAnchor
        
        if let isRecurring = isRecurring, isRecurring {
            
            let model = TransactionModel(
                title: title,
                category: category.key,
                amount: amount,
                type: type.key,
                dateTimestamp: timestamp,
                budgetMonthDate: anchor,
                isRecurring: true
            )
            
            do {
                try transactionRepo.insertTransaction(model)
                
                let monthRange: ClosedRange<Int> = 0...24
                recurringManager.generateRecurringTransactionsForRange(monthRange)
                
                return .success(())
            } catch {
                return .failure(error)
            }
        } else {
            let model = TransactionModel(
                title: title,
                category: category.key,
                amount: amount,
                type: type.key,
                dateTimestamp: timestamp,
                budgetMonthDate: anchor,
                isRecurring: false
            )
            
            do {
                try transactionRepo.insertTransaction(model)
                return .success(())
            } catch {
                return .failure(error)
            }
        }
    }
    
    func addTransactionWithInstallments(
        title: String,
        totalAmount: Int,
        dateString: String,
        categoryKey: String,
        typeRaw: String,
        totalInstallments: Int
    ) -> Result<Void, Error> {
        guard totalInstallments > 1 else {
            return .failure(TransactionError.invalidInstallmentCount)
        }
        
        guard let startDate = DateFormatter.fullDateFormatter.date(from: dateString) else {
            return .failure(TransactionError.invalidDateFormat)
        }
        
        guard let category = TransactionCategory.allCases
                .first(where: { $0.key == categoryKey })
        else {
            return .failure(TransactionError.invalidCategory)
        }

        guard let type = TransactionType.allCases
                .first(where: { String(describing: $0) == typeRaw })
        else {
            return .failure(TransactionError.invalidType)
        }
        
        let amountPerInstallment = totalAmount / totalInstallments
        let remainder = totalAmount % totalInstallments
        
        do {
            let parentModel = TransactionModel(
                title: title,
                category: category.key,
                amount: totalAmount,
                type: type.key,
                dateTimestamp: Int(startDate.timeIntervalSince1970),
                budgetMonthDate: startDate.monthAnchor,
                hasInstallments: true,
                originalAmount: totalAmount,
                totalInstallments: totalInstallments
            )
            
            let parentId = try transactionRepo.insertTransactionAndGetId(parentModel)
            
            for installmentNumber in 1...totalInstallments {
                let installmentDate = Calendar.current.date(byAdding: .month, value: installmentNumber - 1, to: startDate) ?? startDate
                let installmentAmount = installmentNumber == 1 ? amountPerInstallment + remainder : amountPerInstallment
                
                let installmentModel = TransactionModel(
                     title: title,
                     category: category.key,
                     amount: installmentAmount,
                     type: type.key,
                     dateTimestamp: Int(installmentDate.timeIntervalSince1970),
                     budgetMonthDate: installmentDate.monthAnchor,
                     parentTransactionId: parentId,
                     originalAmount: totalAmount,
                     installmentNumber: installmentNumber,
                     totalInstallments: totalInstallments
                 )
                
                try transactionRepo.insertTransaction(installmentModel)
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
