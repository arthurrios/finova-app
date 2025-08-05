//
//  CategoriesView.swift
//  Finova
//
//  Created by Arthur Rios on 31/07/25.
//

import Foundation
import UIKit

protocol CategoriesViewDelegate: AnyObject {
    func didTapSubCategoryManagement(for category: TransactionCategory)
    func didTapCreateSubCategory(parentCategory: TransactionCategory?)
    func didTapEditSubCategory(_ subCategory: SubCategory)
    func didTapDeleteSubCategory(_ subCategory: SubCategory)
    func didTapExpandCategory(_ category: TransactionCategory)
}

final class CategoriesView: UIView {
    
    weak var delegate: CategoriesViewDelegate?
    
    // MARK: - State Management
    private var expandedCategories: Set<TransactionCategory> = []
    private var subCategoriesData: [TransactionCategory: [SubCategory]] = [:]
    
    private let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight).isActive = true
        return view
    }()
    
    private let headerItemsView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing4, leading: Metrics.spacing5, bottom: Metrics.spacing5,
            trailing: Metrics.spacing5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.text = "categories.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let headerSubtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.text = "categories.header.subtitle_new".localized
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var headerTextStackView = UIStackView(
        axis: .vertical, spacing: Metrics.spacing1,
        arrangedSubviews: [headerTitleLabel, headerSubtitleLabel])
    
    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Colors.gray200
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        backgroundColor = Colors.gray200
        
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(headerTextStackView)
        addSubview(tableView)
        
        setupTableView()
        setupConstraints()
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(CategoryCell.self, forCellReuseIdentifier: "CategoryCell")
        
        // Configure table view for automatic sizing
        tableView.estimatedRowHeight = 100
        tableView.rowHeight = UITableView.automaticDimension
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            headerItemsView.topAnchor.constraint(equalTo: headerContainerView.topAnchor),
            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            
            headerTextStackView.leadingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
            headerTextStackView.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
            headerTextStackView.bottomAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.bottomAnchor),
            
            tableView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    // MARK: - Public Methods
    func reloadData() {
        tableView.reloadData()
    }
    
    func updateSubCategories(_ subCategories: [SubCategory], for category: TransactionCategory) {
        subCategoriesData[category] = subCategories
        tableView.reloadData()
    }
    
    func setExpanded(_ isExpanded: Bool, for category: TransactionCategory) {
        if isExpanded {
            expandedCategories.insert(category)
        } else {
            expandedCategories.remove(category)
        }
        
        // Reload the specific cell with animation
        if let index = TransactionCategory.allCases.firstIndex(of: category) {
            let indexPath = IndexPath(row: index, section: 0)
            tableView.reloadRows(at: [indexPath], with: .automatic)
        }
    }
}

// MARK: - UITableViewDataSource
extension CategoriesView: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return TransactionCategory.allCases.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CategoryCell", for: indexPath) as! CategoryCell
        let category = TransactionCategory.allCases[indexPath.row]
        
        let subCategories = subCategoriesData[category] ?? []
        let isExpanded = expandedCategories.contains(category)
        
        cell.configure(with: category, subCategories: subCategories, isExpanded: isExpanded)
        cell.delegate = self
        return cell
    }
}

// MARK: UITableViewDelegate
extension CategoriesView: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let category = TransactionCategory.allCases[indexPath.row]
        let isExpanded = expandedCategories.contains(category)
        
        guard isExpanded else {
            return 78 // Just the header height, no extra space
        }
        
        let subCategories = subCategoriesData[category] ?? []
        let baseHeight: CGFloat = 70 // Header row height
        let containerPadding: CGFloat = Metrics.spacing3 * 3.5 // Proper padding including bottom padding
        let addButtonHeight: CGFloat = 44
        let addButtonPadding: CGFloat = 0 // No spacing between table and button
        
        // Calculate sub-categories height
        let subCategoriesHeight: CGFloat
        if subCategories.isEmpty {
            // Empty state height (same as transaction table)
            subCategoriesHeight = Metrics.tableEmptyViewHeight
        } else {
            // Use dynamic height for small lists, fixed height for larger lists
            if subCategories.count <= 3 {
                // Dynamic height for small lists (1-3 items)
                let rowHeight: CGFloat = 50.0
                let separatorHeight = CGFloat(max(0, subCategories.count - 1)) * 1.0
                subCategoriesHeight = CGFloat(subCategories.count) * rowHeight + separatorHeight
            } else {
                // Fixed height for larger lists (4+ items)
                subCategoriesHeight = 180
            }
        }
        
        // Calculate total height with proper bottom padding
        let totalHeight = baseHeight + subCategoriesHeight + containerPadding + addButtonHeight + addButtonPadding
        
        return totalHeight
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        let category = TransactionCategory.allCases[indexPath.row]
        let isExpanded = expandedCategories.contains(category)
        
        guard isExpanded else {
            return 70 // Just the header height, no extra space
        }
        
        let subCategories = subCategoriesData[category] ?? []
        let baseHeight: CGFloat = 70
        
        // Calculate sub-categories height
        let subCategoryItemHeight: CGFloat = 44
        let spacingBetweenItems: CGFloat = Metrics.spacing2
        
        let subCategoriesHeight: CGFloat
        if subCategories.isEmpty {
            subCategoriesHeight = subCategoryItemHeight
        } else {
            let totalItemsHeight = CGFloat(subCategories.count) * subCategoryItemHeight
            let totalSpacingHeight = CGFloat(subCategories.count - 1) * spacingBetweenItems
            subCategoriesHeight = totalItemsHeight + totalSpacingHeight
        }
        
        // Calculate padding
        let containerPadding: CGFloat = Metrics.spacing3 * 2
        let topBottomPadding: CGFloat = Metrics.spacing2 * 2
        
        // Calculate total height
        let totalHeight = baseHeight + subCategoriesHeight + containerPadding + topBottomPadding
        
        return totalHeight
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let footerView = UIView()
        footerView.backgroundColor = .clear
        return footerView
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return Metrics.spacing17
    }
}

// MARK: - CategoryCellDelegate
extension CategoriesView: CategoryCellDelegate {
    func didTapDeleteCategory(_ category: TransactionCategory) {
        //
    }
    
    func didTapManageSubCategories(for category: TransactionCategory) {
        delegate?.didTapSubCategoryManagement(for: category)
    }
    
    func didTapAddSubCategory(for category: TransactionCategory) {
        delegate?.didTapCreateSubCategory(parentCategory: category)
    }
    
    func didTapEditSubCategory(_ subCategory: SubCategory) {
        delegate?.didTapEditSubCategory(subCategory)
    }
    
    func didTapDeleteSubCategory(_ subCategory: SubCategory) {
        delegate?.didTapDeleteSubCategory(subCategory)
    }
    
    func didTapExpandCategory(_ category: TransactionCategory) {
        let isCurrentlyExpanded = expandedCategories.contains(category)
        setExpanded(!isCurrentlyExpanded, for: category)
    }
}
