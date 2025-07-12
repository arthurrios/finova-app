//
//  TextCasing.swift
//  FinanceApp
//
//  Created by Arthur Rios on 08/05/25.
//

import Foundation

enum TextCasing {
    case none
    case uppercase
    case lowercase
    case capitalize
    
    func apply(to text: String) -> String {
        switch self {
        case .none:        return text
        case .uppercase:   return text.uppercased()
        case .lowercase:   return text.lowercased()
        case .capitalize:  return text.capitalized
        }
    }
}
