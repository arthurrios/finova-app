//
//  AllocationTagCategoryCell.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import UIKit

final class AllocationTagCategoryCell: UITableViewCell {

    static let identifier = "AllocationTagCategoryCell"

    private let iconContainer: UIView = {
        let view = UIView()
        view.layer.cornerRadius = CornerRadius.medium
        view.backgroundColor = Colors.gray200
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.borderWidth = 1
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.gray500
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Names the tag that currently owns this category, so a move is never a surprise.
    private let ownerLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var textStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [nameLabel, ownerLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let checkmarkView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "checkmark")
        imageView.tintColor = Colors.mainMagenta
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = Colors.gray100
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        contentView.addSubview(iconContainer)
        iconContainer.addSubview(iconView)
        contentView.addSubview(textStackView)
        contentView.addSubview(checkmarkView)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: Metrics.spacing5),
            iconContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: Metrics.spacing8),
            iconContainer.heightAnchor.constraint(equalToConstant: Metrics.spacing8),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.spacing5),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.spacing5),

            textStackView.leadingAnchor.constraint(
                equalTo: iconContainer.trailingAnchor, constant: Metrics.spacing3),
            textStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStackView.trailingAnchor.constraint(
                lessThanOrEqualTo: checkmarkView.leadingAnchor, constant: -Metrics.spacing3),

            checkmarkView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -Metrics.spacing5),
            checkmarkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 16),
            checkmarkView.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    func configure(category: TransactionCategory, isSelected: Bool, otherTagName: String?) {
        iconView.image = UIImage(named: category.iconName(for: .expense))?
            .withRenderingMode(.alwaysTemplate)
        nameLabel.text = category.displayName

        checkmarkView.isHidden = !isSelected
        iconView.tintColor = isSelected ? Colors.mainMagenta : Colors.gray500

        if let otherTagName {
            ownerLabel.text = String(
                format: "allocationTags.categories.inOtherTag".localized, otherTagName)
            ownerLabel.isHidden = false
        } else {
            ownerLabel.text = nil
            ownerLabel.isHidden = true
        }
    }
}
