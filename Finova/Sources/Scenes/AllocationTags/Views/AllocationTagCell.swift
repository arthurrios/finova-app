//
//  AllocationTagCell.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import UIKit

/// One tag in the management list. Same card-row shape as `BudgetGroupCell`, with the tag's own colour
/// standing in for that cell's fixed magenta.
final class AllocationTagCell: UITableViewCell {

    static let identifier = "AllocationTagCell"

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.cornerRadius = CornerRadius.large
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// A tinted disc behind the glyph, so the tag's colour is legible at a glance even when the icon
    /// is the generic default and every row would otherwise look alike.
    private let iconContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleSM.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let categoryCountLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let chevronView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "chevron.right")
        imageView.tintColor = Colors.gray400
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
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
        containerView.addSubview(iconContainer)
        iconContainer.addSubview(iconView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(categoryCountLabel)
        containerView.addSubview(chevronView)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing1),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -Metrics.spacing1),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),

            iconContainer.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor, constant: Metrics.spacing4),
            iconContainer.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 32),
            iconContainer.heightAnchor.constraint(equalToConstant: 32),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.inputIconSize),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.inputIconSize),

            nameLabel.leadingAnchor.constraint(
                equalTo: iconContainer.trailingAnchor, constant: Metrics.spacing3),
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Metrics.spacing3),
            nameLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: chevronView.leadingAnchor, constant: -Metrics.spacing3),

            categoryCountLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            categoryCountLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            categoryCountLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: chevronView.leadingAnchor, constant: -Metrics.spacing3),

            chevronView.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor, constant: -Metrics.spacing4),
            chevronView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 12),
            chevronView.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconContainer.layer.cornerRadius = iconContainer.bounds.height / 2
    }

    func configure(with tag: AllocationTag, categoryCount: Int) {
        let ink = tag.color.ink
        iconContainer.backgroundColor = ink.withAlphaComponent(0.12)
        iconView.image = tag.icon.image
        iconView.tintColor = ink

        nameLabel.text = tag.displayName

        switch categoryCount {
        case 0:
            categoryCountLabel.text = "allocationTags.row.noCategories".localized
        case 1:
            categoryCountLabel.text = "allocationTags.row.categoryCount.one".localized
        default:
            categoryCountLabel.text = String(
                format: "allocationTags.row.categoryCount".localized, categoryCount)
        }
    }
}
