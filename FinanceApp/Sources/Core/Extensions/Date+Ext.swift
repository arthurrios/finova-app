//
//  Date+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/05/25.
//

import Foundation

extension Date {
    init(_ dateString: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM"
        
        if let date = dateFormatter.date(from: dateString) {
            self = date
        } else {
            self = Date()
        }
    }
}
