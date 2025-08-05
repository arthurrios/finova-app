//
//  SubCategory.swift
//  Finova
//
//  Created by Arthur Rios on 31/07/25.
//

import Foundation

struct SubCategory: Codable, Equatable {
    let id: String
    let name: String
    let parentCategory: TransactionCategory
    let isDefault: Bool
    let createdAt: Date
    let userId: String
    
    init(id: String = UUID().uuidString,
         name: String,
         parentCategory: TransactionCategory,
         isDefault: Bool = false,
         createdAt: Date = Date(),
         userId: String) {
        self.id = id
        self.name = name
        self.parentCategory = parentCategory
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.userId = userId
    }
} 