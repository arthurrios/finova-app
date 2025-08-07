//
//  SubCategoryRepository.swift
//  Finova
//
//  Created by Arthur Rios on 05/08/25.
//

import Foundation

final class SubCategoryRepository: SubCategoryRepositoryProtocol {
    private let dataManager: SecureLocalDataManager
    
    init(dataManager: SecureLocalDataManager) {
        self.dataManager = dataManager
    }
    
    func createSubCategory(_ subCategory: SubCategory) throws {
        // Validate that the name doesn't already exist
        guard dataManager.validateSubCategoryName(subCategory.name, parentCategory: subCategory.parentCategory) else {
            throw SubCategoryError.duplicateName
        }
        
        try dataManager.saveSubCategory(subCategory)
    }
    
    func updateSubCategory(_ subCategory: SubCategory) throws {
        // For updates, we need to check if the name conflicts with OTHER sub-categories
        // (excluding the current one being updated)
        let existingSubCategories = dataManager.fetchSubCategories(for: subCategory.parentCategory)
        let conflictingSubCategory = existingSubCategories.first {
            $0.id != subCategory.id &&
            $0.name.lowercased() == subCategory.name.lowercased()
        }
        
        guard conflictingSubCategory == nil else {
            throw SubCategoryError.duplicateName
        }
        
        try dataManager.saveSubCategory(subCategory)
    }
    
    func deleteSubCategory(id: String) throws {
        try dataManager.deleteSubCategory(id: id)
    }
    
    func fetchAllSubCategories() -> [SubCategory] {
        return dataManager.fetchSubCategories(for: nil)
    }
    
    func fetchDefaultSubCategories() -> [SubCategory] {
        return dataManager.fetchSubCategories(for: nil)
            .filter { $0.isDefault }
            .sorted { $0.name < $1.name }
    }
    
    func fetchSubCategoriesByParent(_ parentCategory: TransactionCategory) -> [SubCategory] {
        return dataManager.fetchSubCategories(for: parentCategory)
            .sorted { $0.name < $1.name }
    }
}
