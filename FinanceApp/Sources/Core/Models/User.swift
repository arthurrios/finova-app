//
//  UserLoginModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation

struct User: Codable {
    let name: String
    let email: String
    var isUserSaved: Bool = false
    var hasFaceIdEnabled: Bool = false
}
