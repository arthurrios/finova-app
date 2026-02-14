//
//  PendingInvitationCell.swift
//  Finova
//
//  Created by Arthur Rios on 13/02/26.
//

import UIKit

final class PendingInvitationCell: UITableViewCell {
    static let identifier = "PendingInvitationCell"

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.cornerRadius = CornerRadius.large
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "envelope.fill")
        iv.tintColor = Colors.mainMagenta
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleSM.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let pulsingDot: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.mainMagenta
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let chevronView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "chevron.right")
        iv.tintColor = Colors.gray400
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        setupView()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        contentView.addSubview(containerView)
        containerView.addSubview(iconView)
        containerView.addSubview(pulsingDot)
        containerView.addSubview(nameLabel)
        containerView.addSubview(subtitleLabel)
        containerView.addSubview(chevronView)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing1),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.spacing1),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),

            iconView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Metrics.spacing4),
            iconView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            pulsingDot.topAnchor.constraint(equalTo: iconView.topAnchor, constant: -2),
            pulsingDot.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 2),
            pulsingDot.widthAnchor.constraint(equalToConstant: 8),
            pulsingDot.heightAnchor.constraint(equalToConstant: 8),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Metrics.spacing3),
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Metrics.spacing4),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -Metrics.spacing3),

            subtitleLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -Metrics.spacing3),

            chevronView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Metrics.spacing4),
            chevronView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 12),
            chevronView.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    func configure(with invitation: GroupInvitation) {
        nameLabel.text = invitation.groupName
        subtitleLabel.text = String(format: "budgetGroups.cell.pendingInvite".localized, invitation.inviterName)
    }
}
