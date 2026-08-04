//
//  AllocationTagCategoriesView.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import UIKit

protocol AllocationTagCategoriesViewDelegate: AnyObject {
    func didTapBackButton()
}

final class AllocationTagCategoriesView: UIView {

    weak var delegate: AllocationTagCategoriesViewDelegate?

    private let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight).isActive = true
        return view
    }()

    private let headerItemsView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing4, leading: Metrics.spacing5, bottom: Metrics.spacing5,
            trailing: Metrics.spacing5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 26.0, *) {
            button.tintColor = Colors.gray700
        } else {
            button.tintColor = Colors.gray500
        }
        return button
    }()

    private lazy var backButtonGlassContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.applyStyle()
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let headerSubtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.text = "allocationTags.categories.subtitle".localized
        label.textColor = Colors.gray500
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var headerTextStackView = UIStackView(
        axis: .vertical, spacing: Metrics.spacing1,
        arrangedSubviews: [headerTitleLabel, headerSubtitleLabel])

    let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = Colors.gray100
        table.separatorStyle = .singleLine
        table.separatorInset = .zero
        table.separatorColor = Colors.gray300
        table.layer.borderWidth = 1
        table.layer.borderColor = Colors.gray300.cgColor
        table.layer.cornerRadius = CornerRadius.extraLarge
        table.clipsToBounds = true
        table.showsVerticalScrollIndicator = false
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray200
        setupView()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        headerItemsView.addSubview(headerTextStackView)
        headerTextStackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(tableView)

        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .clear)
            glass.isInteractive = true
            let glassView = UIVisualEffectView(effect: glass)
            glassView.translatesAutoresizingMaskIntoConstraints = false
            backButtonGlassContainer.insertSubview(glassView, at: 0)
            glassView.pinToSuperview()
            backButtonGlassContainer.layer.cornerRadius = 18
            backButtonGlassContainer.clipsToBounds = true
        }

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

            backButtonGlassContainer.topAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
            backButtonGlassContainer.leadingAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
            backButtonGlassContainer.widthAnchor.constraint(equalToConstant: 36),
            backButtonGlassContainer.heightAnchor.constraint(equalToConstant: 36),

            backButton.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
            backButton.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
            backButton.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
            backButton.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),

            headerTextStackView.leadingAnchor.constraint(
                equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
            headerTextStackView.centerYAnchor.constraint(
                equalTo: backButtonGlassContainer.centerYAnchor),
            headerTextStackView.trailingAnchor.constraint(
                lessThanOrEqualTo: headerItemsView.layoutMarginsGuide.trailingAnchor),

            tableView.topAnchor.constraint(
                equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing4),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            tableView.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Metrics.spacing4),
        ])
    }

    func configure(tagName: String) {
        headerTitleLabel.text = tagName
        headerTitleLabel.applyStyle()
    }

    @objc private func backTapped() { delegate?.didTapBackButton() }
}
