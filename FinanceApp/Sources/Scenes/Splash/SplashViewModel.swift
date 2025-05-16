//
//  SplashViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation

final class SplashViewModel {
    private let calendar = Calendar.current
    private let monthRange: ClosedRange<Int>
    
    init(monthRange: ClosedRange<Int> = -12...24) { // 3 years
        self.monthRange = monthRange
    }
    
    func performInitialAnimation(completion: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            completion()
        }
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
}
