//
//  DashboardViewDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation

protocol DashboardViewDelegate: AnyObject {
  func didTapAddTransaction()
  func didTapProfile()
  func didTapNotifications()
  func didTapContextSwitch()
  func dashboardViewDidRequestRefresh(_ dashboardView: DashboardView)
}
