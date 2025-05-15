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
    private(set) var monthData: [MonthBudgetCardType] = []
    private(set) var allTransactions: [Transaction] = []
    private(set) var selectedIndex: Int = 0
    
    weak var delegate: SyncedCollectionsViewModelDelegate?
    
    // MARK: - Initialization
    init(monthData: [MonthBudgetCardType] = [], transactions: [Transaction] = [], initialIndex: Int = 0) {
        self.monthData = monthData
        self.allTransactions = transactions
        self.selectedIndex = initialIndex
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
        let clampedIndex = min(max(index, 0), monthData.count - 1)
        if clampedIndex != selectedIndex {
            selectedIndex = clampedIndex
            delegate?.didUpdateSelectedIndex(clampedIndex, animated: animated)
        }
    }
    
    func moveToNextMonth(animated: Bool = true) {
        selectMonth(at: selectedIndex + 1, animated: animated)
    }
    
    func moveToPreviousMonth(animated: Bool = true) {
        selectMonth(at: selectedIndex - 1, animated: animated)
    }
    
    func getTransactionsForCurrentMonth() -> [Transaction] {
        guard !monthData.isEmpty, selectedIndex < monthData.count else { return [] }
        
        let selectedMonth = monthData[selectedIndex]
        let key = DateFormatter.keyFormatter.string(from: selectedMonth.date)
        
        return allTransactions.filter { transaction in
            DateFormatter.keyFormatter.string(from: transaction.date) == key
        }
    }
    
    func getMonthTitles() -> [String] {
        return monthData.map { $0.month }
    }
    
    func getCurrentMonthData() -> MonthBudgetCardType? {
        guard !monthData.isEmpty, selectedIndex < monthData.count else { return nil }
        return monthData[selectedIndex]
    }
}
