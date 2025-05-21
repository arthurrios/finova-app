//
//  BudgetsView.swift
//  FinanceApp
//
//  Created by Arthur Rios on 16/05/25.
//

import Foundation
import UIKit

final class BudgetsView: UIView {
    public weak var delegate: BudgetsViewDelegate?
    
    private var tableHeightConstraint: NSLayoutConstraint?
    private var budgets: [BudgetModel] = []
    
    private let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight).isActive = true
        return view
    }()
    
    private let headerItemsView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: Metrics.spacing4, leading: Metrics.spacing5, bottom: Metrics.spacing5, trailing: Metrics.spacing5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
        
    lazy var headerTextStackView = UIStackView(axis: .vertical, spacing: Metrics.spacing1, arrangedSubviews: [headerTitleLabel, headerSubtitleLabel])
    
    private let backButton: UIButton = {
        let button = UIButton(type: .system)
        
        if let originalImage = UIImage(named: "chevronLeft") {
            let size = CGSize(width: Metrics.backButtonSize, height: Metrics.backButtonSize)
            UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
            originalImage.draw(in: CGRect(origin: .zero, size: size))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            button.setImage(resizedImage, for: .normal)
        } else {
            button.setImage(UIImage(named: "chevronLeft"), for: .normal)
        }
        
        button.imageView?.contentMode = .scaleAspectFit
        button.tintColor = Colors.gray500
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
        
    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.text = "budgets.header.title".localized
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
        label.text = "budgets.header.subtitle".localized
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let newBudgetCardHeaderView = CardHeader(headerTitle: "budgets.new.header.title".localized)
    
    private lazy var cardContentView: UIStackView = {
        let stackView = UIStackView(axis: .vertical, spacing: Metrics.spacing4, arrangedSubviews: [inputStackView, addButton])
        stackView.layoutMargins = UIEdgeInsets(top: Metrics.spacing5, left: Metrics.spacing5, bottom: Metrics.spacing5, right: Metrics.spacing5)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.distribution = .fill
        stackView.backgroundColor = Colors.gray100
        stackView.layer.borderWidth = 1
        stackView.layer.borderColor = Colors.gray300.cgColor
        stackView.layer.cornerRadius = CornerRadius.extraLarge
        stackView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        stackView.clipsToBounds = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private lazy var inputStackView: UIStackView = {
        let stackView = UIStackView(axis: .horizontal, spacing: Metrics.spacing3, arrangedSubviews: [dateInput, budgetValueInput])
        stackView.distribution = .fillEqually
        stackView.heightAnchor.constraint(equalToConstant: Metrics.inputHeight).isActive = true
        return stackView
    }()
    
    private let dateInput = Input(type: .date(style: .monthYear), placeholder: "00/0000", icon: UIImage(named: "calendar"))
    
    private let budgetValueInput = Input(type: .currency, placeholder: "0,00")
    
    private let addButton = Button(label: "budgets.button.add.title".localized)
    
    private let budgetsTableHeaderView = CardHeader(headerTitle: "budgets.table.header.title".localized)
    
    let budgetsTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Colors.gray100
        tableView.layer.borderWidth = 1
        tableView.layer.borderColor = Colors.gray300.cgColor
        tableView.layer.cornerRadius = CornerRadius.extraLarge
        tableView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets.zero
        tableView.clipsToBounds = true
        tableView.separatorColor = Colors.gray300
        tableView.isScrollEnabled = true
        tableView.showsVerticalScrollIndicator = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    private let emptyStateView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.borderWidth = 1
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
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
        label.text = "budgets.emptyState.description".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        backgroundColor = Colors.gray200
        
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButton)
        headerItemsView.addSubview(headerTextStackView)
        
        addSubview(newBudgetCardHeaderView)
        addSubview(cardContentView)
        cardContentView.addSubview(inputStackView)
        cardContentView.addSubview(addButton)
        
        addSubview(budgetsTableHeaderView)
        addSubview(budgetsTableView)
        
        addSubview(emptyStateView)
        emptyStateView.addSubview(emptyStateIconImageView)
        emptyStateView.addSubview(emptyStateDescriptionLabel)
        
        backButton.addTarget(self, action: #selector(didTapBackButton), for: .touchUpInside)
        addButton.addTarget(self, action: #selector(didTapAddBudgetButton), for: .touchUpInside)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            
            backButton.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
            backButton.leadingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
            
            headerTextStackView.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: Metrics.spacing4),
            headerTextStackView.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            
            newBudgetCardHeaderView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing4),
            newBudgetCardHeaderView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            newBudgetCardHeaderView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            
            cardContentView.topAnchor.constraint(equalTo: newBudgetCardHeaderView.bottomAnchor),
            cardContentView.leadingAnchor.constraint(equalTo: newBudgetCardHeaderView.leadingAnchor),
            cardContentView.trailingAnchor.constraint(equalTo: newBudgetCardHeaderView.trailingAnchor),
        
            budgetsTableHeaderView.topAnchor.constraint(equalTo: cardContentView.bottomAnchor, constant: Metrics.spacing4),
            budgetsTableHeaderView.leadingAnchor.constraint(equalTo: cardContentView.leadingAnchor),
            budgetsTableHeaderView.trailingAnchor.constraint(equalTo: cardContentView.trailingAnchor),
            
            budgetsTableView.topAnchor.constraint(equalTo: budgetsTableHeaderView.bottomAnchor),
            budgetsTableView.leadingAnchor.constraint(equalTo: cardContentView.leadingAnchor),
            budgetsTableView.trailingAnchor.constraint(equalTo: cardContentView.trailingAnchor),
            budgetsTableView.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -Metrics.spacing8),
            
            emptyStateView.topAnchor.constraint(equalTo: budgetsTableHeaderView.bottomAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: cardContentView.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: cardContentView.trailingAnchor),
            emptyStateView.heightAnchor.constraint(equalToConstant: Metrics.tableEmptyViewHeight),
            
            emptyStateIconImageView.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor, constant: Metrics.spacing5),
            emptyStateIconImageView.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor),
            emptyStateIconImageView.heightAnchor.constraint(equalToConstant: Metrics.spacing8),
            emptyStateIconImageView.widthAnchor.constraint(equalToConstant: Metrics.spacing8),
            
            emptyStateDescriptionLabel.leadingAnchor.constraint(equalTo: emptyStateIconImageView.trailingAnchor, constant: Metrics.spacing5),
            emptyStateDescriptionLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor, constant: -Metrics.spacing4),
            emptyStateDescriptionLabel.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor),
        ])
    }
    
    func updateUI(with budgets: [BudgetModel], selectedDate: Date?) {
        self.budgets = budgets
        
        if let selectedDate = selectedDate {
            self.dateInput.text = DateFormatter.monthYearFormatter.string(from: selectedDate)
        }
        
        if budgets.isEmpty {
            budgetsTableView.isHidden = true
            emptyStateView.isHidden = false
        } else {
            budgetsTableView.isHidden = false
            emptyStateView.isHidden = true
            budgetsTableView.reloadData()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
    }
    
    @objc
    private func didTapBackButton() {
        delegate?.didTapBackButton()
    }
    
    @objc
    private func didTapAddBudgetButton() {
        let inputs = [dateInput, budgetValueInput]

        let invalids = inputs.filter { !$0.textField.hasText }

        invalids.forEach { $0.setError(true) }

        guard invalids.isEmpty else { return }
        
        let date = dateInput.textField.text ?? ""
        let budget = budgetValueInput.centsValue
        delegate?.didTapAddBudgetButton(monthYearDate: date, budgetAmount: budget)
    }
}
