//
//  LoginFlowDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation

public protocol LoginFlowDelegate: AnyObject {
    func sendLoginData(name: String, email: String, password: String)
}
