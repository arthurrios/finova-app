//
//  MonthCarouselCell.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation
import UIKit

class MonthCarouselCell: UICollectionViewCell {
    static let reuseID = "MonthCarouselCell"
    
    let monthCard = MonthBudgetCard()
    private var transactions: [Transaction] = []
    private var tableHeightConstraint: NSLayoutConstraint?
    
    private let tableHeaderView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.heightAnchor.constraint(equalToConstant: Metrics.spacing11).isActive = true
        stackView.layer.cornerRadius = CornerRadius.extraLarge
        stackView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        stackView.backgroundColor = Colors.gray100
        stackView.layoutMargins = UIEdgeInsets(top: 0, left: Metrics.spacing5, bottom: 0, right: Metrics.spacing4)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.distribution = .equalSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let tableHeaderTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.title2XS
        label.textColor = Colors.gray500
        label.text = "transactions.header.title".localized
        label.applyStyle()
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let transactionsNumberContainerView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        stackView.layoutMargins = UIEdgeInsets(top: 0, left: Metrics.spacing2, bottom: 0, right: Metrics.spacing2)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.backgroundColor = Colors.gray300
        stackView.clipsToBounds = true
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let transactionNumberLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleXS.font
        label.textColor = Colors.gray600
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        label.text = "transactions.emptyState.description".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    lazy var transactionTableView: UITableView = {
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
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        monthCard.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(monthCard)
        contentView.addSubview(transactionTableView)
        
        contentView.addSubview(tableHeaderView)
        tableHeaderView.addArrangedSubview(tableHeaderTitleLabel)
        tableHeaderView.addArrangedSubview(transactionsNumberContainerView)
        transactionsNumberContainerView.addArrangedSubview(transactionNumberLabel)
        contentView.addSubview(emptyStateView)
        emptyStateView.addSubview(emptyStateIconImageView)
        emptyStateView.addSubview(emptyStateDescriptionLabel)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            monthCard.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing4),
            monthCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
            monthCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),
            
            tableHeaderView.topAnchor.constraint(equalTo: monthCard.bottomAnchor, constant: Metrics.spacing4),
            tableHeaderView.leadingAnchor.constraint(equalTo: monthCard.leadingAnchor),
            tableHeaderView.trailingAnchor.constraint(equalTo: monthCard.trailingAnchor),
            
            transactionTableView.topAnchor.constraint(equalTo: tableHeaderView.bottomAnchor),
            transactionTableView.leadingAnchor.constraint(equalTo: monthCard.leadingAnchor),
            transactionTableView.trailingAnchor.constraint(equalTo: monthCard.trailingAnchor),

            emptyStateView.topAnchor.constraint(equalTo: tableHeaderView.bottomAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: monthCard.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: monthCard.trailingAnchor),
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
    
    func configure(with model: MonthBudgetCardType, transactions: [Transaction]) {
        monthCard.configure(data: model)
        self.transactions = transactions
        transactionTableView.reloadData()
        self.transactionNumberLabel.text = "\(transactions.count)"
        if transactions.isEmpty {
            transactionTableView.isHidden = true
            emptyStateView.isHidden = false
        } else {
            transactionTableView.isHidden = false
            emptyStateView.isHidden = true
        }
        
        updateTableHeight(with: transactions.count)
    }
    
    func updateTableHeight(with rowCount: Int) {
        let rowHeight: CGFloat = 67
        let separatorHeight = CGFloat(max(0, rowCount - 1)) * 1.0
        let contentHeight = CGFloat(rowCount) * rowHeight + separatorHeight

        let maxTableHeight: CGFloat = Metrics.transactionsTableHeight
        let finalHeight = min(contentHeight, maxTableHeight)

        if let c = tableHeightConstraint {
            c.constant = finalHeight
        } else {
            tableHeightConstraint = transactionTableView
                .heightAnchor
                .constraint(equalToConstant: finalHeight)
            tableHeightConstraint?.isActive = true
        }

        transactionTableView.isScrollEnabled = (contentHeight > maxTableHeight)
        layoutIfNeeded()
    }

    private func addBordersExceptBottom(to view: UIView, color: UIColor, width: CGFloat = 1.0) {
        view.layer.sublayers?.removeAll(where: { $0.name == "customBorder" })
        
        let bounds = view.bounds
        let cornerRadius = view.layer.cornerRadius
        
        let path = UIBezierPath()
        
        path.move(to: CGPoint(x: 0, y: bounds.height))
        
        path.addLine(to: CGPoint(x: 0, y: cornerRadius))
        
        path.addArc(withCenter: CGPoint(x: cornerRadius, y: cornerRadius),
                    radius: cornerRadius,
                    startAngle: .pi,
                    endAngle: 3 * .pi / 2,
                    clockwise: true)
        
        path.addLine(to: CGPoint(x: bounds.width - cornerRadius, y: 0))
        
        path.addArc(withCenter: CGPoint(x: bounds.width - cornerRadius, y: cornerRadius),
                    radius: cornerRadius,
                    startAngle: 3 * .pi / 2,
                    endAngle: 0,
                    clockwise: true)
        
        path.addLine(to: CGPoint(x: bounds.width, y: bounds.height))
        
        let borderLayer = CAShapeLayer()
        borderLayer.name = "customBorder"
        borderLayer.path = path.cgPath
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = color.cgColor
        borderLayer.lineWidth = width
        borderLayer.frame = bounds
        
        view.layer.addSublayer(borderLayer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        transactionsNumberContainerView.layoutIfNeeded()
        
        let size = min(transactionsNumberContainerView.bounds.width, transactionsNumberContainerView.bounds.height)
        transactionsNumberContainerView.layer.cornerRadius = size / 2
        
        transactionsNumberContainerView.clipsToBounds = true
        
        tableHeaderView.layer.sublayers?.removeAll(where: { $0 is CAShapeLayer })
        tableHeaderView.layoutIfNeeded()
        addBordersExceptBottom(to: tableHeaderView, color: Colors.gray300)
    }
}
