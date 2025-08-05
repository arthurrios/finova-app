//
//  CategoriesViewController.swift
//  Finova
//
//  Created by Arthur Rios on 31/07/25.
//

import UIKit

final class CategoriesViewController: UIViewController {
    
    let contentView: CategoriesView
    let viewModel: CategoriesViewModel
    weak var flowDelegate: CategoriesFlowDelegate?
    
    init(
        contentView: CategoriesView,
        viewModel: CategoriesViewModel,
        flowDelegate: CategoriesFlowDelegate
    ) {
        self.contentView = contentView
        self.viewModel = viewModel
        self.flowDelegate = flowDelegate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        loadData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
    }
    
    private func setup() {
        contentView.delegate = self
        contentView.frame = view.bounds
        view.addSubview(contentView)
        
        // Bind view model
        viewModel.onSubCategoriesUpdated = { [weak self] category, subCategories in
            self?.contentView.updateSubCategories(subCategories, for: category)
        }
    }
    
    private func loadData() {
        viewModel.loadSubCategoriesForAllCategories()
    }
}

// MARK: - CategoriesViewDelegate
extension CategoriesViewController: CategoriesViewDelegate {
    func didTapSubCategoryManagement(for category: TransactionCategory) {
        flowDelegate?.navigateToSubCategoryManagement()
    }
    
    func didTapCreateSubCategory(parentCategory: TransactionCategory?) {
        flowDelegate?.navigateToSubCategoryCreation(parentCategory: parentCategory)
    }
    
    func didTapEditSubCategory(_ subCategory: SubCategory) {
        flowDelegate?.navigateToSubCategoryEditing(subCategory)
    }
    
    func didTapDeleteSubCategory(_ subCategory: SubCategory) {
        showDeleteConfirmation(for: subCategory)
    }
    
    func didTapExpandCategory(_ category: TransactionCategory) {
        // This is handled by the view itself
    }
    
    private func showDeleteConfirmation(for subCategory: SubCategory) {
        let alert = UIAlertController(
            title: "categories.delete.confirmation.title".localized,
            message: String(format: "categories.delete.confirmation.message".localized, subCategory.name),
            preferredStyle: .alert
        )
        
        let cancelAction = UIAlertAction(
            title: "common.cancel".localized,
            style: .cancel
        )
        
        let deleteAction = UIAlertAction(
            title: "common.delete".localized,
            style: .destructive
        ) { [weak self] _ in
            self?.viewModel.deleteSubCategory(subCategory)
        }
        
        alert.addAction(cancelAction)
        alert.addAction(deleteAction)
        
        present(alert, animated: true)
    }
}
