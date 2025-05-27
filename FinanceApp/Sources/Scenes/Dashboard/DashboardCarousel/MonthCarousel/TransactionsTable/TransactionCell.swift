//
//  TransactionCell.swift
//  FinanceApp
//
//  Created by Arthur Rios on 15/05/25.
//

import Foundation
import UIKit

final public class TransactionCell: UITableViewCell {
    static let reuseID = "TransactionCell"
    
    weak var delegate: TransactionCellDelegate?
    
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
    
    private let actionContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.mainMagenta
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let actionIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "trash")
        imageView.tintColor = Colors.gray100
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let actionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.buttonSM.font
        label.textColor = Colors.gray100
        label.text = "delete.action.label".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var actionContainerWidthConstraint: NSLayoutConstraint!
    private var panStartX: CGFloat = 0
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        contentView.backgroundColor = Colors.gray100
        
        contentView.addSubview(iconContainerView)
        iconContainerView.addSubview(iconView)
        contentView.addSubview(titleStackView)
        titleStackView.addArrangedSubview(titleLabel)
        titleStackView.addArrangedSubview(dateLabel)
        contentView.addSubview(valueStackView)
        valueStackView.addArrangedSubview(valueLabel)
        valueStackView.addArrangedSubview(transactionTypeIconView)
        contentView.addSubview(trashIconView)
        
        contentView.addSubview(actionContainerView)
        actionContainerView.addSubview(actionIconView)
        actionContainerView.addSubview(actionLabel)
        
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
            
            actionContainerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            actionContainerView.leadingAnchor.constraint(equalTo: contentView.trailingAnchor),
            actionContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            actionIconView.leadingAnchor.constraint(equalTo: actionContainerView.leadingAnchor, constant: Metrics.spacing6),
            actionIconView.centerYAnchor.constraint(equalTo: actionContainerView.centerYAnchor),
            actionIconView.heightAnchor.constraint(equalToConstant: Metrics.spacing5),
            actionIconView.widthAnchor.constraint(equalToConstant: Metrics.spacing5),
            
            actionLabel.leadingAnchor.constraint(equalTo: actionIconView.trailingAnchor, constant: Metrics.spacing3),
            actionLabel.centerYAnchor.constraint(equalTo: actionContainerView.centerYAnchor)
        ])
        
        
        actionContainerWidthConstraint = actionContainerView.widthAnchor.constraint(equalTo: contentView.widthAnchor)
        actionContainerWidthConstraint.isActive = true
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
    
    public override func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
        guard let pan = gr as? UIPanGestureRecognizer else {
            return true
        }
        let v = pan.velocity(in: contentView)
        return abs(v.x) > abs(v.y)
    }
}
