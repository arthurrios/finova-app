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
            
            transactionTableView.topAnchor.constraint(equalTo: monthCard.bottomAnchor, constant: Metrics.spacing4),
            transactionTableView.leadingAnchor.constraint(equalTo: monthCard.leadingAnchor),
            transactionTableView.trailingAnchor.constraint(equalTo: monthCard.trailingAnchor),
            transactionTableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.spacing12)
        ])
    }
    
    func configure(with model: MonthBudgetCardType, transactions: [Transaction]) {
        monthCard.configure(data: model)
        self.transactions = transactions
        transactionTableView.reloadData()
        
        let rowHeight: CGFloat = 67
        let tableHeight = CGFloat(transactions.count) * rowHeight
        
        if let existingHeightConstraint = transactionTableView.constraints.first(where: { $0.firstAttribute == .height }) {
            existingHeightConstraint.constant = tableHeight
        } else {
            transactionTableView.heightAnchor.constraint(equalToConstant: tableHeight).isActive = true
        }
        transactionTableView.isHidden = transactions.isEmpty
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
