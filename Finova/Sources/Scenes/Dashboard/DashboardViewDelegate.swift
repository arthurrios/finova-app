//
//  DashboardViewDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation

public protocol DashboardViewDelegate: AnyObject {
    func didTapAddTransaction()
    func didTapProfileImage()
    func logout()
    func didTapSettings()
}
