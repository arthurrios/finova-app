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
  
  /// Normalizes a string for search by removing accents and converting to lowercase
  /// Example: "Dízimo" becomes "dizimo"
  func normalizedForSearch() -> String {
    return self.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
  }
}
