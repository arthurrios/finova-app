//
//  AllocationTagsView.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import UIKit

final class AllocationTagsView: UIView {

    weak var delegate: AllocationTagsViewDelegate?

    // MARK: - Header

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
        label.text = "allocationTags.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let headerSubtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.text = "allocationTags.subtitle".localized
        label.textColor = Colors.gray500
        label.textAlignment = .left
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var headerTextStackView = UIStackView(
        axis: .vertical, spacing: Metrics.spacing1,
        arrangedSubviews: [headerTitleLabel, headerSubtitleLabel])

    // MARK: - Content

    let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.showsVerticalScrollIndicator = false
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private let emptyStateIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "tag")
        imageView.tintColor = Colors.gray400
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.text = "allocationTags.emptyState.description".localized
        label.textColor = Colors.gray400
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var emptyStateView: UIView = {
        let view = UIView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(
            axis: .vertical, spacing: Metrics.spacing3, alignment: .center,
            arrangedSubviews: [emptyStateIconView, emptyStateLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            emptyStateIconView.widthAnchor.constraint(equalToConstant: 48),
            emptyStateIconView.heightAnchor.constraint(equalToConstant: 48),

            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Metrics.spacing8),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Metrics.spacing8),
        ])
        return view
    }()

    // FAB, matching the BudgetGroups create button.
    private let createTagButton: UIButton = {
        let button = UIButton(type: .system)

        if let original = UIImage(named: "plus") {
            let size = CGSize(width: 24, height: 24)
            UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
            original.draw(in: CGRect(origin: .zero, size: size))
            let resized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            button.setImage(resized, for: .normal)
        }

        button.imageView?.contentMode = .center
        button.translatesAutoresizingMaskIntoConstraints = false

        if #available(iOS 26.0, *) {
            button.tintColor = Colors.mainMagenta
            button.backgroundColor = .clear
        } else {
            button.tintColor = Colors.gray100
            button.backgroundColor = Colors.gray700
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOffset = CGSize(width: 0, height: 4)
            button.layer.shadowOpacity = 0.25
            button.layer.shadowRadius = 4
            button.layer.shouldRasterize = true
            button.layer.rasterizationScale = UIScreen.main.scale
        }
        return button
    }()

    private lazy var createTagButtonGlassContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    // MARK: - Init

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
        addSubview(emptyStateView)
        addSubview(createTagButtonGlassContainer)
        createTagButtonGlassContainer.addSubview(createTagButton)

        if #available(iOS 26.0, *) {
            let backGlass = UIGlassEffect(style: .clear)
            backGlass.isInteractive = true
            let backGlassView = UIVisualEffectView(effect: backGlass)
            backGlassView.translatesAutoresizingMaskIntoConstraints = false
            backButtonGlassContainer.insertSubview(backGlassView, at: 0)
            backGlassView.pinToSuperview()
            backButtonGlassContainer.layer.cornerRadius = 18
            backButtonGlassContainer.clipsToBounds = true

            let fabGlass = UIGlassEffect(style: .clear)
            fabGlass.isInteractive = true
            let fabGlassView = UIVisualEffectView(effect: fabGlass)
            fabGlassView.translatesAutoresizingMaskIntoConstraints = false
            createTagButtonGlassContainer.insertSubview(fabGlassView, at: 0)
            fabGlassView.pinToSuperview()
        }

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        createTagButton.addTarget(self, action: #selector(createTagTapped), for: .touchUpInside)
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
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyStateView.topAnchor.constraint(equalTo: tableView.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(
                equalTo: createTagButtonGlassContainer.topAnchor, constant: -Metrics.spacing4),

            createTagButtonGlassContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            createTagButtonGlassContainer.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Metrics.spacing4),
            createTagButtonGlassContainer.widthAnchor.constraint(
                equalToConstant: Metrics.addButtonSize),
            createTagButtonGlassContainer.heightAnchor.constraint(
                equalToConstant: Metrics.addButtonSize),

            createTagButton.topAnchor.constraint(equalTo: createTagButtonGlassContainer.topAnchor),
            createTagButton.leadingAnchor.constraint(
                equalTo: createTagButtonGlassContainer.leadingAnchor),
            createTagButton.trailingAnchor.constraint(
                equalTo: createTagButtonGlassContainer.trailingAnchor),
            createTagButton.bottomAnchor.constraint(
                equalTo: createTagButtonGlassContainer.bottomAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let radius = createTagButtonGlassContainer.bounds.height / 2
        createTagButtonGlassContainer.layer.cornerRadius = radius
        createTagButtonGlassContainer.clipsToBounds = true

        if #unavailable(iOS 26.0) {
            createTagButton.layer.cornerRadius = radius
            createTagButton.layer.shadowPath = UIBezierPath(
                roundedRect: createTagButton.bounds, cornerRadius: radius).cgPath
        }
    }

    func updateEmptyState(isEmpty: Bool) {
        emptyStateView.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }

    @objc private func backTapped() { delegate?.didTapBackButton() }
    @objc private func createTagTapped() { delegate?.didTapCreateTag() }
}
