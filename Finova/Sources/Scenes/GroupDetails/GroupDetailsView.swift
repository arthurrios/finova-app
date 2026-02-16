//
//  GroupDetailsView.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class GroupDetailsView: UIView {
    weak var delegate: GroupDetailsViewDelegate?

    // MARK: - Header
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
        label.text = "groupDetails.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Scroll Content
    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Group Info Card
    private let groupInfoHeaderView = CardHeader(
        headerTitle: "groupDetails.info.header.title".localized)

    private lazy var groupInfoContentView: UIStackView = {
        let stackView = UIStackView(
            axis: .vertical, spacing: Metrics.spacing4,
            arrangedSubviews: [groupNameRow, ownerRow, createdDateRow, currencyRow])
        stackView.layoutMargins = UIEdgeInsets(
            top: Metrics.spacing5, left: Metrics.spacing5,
            bottom: Metrics.spacing5, right: Metrics.spacing5)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.backgroundColor = Colors.gray100
        stackView.layer.borderWidth = 1
        stackView.layer.borderColor = Colors.gray300.cgColor
        stackView.layer.cornerRadius = CornerRadius.extraLarge
        stackView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        stackView.clipsToBounds = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    // Detail rows
    private lazy var groupNameRow: UIView = createDetailRow(
        title: "groupDetails.name.label".localized, value: "")
    private lazy var ownerRow: UIView = createDetailRow(
        title: "groupDetails.owner.label".localized, value: "")
    private lazy var createdDateRow: UIView = createDetailRow(
        title: "groupDetails.created.label".localized, value: "")
    private lazy var currencyRow: UIView = createDetailRow(
        title: "groupDetails.currency.title".localized, value: "")

    private let currencyChevron: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "chevron.right")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        iv.tintColor = Colors.gray500
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    // MARK: - Rename Button (profile avatar edit badge style)
    private let renameButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.backgroundColor = Colors.mainMagenta
        btn.translatesAutoresizingMaskIntoConstraints = false

        let badgeSize: CGFloat = 24
        let iconSize: CGFloat = 12

        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: badgeSize),
            btn.heightAnchor.constraint(equalToConstant: badgeSize),
        ])

        btn.layer.cornerRadius = badgeSize / 2
        btn.clipsToBounds = true

        if let editImage = UIImage(named: "edit")?.withRenderingMode(.alwaysTemplate) {
            let iconView = UIImageView(image: editImage)
            iconView.tintColor = .white
            iconView.contentMode = .scaleAspectFit
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.isUserInteractionEnabled = false
            btn.addSubview(iconView)

            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: iconSize),
                iconView.heightAnchor.constraint(equalToConstant: iconSize),
            ])
        }

        return btn
    }()

    // MARK: - Members Section
    private let membersSectionHeaderView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let label = UILabel()
        label.text = "groupDetails.members.title".localized.uppercased()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.spacing2),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.spacing3),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }()

    let inviteButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("groupDetails.invite.button".localized, for: .normal)
        btn.titleLabel?.font = Fonts.buttonSM.font
        btn.setTitleColor(Colors.mainMagenta, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    let membersTableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.showsVerticalScrollIndicator = false
        table.isScrollEnabled = false
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    var membersTableHeightConstraint: NSLayoutConstraint?
    var sharedCardsTableHeightConstraint: NSLayoutConstraint?

    // MARK: - Shared Cards Section
    private let sharedCardsSectionHeaderView = createSectionHeader(
        title: "groupDetails.sharedCards.title".localized)

    let sharedCardsTableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.isScrollEnabled = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 170
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private let emptyCardsView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView()
        iconView.image = UIImage(systemName: "creditcard")
        iconView.tintColor = Colors.gray400
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.fontStyle = Fonts.titleSM
        titleLabel.text = "groupDetails.sharedCards.empty.title".localized
        titleLabel.applyStyle()
        titleLabel.textColor = Colors.gray500
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.font = Fonts.textSM.font
        subtitleLabel.text = "groupDetails.sharedCards.empty.subtitle".localized
        subtitleLabel.textColor = Colors.gray400
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(
            axis: .vertical, spacing: Metrics.spacing3,
            alignment: .center, arrangedSubviews: [iconView, titleLabel, subtitleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.spacing5),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Metrics.spacing5),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.spacing8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.spacing8),
        ])

        return container
    }()

    // MARK: - Import Section
    private let importSectionHeaderView = createSectionHeader(
        title: "groupDetails.migration.title".localized)

    private let importDataContainer: UIView = {
        let container = createSettingContainer()
        container.isUserInteractionEnabled = true
        return container
    }()

    private let importDataIconView = createIconView(imageName: "square.and.arrow.down.on.square", tintColor: Colors.mainMagenta)
    private let importDataLabel = createSettingLabel(text: "groupDetails.migration.button".localized)

    // MARK: - Danger Zone
    private let dangerSectionHeaderView = createSectionHeader(title: "groupDetails.dangerZone.title".localized)

    private let leaveGroupContainer: UIView = {
        let container = createSettingContainer()
        container.isUserInteractionEnabled = true
        return container
    }()

    private let leaveGroupIconView = createIconView(imageName: "rectangle.portrait.and.arrow.right", tintColor: Colors.mainRed)
    private let leaveGroupLabel: UILabel = {
        let label = createSettingLabel(text: "groupDetails.leave.button".localized)
        label.textColor = Colors.mainRed
        return label
    }()

    private let deleteGroupContainer: UIView = {
        let container = createSettingContainer()
        container.isUserInteractionEnabled = true
        return container
    }()

    private let deleteGroupIconView = createIconView(imageName: "trash", tintColor: Colors.mainRed)
    private let deleteGroupLabel: UILabel = {
        let label = createSettingLabel(text: "groupDetails.delete.button".localized)
        label.textColor = Colors.mainRed
        return label
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

    // MARK: - Setup

    private func setupView() {
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        headerItemsView.addSubview(headerTitleLabel)

        addSubview(scrollView)
        scrollView.addSubview(contentStackView)

        // Info card
        contentStackView.addArrangedSubview(groupInfoHeaderView)
        contentStackView.addArrangedSubview(groupInfoContentView)
        contentStackView.setCustomSpacing(0, after: groupInfoHeaderView)

        // Add rename button to the name row
        groupNameRow.addSubview(renameButton)
        NSLayoutConstraint.activate([
            renameButton.trailingAnchor.constraint(equalTo: groupNameRow.trailingAnchor),
            renameButton.centerYAnchor.constraint(equalTo: groupNameRow.centerYAnchor),
        ])

        // Add chevron to currency row and make it tappable
        currencyRow.addSubview(currencyChevron)
        // Move the value label trailing to the left of the chevron
        if let valueLabel = currencyRow.subviews.compactMap({ $0 as? UILabel }).last {
            // Remove existing trailing constraint
            for constraint in currencyRow.constraints where constraint.firstItem === valueLabel && constraint.firstAnchor == valueLabel.trailingAnchor {
                constraint.isActive = false
            }
            valueLabel.trailingAnchor.constraint(equalTo: currencyChevron.leadingAnchor, constant: -Metrics.spacing2).isActive = true
        }
        NSLayoutConstraint.activate([
            currencyChevron.trailingAnchor.constraint(equalTo: currencyRow.trailingAnchor),
            currencyChevron.centerYAnchor.constraint(equalTo: currencyRow.centerYAnchor),
        ])
        currencyRow.isUserInteractionEnabled = true
        let currencyTap = UITapGestureRecognizer(target: self, action: #selector(currencyTapped))
        currencyRow.addGestureRecognizer(currencyTap)

        // Members section
        contentStackView.addArrangedSubview(membersSectionHeaderView)
        membersSectionHeaderView.addSubview(inviteButton)
        contentStackView.addArrangedSubview(membersTableView)

        membersTableHeightConstraint = membersTableView.heightAnchor.constraint(equalToConstant: 0)
        membersTableHeightConstraint?.isActive = true

        // Shared cards section
        contentStackView.addArrangedSubview(sharedCardsSectionHeaderView)
        contentStackView.addArrangedSubview(emptyCardsView)
        contentStackView.addArrangedSubview(sharedCardsTableView)

        sharedCardsTableHeightConstraint = sharedCardsTableView.heightAnchor.constraint(equalToConstant: 0)
        sharedCardsTableHeightConstraint?.isActive = true

        // Import section
        contentStackView.addArrangedSubview(importSectionHeaderView)
        setupImportDataContainer()
        contentStackView.addArrangedSubview(importDataContainer)

        // Danger zone
        contentStackView.addArrangedSubview(dangerSectionHeaderView)
        setupLeaveGroupContainer()
        contentStackView.addArrangedSubview(leaveGroupContainer)
        setupDeleteGroupContainer()
        contentStackView.addArrangedSubview(deleteGroupContainer)

        // Glass effect on back button
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .clear)
            glassEffect.isInteractive = true
            let glassView = UIVisualEffectView(effect: glassEffect)
            glassView.translatesAutoresizingMaskIntoConstraints = false
            backButtonGlassContainer.insertSubview(glassView, at: 0)
            glassView.pinToSuperview()
            backButtonGlassContainer.layer.cornerRadius = 18
            backButtonGlassContainer.clipsToBounds = true
        }

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        inviteButton.addTarget(self, action: #selector(inviteTapped), for: .touchUpInside)
        renameButton.addTarget(self, action: #selector(renameTapped), for: .touchUpInside)

        let leaveTap = UITapGestureRecognizer(target: self, action: #selector(leaveGroupTapped))
        leaveGroupContainer.addGestureRecognizer(leaveTap)

        let deleteTap = UITapGestureRecognizer(target: self, action: #selector(deleteGroupTapped))
        deleteGroupContainer.addGestureRecognizer(deleteTap)

        let importTap = UITapGestureRecognizer(target: self, action: #selector(importDataTapped))
        importDataContainer.addGestureRecognizer(importTap)
    }

    private func setupLeaveGroupContainer() {
        leaveGroupContainer.addSubview(leaveGroupIconView)
        leaveGroupContainer.addSubview(leaveGroupLabel)

        NSLayoutConstraint.activate([
            leaveGroupIconView.leadingAnchor.constraint(equalTo: leaveGroupContainer.leadingAnchor, constant: Metrics.spacing4),
            leaveGroupIconView.centerYAnchor.constraint(equalTo: leaveGroupContainer.centerYAnchor),
            leaveGroupIconView.widthAnchor.constraint(equalToConstant: 20),
            leaveGroupIconView.heightAnchor.constraint(equalToConstant: 20),

            leaveGroupLabel.leadingAnchor.constraint(equalTo: leaveGroupIconView.trailingAnchor, constant: Metrics.spacing3),
            leaveGroupLabel.centerYAnchor.constraint(equalTo: leaveGroupContainer.centerYAnchor),
        ])
    }

    private func setupDeleteGroupContainer() {
        deleteGroupContainer.addSubview(deleteGroupIconView)
        deleteGroupContainer.addSubview(deleteGroupLabel)

        NSLayoutConstraint.activate([
            deleteGroupIconView.leadingAnchor.constraint(equalTo: deleteGroupContainer.leadingAnchor, constant: Metrics.spacing4),
            deleteGroupIconView.centerYAnchor.constraint(equalTo: deleteGroupContainer.centerYAnchor),
            deleteGroupIconView.widthAnchor.constraint(equalToConstant: 20),
            deleteGroupIconView.heightAnchor.constraint(equalToConstant: 20),

            deleteGroupLabel.leadingAnchor.constraint(equalTo: deleteGroupIconView.trailingAnchor, constant: Metrics.spacing3),
            deleteGroupLabel.centerYAnchor.constraint(equalTo: deleteGroupContainer.centerYAnchor),
        ])
    }

    private func setupImportDataContainer() {
        importDataContainer.addSubview(importDataIconView)
        importDataContainer.addSubview(importDataLabel)

        NSLayoutConstraint.activate([
            importDataIconView.leadingAnchor.constraint(equalTo: importDataContainer.leadingAnchor, constant: Metrics.spacing4),
            importDataIconView.centerYAnchor.constraint(equalTo: importDataContainer.centerYAnchor),
            importDataIconView.widthAnchor.constraint(equalToConstant: 20),
            importDataIconView.heightAnchor.constraint(equalToConstant: 20),

            importDataLabel.leadingAnchor.constraint(equalTo: importDataIconView.trailingAnchor, constant: Metrics.spacing3),
            importDataLabel.centerYAnchor.constraint(equalTo: importDataContainer.centerYAnchor),
        ])
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

            headerTitleLabel.leadingAnchor.constraint(
                equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
            headerTitleLabel.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),
            headerTitleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: headerItemsView.layoutMarginsGuide.trailingAnchor),

            // Scroll content
            scrollView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStackView.topAnchor.constraint(
                equalTo: scrollView.topAnchor, constant: Metrics.spacing4),
            contentStackView.leadingAnchor.constraint(
                equalTo: scrollView.leadingAnchor, constant: Metrics.spacing4),
            contentStackView.trailingAnchor.constraint(
                equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing4),
            contentStackView.bottomAnchor.constraint(
                equalTo: scrollView.bottomAnchor, constant: -Metrics.spacing4),
            contentStackView.widthAnchor.constraint(
                equalTo: scrollView.widthAnchor, constant: -2 * Metrics.spacing4),

            // Invite button (trailing in members section header)
            inviteButton.trailingAnchor.constraint(
                equalTo: membersSectionHeaderView.trailingAnchor, constant: -Metrics.spacing2),
            inviteButton.centerYAnchor.constraint(equalTo: membersSectionHeaderView.centerYAnchor),
        ])
    }

    // MARK: - Factory Methods

    private static func createSettingContainer() -> UIView {
        let container = UIView()
        container.backgroundColor = Colors.gray100
        container.layer.cornerRadius = CornerRadius.large
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 56).isActive = true
        return container
    }

    private static func createIconView(imageName: String, tintColor: UIColor = Colors.gray600) -> UIImageView {
        let iv = UIImageView()
        iv.image = UIImage(systemName: imageName)?.withRenderingMode(.alwaysTemplate)
        iv.tintColor = tintColor
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.widthAnchor.constraint(equalToConstant: 20).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return iv
    }

    private static func createSettingLabel(text: String) -> UILabel {
        let label = UILabel()
        label.font = Fonts.titleSM.font
        label.textColor = Colors.gray700
        label.text = text
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func createSectionHeader(title: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = title.uppercased()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.spacing2),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.spacing3),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 24),
        ])
        return container
    }

    // MARK: - Detail Row

    private func createDetailRow(title: String, value: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = Fonts.textSM.font
        titleLabel.textColor = Colors.gray600
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = Fonts.textSM.font
        valueLabel.textColor = Colors.gray700
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: Metrics.spacing3),

            container.heightAnchor.constraint(equalToConstant: 24),
        ])
        return container
    }

    // MARK: - Configuration

    func configure(with group: BudgetGroup) {
        headerTitleLabel.text = group.name
        headerTitleLabel.applyStyle()
        headerTitleLabel.textColor = Colors.gray700

        // Update detail rows
        updateDetailRowValue(groupNameRow, value: group.name)
        updateDetailRowValue(ownerRow, value: group.ownerName)
        updateDetailRowValue(currencyRow, value: group.currency)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        updateDetailRowValue(createdDateRow, value: formatter.string(from: group.createdAt))

        // Show/hide edit controls based on ownership
        renameButton.isHidden = !group.isOwner
        currencyChevron.isHidden = !group.isOwner
        currencyRow.isUserInteractionEnabled = group.isOwner

        // Show/hide danger zone based on ownership
        leaveGroupContainer.isHidden = group.isOwner
        deleteGroupContainer.isHidden = !group.isOwner

        // Show/hide invite button based on permissions
        inviteButton.isHidden = !group.isOwner && !BudgetGroupService.shared.currentUserCan(\.canInviteMembers, in: group)

        // Show/hide shared cards empty state
        let hasSharedCards = !group.sharedCards.isEmpty
        emptyCardsView.isHidden = hasSharedCards
        sharedCardsTableView.isHidden = !hasSharedCards

        // Show/hide import section (owner only)
        importSectionHeaderView.isHidden = !group.isOwner
        importDataContainer.isHidden = !group.isOwner
    }

    func updateMembersTableHeight(count: Int) {
        membersTableHeightConstraint?.constant = CGFloat(count) * 80
    }

    func updateSharedCardsTableHeight() {
        // Defer to next layout pass so Auto Layout calculates actual cell heights
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.sharedCardsTableView.layoutIfNeeded()
            self.sharedCardsTableHeightConstraint?.constant = self.sharedCardsTableView.contentSize.height
        }
    }

    private func updateDetailRowValue(_ row: UIView, value: String) {
        if let valueLabel = row.subviews.last as? UILabel {
            valueLabel.text = value
        }
    }

    // MARK: - Actions

    @objc private func backTapped() { delegate?.handleDidTapBackButton() }
    @objc private func inviteTapped() { delegate?.didTapInvite() }
    @objc private func renameTapped() { delegate?.didTapRenameGroup() }
    @objc private func leaveGroupTapped() { delegate?.didTapLeaveGroup() }
    @objc private func deleteGroupTapped() { delegate?.didTapDeleteGroup() }
    @objc private func currencyTapped() { delegate?.didTapCurrency() }
    @objc private func importDataTapped() { delegate?.didTapMigrateData() }
}
