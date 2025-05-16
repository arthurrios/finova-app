//
//  TransactionCell.swift
//  FinanceApp
//
//  Created by Arthur Rios on 15/05/25.
//

import Foundation
import UIKit

final class TransactionCell: UITableViewCell {
    static let reuseID = "TransactionCell"
    
    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = Colors.mainMagenta
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let iconContainerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = CornerRadius.medium
        view.backgroundColor = Colors.gray200
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.borderWidth = 1
        view.layer.masksToBounds = true
        view.heightAnchor.constraint(equalToConstant: Metrics.spacing8).isActive = true
        view.widthAnchor.constraint(equalToConstant: Metrics.spacing8).isActive = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let titleStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = Metrics.spacing1
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.numberOfLines = 0
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let valueStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Metrics.spacing1
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let valueLabel: UILabel = {
        let label = UILabel()
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let transactionTypeIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.heightAnchor.constraint(equalToConstant: 14).isActive = true
        imageView.widthAnchor.constraint(equalToConstant: 14).isActive = true
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let trashIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "trash")
        imageView.heightAnchor.constraint(equalToConstant: Metrics.spacing4).isActive = true
        imageView.tintColor = Colors.mainMagenta
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        contentView.addSubview(iconContainerView)
        iconContainerView.addSubview(iconView)
        contentView.addSubview(titleStackView)
        titleStackView.addArrangedSubview(titleLabel)
        titleStackView.addArrangedSubview(dateLabel)
        contentView.addSubview(valueStackView)
        valueStackView.addArrangedSubview(valueLabel)
        valueStackView.addArrangedSubview(transactionTypeIconView)
        contentView.addSubview(trashIconView)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            iconContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing5),
            iconContainerView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            iconView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.spacing5),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.spacing5),
            
            titleStackView.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: Metrics.spacing4),
            titleStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            trashIconView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing5),
            trashIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            valueStackView.trailingAnchor.constraint(equalTo: trashIconView.leadingAnchor, constant: -Metrics.spacing3),
            valueStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }
    
    func configure(category: TransactionCategory, title: String, date: Date, value: Int, transactionType: TransactionType) {
        self.titleLabel.text = title
        self.dateLabel.text = DateFormatter.fullDateFormatter.string(from: date)
        
        let symbolFont = Fonts.textXS.font
        self.valueLabel.attributedText = value.currencyAttributedString(symbolFont: symbolFont, font: Fonts.titleMD)
        self.valueLabel.accessibilityLabel = value.currencyString
        
        self.iconView.image = UIImage(named: category.iconName)
        
        if transactionType == .income {
            self.transactionTypeIconView.image = UIImage(named: "arrowUp")
            self.transactionTypeIconView.tintColor = Colors.mainGreen
        } else {
            self.transactionTypeIconView.image = UIImage(named: "arrowDown")
            self.transactionTypeIconView.tintColor = Colors.mainRed
        }
    }
}
