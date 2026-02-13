//
//  BudgetGroupsView.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class BudgetGroupsView: UIView {
    weak var delegate: BudgetGroupsViewDelegate?

    // MARK: - Header (exact same pattern as SettingsView)
    private let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight - 12).isActive = true
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
        label.text = "budgetGroups.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Content
    let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.showsVerticalScrollIndicator = false
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    let emptyView: EmptyGroupsView = {
        let view = EmptyGroupsView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // FAB: matches Dashboard addTransactionButton pattern exactly
    private let createGroupButton: UIButton = {
        let btn = UIButton(type: .system)

        if let originalImage = UIImage(named: "plus") {
            let newSize = CGSize(width: 24, height: 24)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
            originalImage.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            btn.setImage(resizedImage, for: .normal)
        }

        btn.imageView?.contentMode = .center
        btn.translatesAutoresizingMaskIntoConstraints = false

        if #available(iOS 26.0, *) {
            btn.tintColor = Colors.mainMagenta
            btn.backgroundColor = .clear
        } else {
            btn.tintColor = Colors.gray100
            btn.backgroundColor = Colors.gray700
            btn.layer.shadowColor = UIColor.black.cgColor
            btn.layer.shadowOffset = CGSize(width: 0, height: 4)
            btn.layer.shadowOpacity = 0.25
            btn.layer.shadowRadius = 4
            btn.layer.shouldRasterize = true
            btn.layer.rasterizationScale = UIScreen.main.scale
        }
        return btn
    }()

    private lazy var createGroupButtonGlassContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
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
        headerItemsView.addSubview(headerTitleLabel)

        addSubview(tableView)
        addSubview(emptyView)
        addSubview(createGroupButtonGlassContainer)
        createGroupButtonGlassContainer.addSubview(createGroupButton)

        // Glass effect on back button (iOS 26+)
        if #available(iOS 26.0, *) {
            let backGlass = UIGlassEffect(style: .clear)
            backGlass.isInteractive = true
            let backGlassView = UIVisualEffectView(effect: backGlass)
            backGlassView.translatesAutoresizingMaskIntoConstraints = false
            backButtonGlassContainer.insertSubview(backGlassView, at: 0)
            backGlassView.pinToSuperview()
            backButtonGlassContainer.layer.cornerRadius = 18
            backButtonGlassContainer.clipsToBounds = true

            // Glass on FAB
            let fabGlass = UIGlassEffect(style: .clear)
            fabGlass.isInteractive = true
            let fabGlassView = UIVisualEffectView(effect: fabGlass)
            fabGlassView.translatesAutoresizingMaskIntoConstraints = false
            createGroupButtonGlassContainer.insertSubview(fabGlassView, at: 0)
            fabGlassView.pinToSuperview()
        }

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        createGroupButton.addTarget(self, action: #selector(createGroupTapped), for: .touchUpInside)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            // Header
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

            // Back button: 36x36 glass container
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

            // Title: left of back button
            headerTitleLabel.leadingAnchor.constraint(
                equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
            headerTitleLabel.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),
            headerTitleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: headerItemsView.layoutMarginsGuide.trailingAnchor),

            // Table
            tableView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing4),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Empty state: centered in table area
            emptyView.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyView.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),

            // FAB: centered bottom, Metrics.addButtonSize (48x48)
            createGroupButtonGlassContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            createGroupButtonGlassContainer.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Metrics.spacing4),
            createGroupButtonGlassContainer.widthAnchor.constraint(equalToConstant: Metrics.addButtonSize),
            createGroupButtonGlassContainer.heightAnchor.constraint(equalToConstant: Metrics.addButtonSize),

            createGroupButton.topAnchor.constraint(equalTo: createGroupButtonGlassContainer.topAnchor),
            createGroupButton.leadingAnchor.constraint(equalTo: createGroupButtonGlassContainer.leadingAnchor),
            createGroupButton.trailingAnchor.constraint(equalTo: createGroupButtonGlassContainer.trailingAnchor),
            createGroupButton.bottomAnchor.constraint(equalTo: createGroupButtonGlassContainer.bottomAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let cornerRadius = createGroupButtonGlassContainer.bounds.height / 2
        createGroupButtonGlassContainer.layer.cornerRadius = cornerRadius
        createGroupButtonGlassContainer.clipsToBounds = true

        if #unavailable(iOS 26.0) {
            createGroupButton.layer.cornerRadius = cornerRadius
            createGroupButton.layer.shadowPath =
                UIBezierPath(
                    roundedRect: createGroupButton.bounds,
                    cornerRadius: cornerRadius
                ).cgPath
        }
    }

    func updateEmptyState(isEmpty: Bool) {
        emptyView.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }

    @objc private func backTapped() { delegate?.handleDidTapBackButton() }
    @objc private func createGroupTapped() { delegate?.didTapCreateGroup() }
}
