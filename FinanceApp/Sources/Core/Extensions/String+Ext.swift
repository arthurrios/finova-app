//
//  String+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 08/05/25.
//

import Foundation

extension String {
  var localized: String {
    NSLocalizedString(self, comment: "")
  }

  func localized(_ args: CVarArg...) -> String {
    let format = NSLocalizedString(self, comment: "")
    return String(
      format: format,
      locale: Locale.current,
      arguments: args
    )
  }
}
