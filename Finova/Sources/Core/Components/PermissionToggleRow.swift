//
//  PermissionToggleRow.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class PermissionToggleRow: UIView {
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleSM.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let toggle: UISwitch = {
        let toggle = UISwitch()
        toggle.onTintColor = Colors.mainMagenta
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }()

    var onToggleChanged: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = Colors.gray100
        layer.cornerRadius = CornerRadius.large
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 52).isActive = true

        let textStack = UIStackView(axis: .vertical, spacing: 2, arrangedSubviews: [titleLabel, descriptionLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textStack)
        addSubview(toggle)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),

            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -Metrics.spacing3),
        ])

        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
    }

    @objc private func toggleChanged() {
        onToggleChanged?(toggle.isOn)
    }

    func configure(title: String, description: String, isOn: Bool) {
        titleLabel.text = title
        descriptionLabel.text = description
        toggle.isOn = isOn
    }
}
