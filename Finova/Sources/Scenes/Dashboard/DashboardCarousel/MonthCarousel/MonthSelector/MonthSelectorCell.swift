//
//  MonthSelectorCell.swift
//  FinanceApp
//
//  Created by Arthur Rios on 12/05/25.
//

import Foundation
import UIKit

class MonthCell: UICollectionViewCell {
    static let reuseID = "MonthCell"
    private let titleLabel = UILabel()
    
    private let barView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.mainMagenta
        view.heightAnchor.constraint(equalToConstant: 2).isActive = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        contentView.addSubview(barView)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            barView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Metrics.spacing2),
            barView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            barView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            barView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        updateStyles()
    }
    required init?(coder: NSCoder) { fatalError() }
    
    override var isSelected: Bool {
        didSet {
            updateStyles()
        }
    }
    
    private func updateStyles() {
        barView.isHidden = !isSelected
        
        if isSelected {
            titleLabel.fontStyle = Fonts.titleXS
            titleLabel.textColor = Colors.gray700
        } else {
            titleLabel.fontStyle = Fonts.title2XS
            titleLabel.textColor = Colors.gray400
        }
        
        titleLabel.applyStyle()
    }
    
    func configure(title: String) {
        titleLabel.text = title
        titleLabel.applyStyle()
    }
}
