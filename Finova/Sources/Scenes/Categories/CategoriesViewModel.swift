//
//  CategoriesViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 31/07/25.
//

import Foundation

final class CategoriesViewModel: ObservableObject {
    
    // MARK: - Callbacks
    var onSubCategoriesUpdated: ((TransactionCategory, [SubCategory]) -> Void)?
    
    // MARK: - Properties
    private var subCategoriesData: [TransactionCategory: [SubCategory]] = [:]
    
    // MARK: - Public Methods
    func loadSubCategoriesForAllCategories() {
        // TODO: Load from repository when implemented
        loadMockSubCategories()
    }
    
    func loadSubCategories(for category: TransactionCategory) {
        // TODO: Load from repository when implemented
        let subCategories = subCategoriesData[category] ?? []
        onSubCategoriesUpdated?(category, subCategories)
    }
    
    func createSubCategory(name: String, parentCategory: TransactionCategory, isDefault: Bool = false) {
        let subCategory = SubCategory(
            name: name,
            parentCategory: parentCategory,
            isDefault: isDefault,
            userId: getCurrentUserId()
        )
        
        // TODO: Save to repository when implemented
        if subCategoriesData[parentCategory] == nil {
            subCategoriesData[parentCategory] = []
        }
        subCategoriesData[parentCategory]?.append(subCategory)
        
        onSubCategoriesUpdated?(parentCategory, subCategoriesData[parentCategory] ?? [])
    }
    
    func updateSubCategory(_ subCategory: SubCategory) {
        // TODO: Update in repository when implemented
        if let index = subCategoriesData[subCategory.parentCategory]?.firstIndex(of: subCategory) {
            subCategoriesData[subCategory.parentCategory]?[index] = subCategory
            onSubCategoriesUpdated?(subCategory.parentCategory, subCategoriesData[subCategory.parentCategory] ?? [])
        }
    }
    
    func deleteSubCategory(_ subCategory: SubCategory) {
        // TODO: Delete from repository when implemented
        subCategoriesData[subCategory.parentCategory]?.removeAll { $0.id == subCategory.id }
        onSubCategoriesUpdated?(subCategory.parentCategory, subCategoriesData[subCategory.parentCategory] ?? [])
    }
    
    // MARK: - Private Methods
    private func getCurrentUserId() -> String {
        // TODO: Get from authentication manager when implemented
        return "current-user-id"
    }
    
    private func loadMockSubCategories() {
        print("🔍 Loading mock sub-categories...")
        
        // Mock data for demonstration with more sub-categories to test dynamic height
        let mockSubCategories: [TransactionCategory: [SubCategory]] = [
            .groceries: [
                SubCategory(name: "Fresh Produce", parentCategory: .groceries, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Dairy", parentCategory: .groceries, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Pantry Items", parentCategory: .groceries, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Beverages", parentCategory: .groceries, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Snacks", parentCategory: .groceries, isDefault: true, userId: getCurrentUserId())
            ],
            .entertainment: [
                SubCategory(name: "Movies", parentCategory: .entertainment, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Restaurants", parentCategory: .entertainment, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Concerts", parentCategory: .entertainment, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Games", parentCategory: .entertainment, isDefault: true, userId: getCurrentUserId())
            ],
            .transportation: [
                SubCategory(name: "Fuel", parentCategory: .transportation, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Public Transport", parentCategory: .transportation, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Parking", parentCategory: .transportation, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Maintenance", parentCategory: .transportation, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Insurance", parentCategory: .transportation, isDefault: true, userId: getCurrentUserId())
            ],
            .healthcare: [
                SubCategory(name: "Doctor Visits", parentCategory: .healthcare, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Medications", parentCategory: .healthcare, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Dental Care", parentCategory: .healthcare, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Vision Care", parentCategory: .healthcare, isDefault: true, userId: getCurrentUserId())
            ],
            .utilities: [
                SubCategory(name: "Electricity", parentCategory: .utilities, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Water", parentCategory: .utilities, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Gas", parentCategory: .utilities, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Internet", parentCategory: .utilities, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Phone", parentCategory: .utilities, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Garbage", parentCategory: .utilities, isDefault: true, userId: getCurrentUserId())
            ],
            .salary: [
                SubCategory(name: "Regular Salary", parentCategory: .salary, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Bonus", parentCategory: .salary, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Overtime", parentCategory: .salary, isDefault: true, userId: getCurrentUserId())
            ],
            .education: [
                SubCategory(name: "Tuition", parentCategory: .education, isDefault: true, userId: getCurrentUserId())
            ],
            .clothing: [
                SubCategory(name: "Casual Wear", parentCategory: .clothing, isDefault: true, userId: getCurrentUserId()),
                SubCategory(name: "Formal Wear", parentCategory: .clothing, isDefault: true, userId: getCurrentUserId())
            ]
        ]
        
        subCategoriesData = mockSubCategories
        
        print("🔍 Mock data loaded for \(subCategoriesData.count) categories")
        print("🔍 Categories with data: \(subCategoriesData.keys.map { $0.rawValue })")
        
        // Notify all categories
        for category in TransactionCategory.allCases {
            let subCategories = subCategoriesData[category] ?? []
            print("🔍 Notifying category: \(category.rawValue) with \(subCategories.count) sub-categories")
            onSubCategoriesUpdated?(category, subCategories)
        }
    }
}
