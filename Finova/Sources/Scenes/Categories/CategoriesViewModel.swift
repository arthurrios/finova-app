//
//  CategoriesViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 31/07/25.
//

import Foundation
import Combine

@MainActor
final class CategoriesViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var categories: [TransactionCategory] = []
    @Published var subCategories: [SubCategory] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedCategory: TransactionCategory?
    
    // MARK: - Private Properties
    private let subCategoryRepository: SubCategoryRepository
    private var cancellables: Set<AnyCancellable> = []
    
    // MARK: - Initialization
    init(subCategoryRepository: SubCategoryRepository) {
        self.subCategoryRepository = subCategoryRepository
        setupCategories()
    }
    
    // MARK: - Public Methods
    func loadData() {
        isLoading = true
        errorMessage = nil
        
        subCategories = subCategoryRepository.fetchAllSubCategories()
        isLoading = false
    }
    
    func loadSubCategories(for category: TransactionCategory) {
        selectedCategory = category
        subCategories = subCategoryRepository.fetchSubCategoriesByParent(category)
    }
    
    func createSubCategory(name: String, parentCategory: TransactionCategory, isDefault: Bool = false) {
        isLoading = true
        errorMessage = nil
        
        let subCategory = SubCategory(
            name: name,
            parentCategory: parentCategory,
            isDefault: isDefault,
            userId: getCurrentUserId()
        )
        
        do {
            try subCategoryRepository.createSubCategory(subCategory)
            loadData()
        } catch SubCategoryError.duplicateName {
            errorMessage = SubCategoryError.duplicateName.localizedDescription
        } catch {
            errorMessage = "An error occurred while creating the sub-category"
        }
        
        isLoading = false
    }
    
    
    // MARK: - Helper Methods
    private func setupCategories() {
        categories = TransactionCategory.allCases
    }
    
    private func getCurrentUserId() -> String {
        return SecureLocalDataManager.shared.getCurrentUserUID() ?? ""
    }
    
    
}
