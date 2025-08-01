//
//  CategoriesView.swift
//  Finova
//
//  Created by Arthur Rios on 31/07/25.
//

import Foundation
import UIKit

protocol CategoriesViewDelegate: AnyObject {
    func didTapSubCategoryManagement()
    func didTapCreateSubCategory(parentCategory: TransactionCategory?)
}

final class CategoriesView: UIView {
    
    
    weak var delegate: CategoriesViewDelegate?
    
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private lazy var contentStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [titleLabel, placeholderLabel])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.title2XS.font
        label.textColor = Colors.gray700
        label.textAlignment = .center
        label.text = "Categories"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.textAlignment = .center
        label.text = "Categories feature coming soon!"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        
        addSubview(scrollView)
        scrollView.addSubview(contentStackView)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Metrics.spacing5),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Metrics.spacing5)),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing5)),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Metrics.spacing5)),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -Metrics.spacing10)
        ])
    }
}
