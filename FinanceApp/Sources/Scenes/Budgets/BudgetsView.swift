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
    
    let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight).isActive = true
        return view
    }()
    
    let headerItemsView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: Metrics.spacing3, leading: Metrics.spacing5, bottom: Metrics.spacing6, trailing: Metrics.spacing5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
        
    lazy var headerTextStackView = UIStackView(axis: .vertical, spacing: Metrics.spacing1, arrangedSubviews: [headerTitleLabel, headerSubtitleLabel])
    
    private let backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronLeft"), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.heightAnchor.constraint(equalToConstant: Metrics.backButtonSize).isActive = true
        button.widthAnchor.constraint(equalToConstant: Metrics.backButtonSize).isActive = true
        button.tintColor = Colors.gray500
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
        
    let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.text = "budgets.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let headerSubtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.text = "budgets.header.subtitle".localized
        label.textAlignment = .left
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
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor, constant: Metrics.spacing5),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            
            backButton.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
            backButton.leadingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
        ])
    }
}
