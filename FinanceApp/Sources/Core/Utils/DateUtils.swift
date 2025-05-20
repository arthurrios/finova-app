//
//  DateUtils.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/05/25.
//

import Foundation

public struct DateUtils {
    public static func isPastMonth(date: Date) -> Bool {
        let calendar = Calendar.current
        let currentDate = Date()
        
        let currentMonth = calendar.component(.month, from: currentDate)
        let currentYear = calendar.component(.year, from: currentDate)
        
        let dateMonth = calendar.component(.month, from: date)
        let dateYear = calendar.component(.year, from: date)
        
        if dateYear < currentYear {
            return true
        } else if dateYear == currentYear && dateMonth < currentMonth {
            return true
        }
        
        return false
    }
}
