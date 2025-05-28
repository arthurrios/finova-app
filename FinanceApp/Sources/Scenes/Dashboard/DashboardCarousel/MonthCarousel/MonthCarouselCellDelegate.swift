//
//  MonthCarouselCellDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 27/05/25.
//

import Foundation

protocol MonthCarouselCellDelegate: AnyObject {
    func monthCarouselCell(_ cell: MonthCarouselCell, didUpdateHeight height: CGFloat)
}
