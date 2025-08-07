//
//  SubCategoryRepositoryProtocol.swift
//  Finova
//
//  Created by Arthur Rios on 05/08/25.
//

import Foundation

enum SubCategoryError: Error, LocalizedError {
    case duplicateName
    
    var errorDescription: String? {
        switch self {
        case .duplicateName:
            return "subCategory.error.duplicateName".localized
        }
    }
}

protocol SubCategoryRepositoryProtocol {
    func createSubCategory(_ subCategory: SubCategory) throws
    func updateSubCategory(_ subCategory: SubCategory) throws
    func deleteSubCategory(id: String) throws
    func fetchAllSubCategories() -> [SubCategory]
    func fetchDefaultSubCategories() -> [SubCategory]
    func fetchSubCategoriesByParent(_ parentCategory: TransactionCategory) -> [SubCategory]
}
