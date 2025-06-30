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
    private let carouselRange: ClosedRange<Int> = -12...24
    private let calendar = Calendar.current
    
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
        
        guard
            let category = TransactionCategory.allCases
                .first(where: { $0.key == categoryKey })
        else {
            return .failure(TransactionError.invalidCategory)
        }
        
        guard
            let type = TransactionType.allCases
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
                let insertedId = try transactionRepo.insertTransactionAndGetId(model)
                try transactionRepo.updateParentTransactionId(
                    transactionId: insertedId, parentId: insertedId)
                
                // Use a more inclusive range to ensure the original transaction date is included
                let today = Date()
                
                // Calculate how many months back we need to go to include the transaction date
                let monthsBack = max(
                    12, calendar.dateComponents([.month], from: date, to: today).month ?? 0)
                let inclusiveRange = -monthsBack...24
                
                recurringManager.generateRecurringTransactionsForRange(
                    inclusiveRange,
                    referenceDate: today,
                    transactionStartDate: date
                )
                
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
        _ data: InstallmentTransactionData
    ) -> Result<Void, Error> {
        let totalInstallments = data.installments
        guard totalInstallments > 1 else {
            return .failure(TransactionError.invalidInstallmentCount)
        }
        
        guard let startDate = DateFormatter.fullDateFormatter.date(from: data.date) else {
            return .failure(TransactionError.invalidDateFormat)
        }
        
        guard
            let category = TransactionCategory.allCases
                .first(where: { $0.key == data.category })
        else {
            return .failure(TransactionError.invalidCategory)
        }
        
        guard
            let type = TransactionType.allCases
                .first(where: { String(describing: $0) == data.transactionType })
        else {
            return .failure(TransactionError.invalidType)
        }
        
        let amountPerInstallment = data.totalAmount / totalInstallments
        let remainder = data.totalAmount % totalInstallments
        
        do {
            // Create a placeholder parent (NOT visible in UI)
            // This is used only for linking installments together
            let parentModel = TransactionModel(
                title: "\(data.title) - Installment Parent",  // Mark it clearly as parent
                category: category.key,
                amount: 0,  // Zero amount so it doesn't affect totals
                type: type.key,
                dateTimestamp: Int(startDate.timeIntervalSince1970),
                budgetMonthDate: startDate.monthAnchor,
                hasInstallments: true,
                originalAmount: data.totalAmount,
                totalInstallments: totalInstallments
            )
            
            let parentId = try transactionRepo.insertTransactionAndGetId(parentModel)
            
            for installmentNumber in 1...totalInstallments {
                let installmentDate =
                Calendar.current.date(byAdding: .month, value: installmentNumber - 1, to: startDate)
                ?? startDate
                let installmentAmount =
                installmentNumber == 1 ? amountPerInstallment + remainder : amountPerInstallment
                
                let installmentModel = TransactionModel(
                    title: data.title,
                    category: category.key,
                    amount: installmentAmount,
                    type: type.key,
                    dateTimestamp: Int(installmentDate.timeIntervalSince1970),
                    budgetMonthDate: installmentDate.monthAnchor,
                    parentTransactionId: parentId,
                    originalAmount: data.totalAmount,
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
