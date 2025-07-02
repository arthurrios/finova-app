//
//  SyncedCollectionsViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation
import UIKit

protocol SyncedCollectionsViewModelDelegate: AnyObject {
    func didUpdateSelectedIndex(_ index: Int, animated: Bool)
    func didUpdateMonthData(_ data: [MonthBudgetCardType])
    func didUpdateTransactions(_ transactions: [Transaction])
}

final class SyncedCollectionsViewModel {
    // MARK: - Properties
    private let calendar = Calendar.current
    private(set) var monthData: [MonthBudgetCardType] = []
    private(set) var allTransactions: [Transaction] = []
    private(set) var selectedIndex: Int = 0
    private let monthRange: ClosedRange<Int>
    
    weak var delegate: SyncedCollectionsViewModelDelegate?
    
    // MARK: - Initialization
    init(monthData: [MonthBudgetCardType] = [], transactions: [Transaction] = [], initialIndex: Int = 0, monthRange: ClosedRange<Int> = -12...24) {
        self.monthData = monthData
        self.allTransactions = transactions
        self.selectedIndex = initialIndex
        self.monthRange = monthRange
    }
    
    // MARK: - Public Methods
    func setMonthData(_ data: [MonthBudgetCardType]) {
        monthData = data
        delegate?.didUpdateMonthData(data)
    }
    
    func setTransactions(_ transactions: [Transaction]) {
        allTransactions = transactions
        delegate?.didUpdateTransactions(transactions)
    }
    
    func selectMonth(at index: Int, animated: Bool = true) {
        let clampedIndex = min(max(index, 0), monthRange.count - 1)
        if clampedIndex != selectedIndex {
            selectedIndex = clampedIndex
            DispatchQueue.main.async {
                self.delegate?.didUpdateSelectedIndex(clampedIndex, animated: animated)
            }
        }
    }
    
    func saveInitialDate() {
        UserDefaultsManager.setCurrentMonthIndex(currentMonthIndex)
    }
    
    var currentMonthIndex: Int {
        let today = Date()
        let components = calendar.dateComponents([.year, .month], from: today)
        
        let allDates = monthRange.map { offset in
            calendar.date(byAdding: .month, value: offset, to: today)!
        }
        
        return allDates.firstIndex {
            let dComp = calendar.dateComponents([.year, .month], from: $0)
            return dComp.year == components.year && dComp.month == components.month
        } ?? monthRange.lowerBound
    }
    
    private func updateAvailableValuesForAllMonths() {
        guard !monthData.isEmpty else { return }

        var updatedMonthData = monthData

        for index in 0..<updatedMonthData.count {
            let dateKey = DateFormatter.keyFormatter.string(from: updatedMonthData[index].date)

            let total = allTransactions
                .filter { DateFormatter.keyFormatter.string(from: $0.date) == dateKey }
                .reduce(0) { result, transaction in
                    transaction.type == .income ? result + transaction.amount : result - transaction.amount
                }

            updatedMonthData[index].finalBalance = total
        }

        monthData = updatedMonthData
    }

    func moveToNextMonth(animated: Bool = true) {
        selectMonth(at: selectedIndex + 1, animated: animated)
    }
    
    func moveToPreviousMonth(animated: Bool = true) {
        selectMonth(at: selectedIndex - 1, animated: animated)
    }
    
    func sumMonthTransactions() -> Int {
        return getTransactionsForCurrentMonth().reduce(0) { result, transaction in
            if transaction.type == .income {
                return result + transaction.amount
            } else {
                return result - transaction.amount
            }
        }
    }
    
    func getTransactionsForCurrentMonth() -> [Transaction] {
        guard !monthData.isEmpty, selectedIndex < monthData.count else { return [] }
        
        let selectedMonth = monthData[selectedIndex]
        let key = DateFormatter.keyFormatter.string(from: selectedMonth.date)
            
        return allTransactions.filter { transaction in
            DateFormatter.keyFormatter.string(from: transaction.date) == key
        }
    }
    
    func getMonths() -> [String] {
        let today = Date()

        return monthRange.compactMap { offset in
            let date = calendar.date(byAdding: .month, value: offset, to: today)!
            let month = DateFormatter.monthFormatter.string(from: date)
            return "month.\(month.lowercased())".localized
        }
    }
    
    func getCurrentMonthData() -> MonthBudgetCardType? {
        guard !monthData.isEmpty, selectedIndex < monthData.count else { return nil }
        return monthData[selectedIndex]
    }
    
    func removeTransaction(withId id: Int) {
        allTransactions.removeAll { $0.id == id }
        delegate?.didUpdateTransactions(allTransactions)
    }
}
