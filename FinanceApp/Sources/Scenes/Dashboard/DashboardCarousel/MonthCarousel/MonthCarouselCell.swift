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
    
    private let monthCard = MonthBudgetCard()
    private var transactions: [Transaction] = []
    
    let tableHeaderView: UIStackView = {
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
    
    let tableHeaderTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.title2XS
        label.textColor = Colors.gray500
        label.text = "transactions.header.title".localized
        label.applyStyle()
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let transactionsNumberContainerView: UIStackView = {
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
    
    let transactionNumberLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleXS.font
        label.textColor = Colors.gray600
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let transactionTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Colors.gray100
        tableView.layer.borderWidth = 1
        tableView.layer.borderColor = Colors.gray300.cgColor
        tableView.layer.cornerRadius = CornerRadius.extraLarge
        tableView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        tableView.separatorStyle = .singleLine
        tableView.clipsToBounds = true
        tableView.separatorColor = Colors.gray300
        tableView.isScrollEnabled = false
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
        
        transactionTableView.frame = contentView.bounds
        transactionTableView.register(TransactionCell.self, forCellReuseIdentifier: TransactionCell.reuseID)
        transactionTableView.dataSource = self
        transactionTableView.delegate   = self
        
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
        ])
    }
    
    func configure(with model: MonthBudgetCardType, transactions: [Transaction]) {
        monthCard.configure(data: model)
        self.transactions = transactions
        transactionTableView.reloadData()
        
        self.transactionNumberLabel.text = "\(transactions.count)"
        
        let rowHeight: CGFloat = 67
        let tableHeight = CGFloat(transactions.count) * rowHeight
        
        if let existingHeightConstraint = transactionTableView.constraints.first(where: { $0.firstAttribute == .height }) {
            existingHeightConstraint.constant = tableHeight
        } else {
            transactionTableView.heightAnchor.constraint(equalToConstant: tableHeight).isActive = true
        }
        transactionTableView.isHidden = transactions.isEmpty
    }
    
    private func addBordersExceptBottom(to view: UIView, color: UIColor, width: CGFloat = 1.0) {
        view.layer.sublayers?.removeAll(where: { $0.name == "customBorder" })
        
        let path = UIBezierPath()
        let cornerRadius = view.layer.cornerRadius
        
        path.move(to: CGPoint(x: 0, y: view.bounds.height))
        
        path.addLine(to: CGPoint(x: 0, y: cornerRadius))
        path.addArc(withCenter: CGPoint(x: cornerRadius, y: cornerRadius),
                    radius: cornerRadius,
                    startAngle: .pi,
                    endAngle: 3 * .pi / 2,
                    clockwise: true)
        
        path.addLine(to: CGPoint(x: view.bounds.width - cornerRadius, y: 0))
        
        path.addArc(withCenter: CGPoint(x: view.bounds.width - cornerRadius, y: cornerRadius),
                    radius: cornerRadius,
                    startAngle: 3 * .pi / 2,
                    endAngle: 0,
                    clockwise: true)
        
        path.addLine(to: CGPoint(x: view.bounds.width, y: view.bounds.height))
        
        let borderLayer = CAShapeLayer()
        borderLayer.name = "customBorder"
        borderLayer.path = path.cgPath
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = color.cgColor
        borderLayer.lineWidth = width
        borderLayer.frame = view.bounds
        
        view.layer.addSublayer(borderLayer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let size = min(transactionsNumberContainerView.bounds.width, transactionsNumberContainerView.bounds.height)
        transactionsNumberContainerView.layer.cornerRadius = size / 2
        
        tableHeaderView.layer.sublayers?.removeAll(where: { $0 is CAShapeLayer })
        addBordersExceptBottom(to: tableHeaderView, color: Colors.gray300)
    }
}

extension MonthCarouselCell: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        return transactions.count
    }
    func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: TransactionCell.reuseID, for: ip) as! TransactionCell
        let tx = transactions[ip.row]
        cell.configure(
            category: tx.category,
            title:    tx.title,
            date:     tx.date,
            value:    tx.amount,
            transactionType: tx.type
        )
        return cell
    }
    func tableView(_ tv: UITableView, heightForRowAt ip: IndexPath) -> CGFloat { 67 }
}
