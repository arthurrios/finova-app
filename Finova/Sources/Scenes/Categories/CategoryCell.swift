//
//  CategoryCell.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/25.
//

import UIKit

protocol CategoryCellDelegate: AnyObject {
    func didTapManageSubCategories(for category: TransactionCategory)
    func didTapAddSubCategory(for category: TransactionCategory)
    func didTapEditSubCategory(_ subCategory: SubCategory)
    func didTapDeleteSubCategory(_ subCategory: SubCategory)
    func didTapExpandCategory(_ category: TransactionCategory)
}

final class CategoryCell: UITableViewCell {
    
    // MARK: - Properties
    private var isExpanded = false
    private var subCategories: [SubCategory] = []
    private var transactionCategory: TransactionCategory?
    private var tableHeightConstraint: NSLayoutConstraint?
    private var tableContainerHeightConstraint: NSLayoutConstraint?
    private var mainContainerHeightConstraint: NSLayoutConstraint?
    private var mainContainerBottomConstraint: NSLayoutConstraint?
    private var addButtonToHeaderConstraint: NSLayoutConstraint?
    private var addButtonToTableConstraint: NSLayoutConstraint?
    weak var delegate: CategoryCellDelegate?
    
    // MARK: - Main Container (like TransactionCell)
    private let mainContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.borderWidth = 1
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.layer.masksToBounds = true // Ensure content stays inside
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // MARK: - Header Row (Category Info + Arrow)
    private let headerRowView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // MARK: - Category Icon Container (like TransactionCell)
    private let iconContainerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = CornerRadius.medium
        view.backgroundColor = Colors.gray200
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.borderWidth = 1
        view.layer.masksToBounds = true
        view.heightAnchor.constraint(equalToConstant: 44).isActive = true
        view.widthAnchor.constraint(equalToConstant: 44).isActive = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.mainMagenta
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    // MARK: - Title Label (like TransactionCell)
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Quantity Container (like TransactionCell)
    private let quantityContainerView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        stackView.layoutMargins = UIEdgeInsets(
            top: 0, left: Metrics.spacing2, bottom: 0, right: Metrics.spacing2)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.backgroundColor = Colors.gray300
        stackView.clipsToBounds = true
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let quantityLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleXS.font
        label.textColor = Colors.gray600
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Action Buttons (like TransactionCell)
    private let expandButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronDown"), for: .normal)
        button.tintColor = Colors.gray400
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Sub-Categories Table Container
    private var subCategoriesTableContainer: UIView = {
        let container = UIView()
        container.backgroundColor = UIColor.clear
        container.layer.cornerRadius = CornerRadius.small
        container.layer.masksToBounds = true // Ensure content doesn't overflow
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()
    
    // MARK: - Sub-Categories Table View (for swipe-to-delete)
    private let subCategoriesTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = UIColor.clear
        tableView.separatorStyle = .none // Remove default separators
        tableView.isScrollEnabled = true
        tableView.clipsToBounds = true // Ensure content doesn't overflow
        tableView.showsVerticalScrollIndicator = false // Disable vertical scroll indicator
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    // MARK: - Empty State View (like TransactionCell)
    private let emptyStateView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.cornerRadius = CornerRadius.medium
        view.layer.borderWidth = 1
        view.layer.borderColor = Colors.gray200.cgColor
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let emptyStateIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "iconBankSlip")
        imageView.tintColor = Colors.gray400
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let emptyStateDescriptionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.text = "No sub-categories yet"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Add Button (at bottom)
    private let addSubCategoryButton: Button = {
        let button = Button(variant: .outlined, label: "Add Sub-Category")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        setupConstraints()
        setupButtonActions()
        setupTableView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none
        
        // Add main container
        contentView.addSubview(mainContainerView)
        
        // Add header row
        mainContainerView.addSubview(headerRowView)
        
        // Add header components
        headerRowView.addSubview(iconContainerView)
        iconContainerView.addSubview(iconImageView)
        headerRowView.addSubview(titleLabel)
        headerRowView.addSubview(quantityContainerView)
        quantityContainerView.addArrangedSubview(quantityLabel)
        headerRowView.addSubview(expandButton)
        
        // Add sub-categories table container
        mainContainerView.addSubview(subCategoriesTableContainer)
        subCategoriesTableContainer.addSubview(subCategoriesTableView)
        subCategoriesTableContainer.addSubview(emptyStateView)
        
        // Add empty state components
        emptyStateView.addSubview(emptyStateIconImageView)
        emptyStateView.addSubview(emptyStateDescriptionLabel)
        
        // Add add button at bottom
        mainContainerView.addSubview(addSubCategoryButton)
    }
    
