//
//  GroupMemberCell.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class GroupMemberCell: UITableViewCell {
    static let identifier = "GroupMemberCell"

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.cornerRadius = CornerRadius.large
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let avatarView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.mainMagenta.withAlphaComponent(0.2)
        view.layer.cornerRadius = Metrics.profileImageSize / 2
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let avatarLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Colors.mainMagenta
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let emailLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let roleBadge = MemberBadge()

    private let lastActiveLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray400
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let chevronView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "chevron.right")
        iv.tintColor = Colors.gray400
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private var textStack: UIStackView!
    private var trailingStack: UIStackView!
    private var trailingStackToChevronConstraint: NSLayoutConstraint!
    private var trailingStackToContainerConstraint: NSLayoutConstraint!

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
        containerView.addSubview(avatarView)
        avatarView.addSubview(avatarLabel)

        let textStack = UIStackView(axis: .vertical, spacing: 2,
            arrangedSubviews: [nameLabel, emailLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(textStack)

        let trailingStack = UIStackView(axis: .vertical, spacing: Metrics.spacing1,
            alignment: .trailing, arrangedSubviews: [roleBadge, lastActiveLabel])
        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(trailingStack)

        containerView.addSubview(chevronView)

        NSLayoutConstraint.activate([
            avatarLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
        ])

        self.textStack = textStack
        self.trailingStack = trailingStack
    }

    private func setupLayout() {
        trailingStackToChevronConstraint = trailingStack.trailingAnchor.constraint(
            equalTo: chevronView.leadingAnchor, constant: -Metrics.spacing3)
        trailingStackToContainerConstraint = trailingStack.trailingAnchor.constraint(
            equalTo: containerView.trailingAnchor, constant: -Metrics.spacing4)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing1),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.spacing1),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),

            avatarView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Metrics.spacing4),
            avatarView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: Metrics.profileImageSize),
            avatarView.heightAnchor.constraint(equalToConstant: Metrics.profileImageSize),

            textStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: Metrics.spacing3),
            textStack.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            trailingStackToChevronConstraint,
            trailingStack.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            textStack.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -Metrics.spacing3),

            chevronView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Metrics.spacing3),
            chevronView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 12),
            chevronView.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    func configure(with member: GroupMember, isCurrentUserOwner: Bool) {
        nameLabel.text = member.name
        emailLabel.text = member.email
        avatarLabel.text = String(member.name.prefix(1)).uppercased()
        roleBadge.configure(role: member.role)
        lastActiveLabel.text = member.lastActiveDescription

        let showChevron = isCurrentUserOwner && member.role != .owner
        chevronView.isHidden = !showChevron
        trailingStackToChevronConstraint.isActive = showChevron
        trailingStackToContainerConstraint.isActive = !showChevron
    }
}
