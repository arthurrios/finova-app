//
//  EmptyGroupsView.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class EmptyGroupsView: UIView {
    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "person.3")
        iv.tintColor = Colors.gray400
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.text = "budgetGroups.empty.title".localized
        label.applyStyle()
        label.textColor = Colors.gray500
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.text = "budgetGroups.empty.subtitle".localized
        label.textColor = Colors.gray400
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        let stack = UIStackView(
            axis: .vertical, spacing: Metrics.spacing3,
            alignment: .center, arrangedSubviews: [iconView, titleLabel, subtitleLabel])
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),

            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing8),
        ])
    }
}
