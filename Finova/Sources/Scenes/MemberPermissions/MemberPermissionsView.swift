//
//  MemberPermissionsView.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class MemberPermissionsView: UIView {
    weak var delegate: MemberPermissionsViewDelegate?

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
        label.text = "permissions.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Member Info Card
    private let memberInfoCard: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.cornerRadius = CornerRadius.large
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let memberAvatarView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.mainMagenta.withAlphaComponent(0.2)
        view.layer.cornerRadius = Metrics.profileImageSize / 2
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let memberAvatarLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Colors.mainMagenta
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let memberNameLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let memberEmailLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
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
        stack.spacing = Metrics.spacing3
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Permission Sections

    // Transactions
    private let transactionsSectionHeader = createSectionHeader(title: "permissions.section.transactions".localized)
    let canCreateToggle = PermissionToggleRow()
    let canEditToggle = PermissionToggleRow()
    let canDeleteToggle = PermissionToggleRow()

    // Budgets
    private let budgetsSectionHeader = createSectionHeader(title: "permissions.section.budgets".localized)
    let canEditBudgetsToggle = PermissionToggleRow()
    let canEditAllocationsToggle = PermissionToggleRow()

    // Credit Cards
    private let creditCardsSectionHeader = createSectionHeader(title: "permissions.section.creditCards".localized)
    let canViewCardsToggle = PermissionToggleRow()
    let canManageCardsToggle = PermissionToggleRow()

    // Group
    private let groupSectionHeader = createSectionHeader(title: "permissions.section.group".localized)
    let canInviteToggle = PermissionToggleRow()

    // MARK: - Footer
    private let footerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let footerBorderView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let removeMemberButton = Button(variant: .outlined, label: "permissions.removeMember.button".localized)

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
        // Header
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        headerItemsView.addSubview(headerTitleLabel)

        // Member info card
        memberInfoCard.addSubview(memberAvatarView)
        memberAvatarView.addSubview(memberAvatarLabel)

        let nameStack = UIStackView(axis: .vertical, spacing: 2,
            arrangedSubviews: [memberNameLabel, memberEmailLabel])
        nameStack.translatesAutoresizingMaskIntoConstraints = false
        memberInfoCard.addSubview(nameStack)

        NSLayoutConstraint.activate([
            memberInfoCard.heightAnchor.constraint(equalToConstant: 72),
            memberAvatarView.leadingAnchor.constraint(equalTo: memberInfoCard.leadingAnchor, constant: Metrics.spacing4),
            memberAvatarView.centerYAnchor.constraint(equalTo: memberInfoCard.centerYAnchor),
            memberAvatarView.widthAnchor.constraint(equalToConstant: Metrics.profileImageSize),
            memberAvatarView.heightAnchor.constraint(equalToConstant: Metrics.profileImageSize),
            memberAvatarLabel.centerXAnchor.constraint(equalTo: memberAvatarView.centerXAnchor),
            memberAvatarLabel.centerYAnchor.constraint(equalTo: memberAvatarView.centerYAnchor),
            nameStack.leadingAnchor.constraint(equalTo: memberAvatarView.trailingAnchor, constant: Metrics.spacing3),
            nameStack.centerYAnchor.constraint(equalTo: memberInfoCard.centerYAnchor),
            nameStack.trailingAnchor.constraint(lessThanOrEqualTo: memberInfoCard.trailingAnchor, constant: -Metrics.spacing4),
        ])

        // Scroll content
        addSubview(scrollView)
        scrollView.addSubview(contentStackView)

        contentStackView.addArrangedSubview(memberInfoCard)

        // Transactions
        canCreateToggle.configure(title: "permission.createTransactions".localized, description: "", isOn: true)
        canEditToggle.configure(title: "permission.editTransactions".localized, description: "", isOn: false)
        canDeleteToggle.configure(title: "permission.deleteTransactions".localized, description: "", isOn: false)
        let transactionsCard = createSectionCard(toggles: [canCreateToggle, canEditToggle, canDeleteToggle])
        contentStackView.addArrangedSubview(transactionsSectionHeader)
        contentStackView.addArrangedSubview(transactionsCard)
        contentStackView.setCustomSpacing(Metrics.spacing2, after: transactionsSectionHeader)

        // Budgets
        canEditBudgetsToggle.configure(title: "permission.editBudgets".localized, description: "", isOn: false)
        canEditAllocationsToggle.configure(title: "permission.editAllocations".localized, description: "", isOn: false)
        let budgetsCard = createSectionCard(toggles: [canEditBudgetsToggle, canEditAllocationsToggle])
        contentStackView.addArrangedSubview(budgetsSectionHeader)
        contentStackView.addArrangedSubview(budgetsCard)
        contentStackView.setCustomSpacing(Metrics.spacing2, after: budgetsSectionHeader)

        // Credit Cards
        canViewCardsToggle.configure(title: "permission.viewCreditCards".localized, description: "", isOn: false)
        canManageCardsToggle.configure(title: "permission.manageCreditCards".localized, description: "", isOn: false)
        let creditCardsCard = createSectionCard(toggles: [canViewCardsToggle, canManageCardsToggle])
        contentStackView.addArrangedSubview(creditCardsSectionHeader)
        contentStackView.addArrangedSubview(creditCardsCard)
        contentStackView.setCustomSpacing(Metrics.spacing2, after: creditCardsSectionHeader)

        // Group
        canInviteToggle.configure(title: "permission.inviteMembers".localized, description: "", isOn: false)
        let groupCard = createSectionCard(toggles: [canInviteToggle])
        contentStackView.addArrangedSubview(groupSectionHeader)
        contentStackView.addArrangedSubview(groupCard)
        contentStackView.setCustomSpacing(Metrics.spacing2, after: groupSectionHeader)

        // Footer
        addSubview(footerView)
        footerView.addSubview(footerBorderView)
        footerView.addSubview(removeMemberButton)

        // Glass on back button
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
        removeMemberButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
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
            scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Metrics.spacing4),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Metrics.spacing4),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing4),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Metrics.spacing4),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * Metrics.spacing4),

            // Footer
            footerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            footerBorderView.topAnchor.constraint(equalTo: footerView.topAnchor),
            footerBorderView.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
            footerBorderView.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
            footerBorderView.heightAnchor.constraint(equalToConstant: 1),

            removeMemberButton.topAnchor.constraint(equalTo: footerBorderView.bottomAnchor, constant: Metrics.spacing4),
            removeMemberButton.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: Metrics.spacing4),
            removeMemberButton.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -Metrics.spacing4),
            removeMemberButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Metrics.spacing4),
        ])
    }

    private func createSectionCard(toggles: [PermissionToggleRow]) -> UIView {
        let card = UIView()
        card.backgroundColor = Colors.gray100
        card.layer.cornerRadius = CornerRadius.large
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        for (index, toggle) in toggles.enumerated() {
            toggle.backgroundColor = .clear
            toggle.layer.cornerRadius = 0
            stack.addArrangedSubview(toggle)

            if index < toggles.count - 1 {
                let separator = UIView()
                separator.backgroundColor = Colors.gray200
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
                stack.addArrangedSubview(separator)
            }
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        return card
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

    // MARK: - Configuration

    func configure(with member: GroupMember) {
        memberAvatarLabel.text = String(member.name.prefix(1)).uppercased()
        memberNameLabel.text = member.name
        memberEmailLabel.text = member.email

        let perms = member.permissions
        canCreateToggle.configure(title: "permission.createTransactions".localized, description: "", isOn: perms.canCreateTransactions)
        canEditToggle.configure(title: "permission.editTransactions".localized, description: "", isOn: perms.canEditTransactions)
        canDeleteToggle.configure(title: "permission.deleteTransactions".localized, description: "", isOn: perms.canDeleteTransactions)
        canEditBudgetsToggle.configure(title: "permission.editBudgets".localized, description: "", isOn: perms.canEditBudgets)
        canEditAllocationsToggle.configure(title: "permission.editAllocations".localized, description: "", isOn: perms.canEditAllocations)
        canViewCardsToggle.configure(title: "permission.viewCreditCards".localized, description: "", isOn: perms.canViewCreditCards)
        canManageCardsToggle.configure(title: "permission.manageCreditCards".localized, description: "", isOn: perms.canManageCreditCards)
        canInviteToggle.configure(title: "permission.inviteMembers".localized, description: "", isOn: perms.canInviteMembers)
    }

    @objc private func backTapped() { delegate?.handleDidTapBackButton() }
    @objc private func removeTapped() { delegate?.didTapRemoveMember() }
}
