//
//  CategoriesViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 31/07/25.
//

import Foundation

final class CategoriesViewModel: ObservableObject {
    @Published var categories: [TransactionCategory] = []
//    @Published var subCategories: [SubCategory] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    init() {}
}
