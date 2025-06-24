//
//  UserDefaultsManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation

class UserDefaultsManager {
  private static let userKey = "userKey"
  private static let currentMonthIndex = "currentMonthIndexKey"

  static func saveUser(user: User) {
    let encoder = JSONEncoder()
    if let data = try? encoder.encode(user) {
      UserDefaults.standard.set(data, forKey: userKey)
      UserDefaults.standard.synchronize()
    }
  }

  static func getUser() -> User? {
    if let userData = UserDefaults.standard.data(forKey: userKey) {
      let decoder = JSONDecoder()
      if let user = try? decoder.decode(User.self, from: userData) {
        return user
      }
    }
    return nil
  }

  static func removeUser() {
    UserDefaults.standard.removeObject(forKey: userKey)
    UserDefaults.standard.synchronize()
  }

  static func getCurrentMonthIndex() -> Int {
    return UserDefaults.standard.integer(forKey: currentMonthIndex)
  }

  static func setCurrentMonthIndex(_ index: Int) {
    UserDefaults.standard.set(index, forKey: currentMonthIndex)
  }
}
