//
//  MonthBudgetCardDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/05/25.
//

import Foundation

public protocol MonthBudgetCardDelegate: AnyObject {
  func didTapConfigButton()
  func didTapDefineBudgetButton(budgetDate: Date)
  /// The balance adjustment was asked for — from the pencil's menu, or from the long press that
  /// used to be the only way in. Named for the intent rather than the gesture now that there is
  /// more than one gesture behind it.
  func didRequestBalanceAdjustment()
}
