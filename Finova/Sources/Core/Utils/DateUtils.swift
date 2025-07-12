//
//  DateUtils.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/05/25.
//

import Foundation

public struct DateUtils {
    public static func isPastMonth(date: Date) -> Bool {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        
        let now = Date()
        let currentComp = utcCal.dateComponents([.year, .month], from: now)
        let targetComp  = utcCal.dateComponents([.year, .month], from: date)
        
        guard let cY = currentComp.year,
              let cM = currentComp.month,
              let dY = targetComp.year,
              let dM = targetComp.month
        else {
            return false
        }
        
        if dY < cY { return true }
        if dY == cY && dM < cM { return true }
        return false
    }
}
