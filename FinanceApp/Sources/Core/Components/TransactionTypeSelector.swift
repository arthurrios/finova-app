//
//  TransactionTypeSelector.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/05/25.
//

import Foundation
import UIKit

public protocol TransactionTypeSelectorDelegate: AnyObject {
    func transactionTypeSelectorDidSelect(_ selector: TransactionTypeSelector)
}

public class TransactionTypeSelector: UIView {
    weak var delegate: TransactionTypeSelectorDelegate?
    
    enum Variant {
        case normal
        case selected
        case unselected
    }
    
    var transactionType: TransactionType = .income
    var variant: Variant = .normal {
        didSet {
            updateStyle()
        }
    }
    
    private let containerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = CornerRadius.large
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let label: UILabel = {
        let label = UILabel()
        label.font = Fonts.buttonSM.font
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let arrowUpImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "arrowUp")
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let arrowDownImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "arrowDown")
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private lazy var contentStackView = UIStackView(axis: .horizontal, spacing: Metrics.spacing1, alignment: .center, arrangedSubviews: [label, arrowUpImageView, arrowDownImageView])
    
    init(transactionType: TransactionType = .income) {
        super.init(frame: .zero)
        self.transactionType = transactionType
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(containerView)
        containerView.addSubview(contentStackView)
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGestureRecognizer)
        updateStyle()
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            contentStackView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            contentStackView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            arrowUpImageView.heightAnchor.constraint(equalToConstant: Metrics.arrowSize),
            arrowUpImageView.widthAnchor.constraint(equalToConstant: Metrics.arrowSize),
            
            arrowDownImageView.heightAnchor.constraint(equalToConstant: Metrics.arrowSize),
            arrowDownImageView.widthAnchor.constraint(equalToConstant: Metrics.arrowSize),
        ])
    }
    
    private func updateStyle() {
        switch (transactionType, variant) {
        case (.income, .normal):
            containerView.backgroundColor = Colors.lightGreen
            containerView.layer.borderWidth = 1
            containerView.layer.borderColor = Colors.mainGreen.cgColor
            
            label.text = "addTransactionModal.income".localized
            label.textColor = Colors.mainGreen

            arrowDownImageView.isHidden = true
            
            arrowUpImageView.tintColor = Colors.mainGreen
        case (.income, .selected):
            containerView.backgroundColor = Colors.mainGreen
            containerView.layer.borderWidth = 0
            
            label.text = "addTransactionModal.income".localized
            label.textColor = Colors.gray100
            
            arrowDownImageView.isHidden = true
            
            arrowUpImageView.tintColor = Colors.gray100
        case (.income, .unselected):
            containerView.backgroundColor = Colors.gray200
            containerView.layer.borderWidth = 0
            
            label.text = "addTransactionModal.income".localized
            label.textColor = Colors.mainGreen
            
            arrowDownImageView.isHidden = true
            
            arrowUpImageView.tintColor = Colors.mainGreen
        case (.expense, .normal):
            containerView.backgroundColor = Colors.lightRed
            containerView.layer.borderWidth = 1
            containerView.layer.borderColor = Colors.mainRed.cgColor
            
            label.text = "addTransactionModal.expense".localized
            label.textColor = Colors.mainRed
            
            arrowUpImageView.isHidden = true
            
            arrowDownImageView.tintColor = Colors.mainRed
        case (.expense, .selected):
            containerView.backgroundColor = Colors.mainRed
            containerView.layer.borderWidth = 0
            
            label.text = "addTransactionModal.expense".localized
            label.textColor = Colors.gray100
            
            arrowUpImageView.isHidden = true
            
            arrowDownImageView.tintColor = Colors.gray100
        case (.expense, .unselected):
            containerView.backgroundColor = Colors.gray200
            containerView.layer.borderWidth = 0
            
            label.text = "addTransactionModal.expense".localized
            label.textColor = Colors.mainRed
            
            arrowUpImageView.isHidden = true
            
            arrowDownImageView.tintColor = Colors.mainRed
        }
    }
    
    @objc
    private func handleTap() {
        delegate?.transactionTypeSelectorDidSelect(self)
    }
    
    func setSibilingSelected() {
        variant = .unselected
    }
    
    func setNoneSelected() {
        variant = .normal
    }
}
