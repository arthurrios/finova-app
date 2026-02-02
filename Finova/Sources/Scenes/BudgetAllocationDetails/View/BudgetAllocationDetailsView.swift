//
//  BudgetAllocationDetailsView.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import UIKit

final class BudgetAllocationDetailsView: UIView {
    
    private lazy var placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "allocation.details.title".localized
        label.font = Fonts.titleMD.font
        label.textColor = Colors.gray100
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private(set) lazy var backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = Colors.gray100
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = Colors.gray700
        
        addSubview(backButton)
        addSubview(placeholderLabel)
        
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: Metrics.spacing4),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            backButton.widthAnchor.constraint(equalToConstant: 40),
            backButton.heightAnchor.constraint(equalToConstant: 40),
            
            placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    func configure(with allocation: BudgetAllocation) {
        placeholderLabel.text = String(
            format: "allocation.details.title.format".localized,
            allocation.category.displayName
        )
    }
}
