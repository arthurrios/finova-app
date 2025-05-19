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
        return stackView
    }()
    
    private let dateInput = Input(placeholder: "00/0000", icon: UIImage(named: "calendar"), iconPosition: .left)
    
    private let budgetValueInput = Input(placeholder: "0,00")
    
    private let addButton = Button(label: "budgets.button.add".localized)
    
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
        
        backButton.addTarget(self, action: #selector(didTapBackButton), for: .touchUpInside)
        
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
        ])
    }
    
    @objc
    private func didTapBackButton() {
        delegate?.didTapBackButton()
    }
}