    private func setupConstraints() {
        // Main container constraints
        NSLayoutConstraint.activate([
            mainContainerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing2),
            mainContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing3),
            mainContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing3)
        ])
        
        // Dynamic bottom constraint for main container
        mainContainerBottomConstraint = mainContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.spacing2)
        mainContainerBottomConstraint?.isActive = true
        
        // Dynamic height constraint for main container
        mainContainerHeightConstraint = mainContainerView.heightAnchor.constraint(equalToConstant: 74) // 70 + 4 (spacing)
        mainContainerHeightConstraint?.isActive = true
        
        // Header row constraints
        NSLayoutConstraint.activate([
            headerRowView.topAnchor.constraint(equalTo: mainContainerView.topAnchor),
            headerRowView.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor),
            headerRowView.trailingAnchor.constraint(equalTo: mainContainerView.trailingAnchor),
            headerRowView.heightAnchor.constraint(equalToConstant: 70)
        ])
        
        // Icon container constraints
        NSLayoutConstraint.activate([
            iconContainerView.leadingAnchor.constraint(equalTo: headerRowView.leadingAnchor, constant: Metrics.spacing3),
            iconContainerView.centerYAnchor.constraint(equalTo: headerRowView.centerYAnchor),
            iconContainerView.widthAnchor.constraint(equalToConstant: 44),
            iconContainerView.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // Icon image constraints
        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        // Title label constraints
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: Metrics.spacing3),
            titleLabel.centerYAnchor.constraint(equalTo: headerRowView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: quantityContainerView.leadingAnchor, constant: -Metrics.spacing2)
        ])
        
        // Quantity container constraints
        NSLayoutConstraint.activate([
            quantityContainerView.trailingAnchor.constraint(equalTo: expandButton.leadingAnchor, constant: -Metrics.spacing2),
            quantityContainerView.centerYAnchor.constraint(equalTo: headerRowView.centerYAnchor)
        ])
        
        // Quantity label constraints - no need for separate constraints since it's an arranged subview
        
        // Expand button constraints
        NSLayoutConstraint.activate([
            expandButton.trailingAnchor.constraint(equalTo: headerRowView.trailingAnchor, constant: -Metrics.spacing4),
            expandButton.centerYAnchor.constraint(equalTo: headerRowView.centerYAnchor),
            expandButton.widthAnchor.constraint(equalToConstant: 20),
            expandButton.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        // Sub-categories table container constraints
        NSLayoutConstraint.activate([
            subCategoriesTableContainer.topAnchor.constraint(equalTo: headerRowView.bottomAnchor),
            subCategoriesTableContainer.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: Metrics.spacing3),
            subCategoriesTableContainer.trailingAnchor.constraint(equalTo: mainContainerView.trailingAnchor, constant: -Metrics.spacing3)
        ])
        
        // Dynamic height constraint for table container
        tableContainerHeightConstraint = subCategoriesTableContainer.heightAnchor.constraint(equalToConstant: 0)
        tableContainerHeightConstraint?.isActive = true
        
        // Empty state view constraints
        NSLayoutConstraint.activate([
            emptyStateView.topAnchor.constraint(equalTo: subCategoriesTableContainer.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: subCategoriesTableContainer.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: subCategoriesTableContainer.trailingAnchor),
            emptyStateView.heightAnchor.constraint(equalToConstant: Metrics.tableEmptyViewHeight)
        ])
        
        // Empty state components constraints
        NSLayoutConstraint.activate([
            emptyStateIconImageView.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor, constant: Metrics.spacing5),
            emptyStateIconImageView.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor),
            emptyStateIconImageView.heightAnchor.constraint(equalToConstant: Metrics.spacing8),
            emptyStateIconImageView.widthAnchor.constraint(equalToConstant: Metrics.spacing8),
            
            emptyStateDescriptionLabel.leadingAnchor.constraint(equalTo: emptyStateIconImageView.trailingAnchor, constant: Metrics.spacing5),
            emptyStateDescriptionLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor, constant: -Metrics.spacing4),
            emptyStateDescriptionLabel.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor)
        ])
        
        // Add button constraints
        NSLayoutConstraint.activate([
            addSubCategoryButton.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor, constant: Metrics.spacing3),
            addSubCategoryButton.trailingAnchor.constraint(equalTo: mainContainerView.trailingAnchor, constant: -Metrics.spacing3),
            addSubCategoryButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // Add button top constraint - will be updated based on expansion state
        addButtonToHeaderConstraint = addSubCategoryButton.topAnchor.constraint(equalTo: headerRowView.bottomAnchor, constant: Metrics.spacing3)
        addButtonToHeaderConstraint?.isActive = true
        
        // Initialize table constraint (will be activated when expanded)
        addButtonToTableConstraint = addSubCategoryButton.topAnchor.constraint(equalTo: subCategoriesTableContainer.bottomAnchor, constant: Metrics.spacing3)
        addButtonToTableConstraint?.isActive = false
        
        // Table view constraints
        NSLayoutConstraint.activate([
            subCategoriesTableView.topAnchor.constraint(equalTo: subCategoriesTableContainer.topAnchor),
            subCategoriesTableView.leadingAnchor.constraint(equalTo: subCategoriesTableContainer.leadingAnchor),
            subCategoriesTableView.trailingAnchor.constraint(equalTo: subCategoriesTableContainer.trailingAnchor),
            subCategoriesTableView.bottomAnchor.constraint(equalTo: subCategoriesTableContainer.bottomAnchor)
        ])
        
        // Dynamic height constraint for table view
        tableHeightConstraint = subCategoriesTableView.heightAnchor.constraint(equalToConstant: 0)
        tableHeightConstraint?.isActive = true
    }
    
    private func setupButtonActions() {
        expandButton.addTarget(self, action: #selector(didTapExpand), for: .touchUpInside)
        addSubCategoryButton.delegate = self
    }
    
    private func setupTableView() {
        subCategoriesTableView.delegate = self
        subCategoriesTableView.dataSource = self
        subCategoriesTableView.register(UITableViewCell.self, forCellReuseIdentifier: "SubCategoryCell")
        
        // Configure table view with fixed row height for consistent calculation
        subCategoriesTableView.rowHeight = 50
        subCategoriesTableView.reloadData()
    }
    
    @objc private func didTapExpand() {
        guard let category = transactionCategory else { return }
        delegate?.didTapExpandCategory(category)
    }
    
    func configure(with category: TransactionCategory, subCategories: [SubCategory] = [], isExpanded: Bool = false) {
        self.transactionCategory = category
        self.subCategories = subCategories
        self.isExpanded = isExpanded
        
        // Safety check to ensure subCategories is not nil
        if self.subCategories.isEmpty && !subCategories.isEmpty {
            self.subCategories = subCategories
        }
        
        // Configure header
        titleLabel.text = category.rawValue.localized
        iconImageView.image = UIImage(named: category.iconName)
        
        // Update quantity label
        quantityLabel.text = "\(self.subCategories.count)"
        quantityContainerView.isHidden = false
        
        // Update expand button state
        updateExpandButtonState()
        
        // Update sub-categories visibility
        updateSubCategoriesVisibility()
        
        // Update table view height if expanded
        if isExpanded {
            setupSubCategoriesTable()
        }
    }
    
    private func updateExpandButtonState() {
        let rotationAngle: CGFloat = isExpanded ? .pi : 0
        UIView.animate(withDuration: 0.3) {
            self.expandButton.transform = CGAffineTransform(rotationAngle: rotationAngle)
        }
        
        expandButton.isHidden = false
    }
    
    private func updateSubCategoriesVisibility() {
        if isExpanded {
            subCategoriesTableContainer.isHidden = false
            subCategoriesTableView.isHidden = false
            addSubCategoryButton.isHidden = false
            emptyStateView.isHidden = subCategories.isEmpty ? false : true
            
            // Position button relative to table container when expanded
            addButtonToHeaderConstraint?.isActive = false
            addButtonToTableConstraint?.isActive = true
            
            // Reactivate height constraint when expanded
            mainContainerHeightConstraint?.isActive = true
            
            // Restore bottom spacing when expanded
            mainContainerBottomConstraint?.constant = -Metrics.spacing2
            
            setupSubCategoriesTable()
        } else {
            subCategoriesTableContainer.isHidden = true
            subCategoriesTableView.isHidden = true
            addSubCategoryButton.isHidden = true
            emptyStateView.isHidden = true
            
            // Position button relative to header when collapsed
            addButtonToTableConstraint?.isActive = false
            addButtonToHeaderConstraint?.isActive = true
            
            // Reset table height constraint when collapsed
            tableHeightConstraint?.constant = 0
            tableContainerHeightConstraint?.constant = 0
            // Remove height constraint when collapsed to let cell size naturally
            mainContainerHeightConstraint?.isActive = false
            // Remove bottom spacing when collapsed
            mainContainerBottomConstraint?.constant = 0
        }
    }
    
    private func setupSubCategoriesTable() {
        if subCategories.isEmpty {
            emptyStateView.isHidden = false
            subCategoriesTableView.isHidden = true
            tableHeightConstraint?.constant = 0
            tableContainerHeightConstraint?.constant = Metrics.tableEmptyViewHeight
            // Calculate main container height for empty state
            let totalHeight = 70 + Metrics.tableEmptyViewHeight + 44 + Metrics.spacing3 * 4 // header + empty state + button + spacing + bottom padding
            mainContainerHeightConstraint?.constant = totalHeight
        } else {
            emptyStateView.isHidden = true
            subCategoriesTableView.isHidden = false
            
            // Calculate height based on number of sub-categories
            let rowHeight: CGFloat = 50.0
            let separatorHeight = CGFloat(max(0, subCategories.count - 1)) * 1.0
            let contentHeight = CGFloat(subCategories.count) * rowHeight + separatorHeight
            
            // Use dynamic height for small lists, fixed height for larger lists
            let finalTableHeight: CGFloat
            let containerPadding: CGFloat
            if subCategories.count <= 3 {
                // Dynamic height for small lists (1-3 items) with reduced spacing
                finalTableHeight = contentHeight
                containerPadding = Metrics.spacing3 * 2 // Reduced padding for small lists
                subCategoriesTableView.isScrollEnabled = false
                // Ensure table height matches content exactly
                subCategoriesTableView.rowHeight = 50 // Fixed row height for consistent calculation
            } else {
                // Fixed height for larger lists (4+ items)
                finalTableHeight = 180
                containerPadding = Metrics.spacing3 * 4 // Full padding for larger lists
                subCategoriesTableView.isScrollEnabled = true
                subCategoriesTableView.rowHeight = 50 // Fixed row height for consistent calculation
            }
            
            tableHeightConstraint?.constant = finalTableHeight
            tableContainerHeightConstraint?.constant = finalTableHeight
            
            // Calculate main container height for expanded state with proper bottom padding
            let totalHeight = 70 + finalTableHeight + 44 + containerPadding // header + table + button + dynamic padding
            mainContainerHeightConstraint?.constant = totalHeight
            
            subCategoriesTableView.reloadData()
            
            // Force immediate layout update
            subCategoriesTableView.layoutIfNeeded()
            mainContainerView.layoutIfNeeded()
        }
    }
    
    private func createSubCategoryCell(for subCategory: SubCategory, at indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        cell.backgroundColor = Colors.gray100
        cell.selectionStyle = .none
        cell.layer.masksToBounds = true
        cell.translatesAutoresizingMaskIntoConstraints = false
        
        // Safety check to prevent index out of range
        guard indexPath.row < subCategories.count else {
            // Return a basic cell if index is out of bounds
            return cell
        }
        
        // Configure border styling like transaction table
        let isFirstCell = indexPath.row == 0
        let isLastCell = indexPath.row == subCategories.count - 1
        
        if isFirstCell && isLastCell {
            // Single cell - rounded on all corners with all borders
            cell.layer.cornerRadius = CornerRadius.small
            cell.layer.borderWidth = 1
            cell.layer.borderColor = Colors.gray200.cgColor
        } else if isFirstCell {
            // First cell - rounded on top corners with all borders
            cell.layer.cornerRadius = CornerRadius.small
            cell.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            cell.layer.borderWidth = 1
            cell.layer.borderColor = Colors.gray200.cgColor
            // Add bottom border
            let bottomBorder = UIView()
            bottomBorder.backgroundColor = Colors.gray200
            bottomBorder.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(bottomBorder)
            NSLayoutConstraint.activate([
                bottomBorder.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                bottomBorder.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                bottomBorder.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                bottomBorder.heightAnchor.constraint(equalToConstant: 1)
            ])
        } else if isLastCell {
            // Last cell - rounded on bottom corners with all borders
            cell.layer.cornerRadius = CornerRadius.small
            cell.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            cell.layer.borderWidth = 1
            cell.layer.borderColor = Colors.gray200.cgColor
        } else {
            // Middle cell - no rounded corners, no side borders, just bottom border
            cell.layer.cornerRadius = 0
            cell.layer.borderWidth = 0
            // Add bottom border only
            let bottomBorder = UIView()
            bottomBorder.backgroundColor = Colors.gray200
            bottomBorder.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(bottomBorder)
            NSLayoutConstraint.activate([
                bottomBorder.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                bottomBorder.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                bottomBorder.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                bottomBorder.heightAnchor.constraint(equalToConstant: 1)
            ])
            
            // Add left and right borders for middle cells
            let leftBorder = UIView()
            leftBorder.backgroundColor = Colors.gray200
            leftBorder.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(leftBorder)
            
            let rightBorder = UIView()
            rightBorder.backgroundColor = Colors.gray200
            rightBorder.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(rightBorder)
            
            NSLayoutConstraint.activate([
                leftBorder.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                leftBorder.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                leftBorder.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                leftBorder.widthAnchor.constraint(equalToConstant: 1),
                
                rightBorder.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                rightBorder.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                rightBorder.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                rightBorder.widthAnchor.constraint(equalToConstant: 1)
            ])
        }
        
        // Sub-category title
        let titleLabel = UILabel()
        titleLabel.text = subCategory.name
        titleLabel.font = Fonts.textSM.font
        titleLabel.textColor = Colors.gray700
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Action buttons container
        let actionsContainer = UIStackView()
        actionsContainer.axis = .horizontal
        actionsContainer.spacing = Metrics.spacing2
        actionsContainer.alignment = .center
        actionsContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // Edit button
        let editButton = UIButton(type: .system)
        editButton.setImage(UIImage(named: "edit"), for: .normal)
        editButton.tintColor = Colors.mainMagenta
        editButton.translatesAutoresizingMaskIntoConstraints = false
        editButton.tag = subCategory.id.hashValue
        
        // Delete button
        let deleteButton = UIButton(type: .system)
        deleteButton.setImage(UIImage(named: "trash"), for: .normal)
        deleteButton.tintColor = Colors.mainMagenta
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.tag = subCategory.id.hashValue
        
        // Add buttons to actions container
        actionsContainer.addArrangedSubview(editButton)
        actionsContainer.addArrangedSubview(deleteButton)
        
        // Add subviews to cell
        cell.contentView.addSubview(titleLabel)
        cell.contentView.addSubview(actionsContainer)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: Metrics.spacing4),
            titleLabel.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionsContainer.leadingAnchor, constant: -Metrics.spacing3),
            
            actionsContainer.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -Metrics.spacing4),
            actionsContainer.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            
            editButton.widthAnchor.constraint(equalToConstant: 20),
            editButton.heightAnchor.constraint(equalToConstant: 20),
            
            deleteButton.widthAnchor.constraint(equalToConstant: 20),
            deleteButton.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        // Add action handlers
        editButton.addTarget(self, action: #selector(editSubCategoryTapped(_:)), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteSubCategoryTapped(_:)), for: .touchUpInside)
        
        return cell
    }
    
    @objc private func editSubCategoryTapped(_ sender: UIButton) {
        if let subCategory = subCategories.first(where: { $0.id.hashValue == sender.tag }) {
            delegate?.didTapEditSubCategory(subCategory)
        }
    }
    
    @objc private func deleteSubCategoryTapped(_ sender: UIButton) {
        if let subCategory = subCategories.first(where: { $0.id.hashValue == sender.tag }) {
            delegate?.didTapDeleteSubCategory(subCategory)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update corner radius for quantity container to make it circular
        quantityContainerView.layoutIfNeeded()
        let size = min(quantityContainerView.bounds.width, quantityContainerView.bounds.height)
        quantityContainerView.layer.cornerRadius = size / 2
        quantityContainerView.clipsToBounds = true
    }
}

// MARK: - ButtonDelegate
extension CategoryCell: ButtonDelegate {
    func buttonAction() {
        guard let category = transactionCategory else { return }
        delegate?.didTapAddSubCategory(for: category)
    }
}

extension CategoryCell: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return subCategories.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Safety check to prevent index out of range
        guard indexPath.row < subCategories.count else {
            // Return an empty cell if index is out of bounds
            let cell = UITableViewCell()
            cell.backgroundColor = Colors.gray100
            cell.selectionStyle = .none
            return cell
        }
        
        let subCategory = subCategories[indexPath.row]
        let cell = createSubCategoryCell(for: subCategory, at: indexPath)
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 50 // Fixed row height for consistent calculation
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 50 // Fixed row height for consistent calculation
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Safety check to prevent index out of range
            guard indexPath.row < subCategories.count else { return }
            
            let subCategoryToDelete = subCategories[indexPath.row]
            delegate?.didTapDeleteSubCategory(subCategoryToDelete)
        }
    }
}
