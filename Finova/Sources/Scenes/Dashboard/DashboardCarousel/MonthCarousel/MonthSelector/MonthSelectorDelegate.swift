//
//  MonthSelectorDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 12/05/25.
//

import Foundation

protocol MonthSelectorDelegate: AnyObject {
    func didTapPrev()
    func didTapNext()
    func didSelectMonth(at index: Int)
}
