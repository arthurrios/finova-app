//
//  MemberBadge.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class MemberBadge: UIView {
    private let label: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = CornerRadius.small
        clipsToBounds = true
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.spacing1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.spacing1),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing2),
        ])
    }

    func configure(role: GroupRole) {
        switch role {
        case .owner:
            label.text = "sharing.role.owner".localized
            backgroundColor = Colors.lowMagenta
            label.textColor = Colors.mainMagenta
        case .member:
            label.text = "sharing.role.member".localized
            backgroundColor = Colors.gray300
            label.textColor = Colors.gray600
        }
    }
}
