//
//  BudgetGroupCell.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class BudgetGroupCell: UITableViewCell {
    static let identifier = "BudgetGroupCell"

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.cornerRadius = CornerRadius.large
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let groupIconView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "person.3.fill")
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

    private let memberCountLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let avatarStack = GroupAvatarStack()

    private let ownerBadge = MemberBadge()

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
        containerView.addSubview(groupIconView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(memberCountLabel)
        containerView.addSubview(avatarStack)
        containerView.addSubview(ownerBadge)
        containerView.addSubview(chevronView)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            // Container: full width with vertical spacing between cells
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing1),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.spacing1),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),

            // Group icon: leading, centered vertically
            groupIconView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Metrics.spacing4),
            groupIconView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            groupIconView.widthAnchor.constraint(equalToConstant: 32),
            groupIconView.heightAnchor.constraint(equalToConstant: 32),

            // Name: after icon, top-biased
            nameLabel.leadingAnchor.constraint(equalTo: groupIconView.trailingAnchor, constant: Metrics.spacing3),
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Metrics.spacing4),

            // Member count: below name
            memberCountLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            memberCountLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),

            // Owner badge: after name, same baseline
            ownerBadge.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: Metrics.spacing2),
            ownerBadge.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            // Avatar stack: trailing, centered
            avatarStack.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -Metrics.spacing3),
            avatarStack.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            // Constrain name to not overlap avatar stack
            nameLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: avatarStack.leadingAnchor, constant: -Metrics.spacing3),

            // Chevron: trailing edge
            chevronView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Metrics.spacing4),
            chevronView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 12),
            chevronView.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    func configure(with group: BudgetGroup) {
        nameLabel.text = group.name
        memberCountLabel.text = String(
            format: "budgetGroups.cell.memberCount".localized,
            group.members.count
        )
        ownerBadge.isHidden = !group.isOwner
        ownerBadge.configure(role: group.isOwner ? .owner : .member)
        avatarStack.configure(
            with: group.members.prefix(3).map { $0.name },
            totalCount: group.members.count
        )
    }
}
