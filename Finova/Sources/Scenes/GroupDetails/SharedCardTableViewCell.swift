//
//  SharedCardTableViewCell.swift
//  Finova
//
//  Created by Arthur Rios on 13/02/26.
//

import UIKit

final class SharedCardTableViewCell: UITableViewCell {
    static let identifier = "SharedCardTableViewCell"

    private let cardCell = CreditCardCell()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(cardCell)

        NSLayoutConstraint.activate([
            cardCell.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing2),
            cardCell.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardCell.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardCell.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.spacing2),
        ])
    }

    func configure(with card: CreditCard) {
        cardCell.configure(with: card)
    }
}
