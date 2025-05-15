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
    private let transactionTable = UITableView()
    private var transactions: [Transaction] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        monthCard.translatesAutoresizingMaskIntoConstraints = false
        transactionTable.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(monthCard)
//        contentView.addSubview(transactionTable)
        
        transactionTable.dataSource = self
        transactionTable.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            monthCard.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing4),
            monthCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
            monthCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),
//
//            transactionTable.topAnchor.constraint(equalTo: monthCard.bottomAnchor, constant: Metrics.spacing4),
//            transactionTable.leadingAnchor.constraint(equalTo: monthCard.leadingAnchor),
//            transactionTable.trailingAnchor.constraint(equalTo: monthCard.trailingAnchor),
//            transactionTable.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.spacing12)
        ])
    }
    
    func configure(with model: MonthBudgetCardType, transactions: [Transaction]) {
        monthCard.configure(data: model)
        self.transactions = transactions
        transactionTable.reloadData()
//        transactionTable.backgroundView?.isHidden = !transactions.isEmpty
    }
}

extension MonthCarouselCell: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return transactions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = transactionTable.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let tx = transactions[indexPath.row]
        let amountStr = tx.amount.currencyString
        cell.textLabel?.text = "\(tx.date.description) - \(amountStr)"
        cell.imageView?.image = UIImage(systemName: "chevron.right")
        return cell
    }
}
