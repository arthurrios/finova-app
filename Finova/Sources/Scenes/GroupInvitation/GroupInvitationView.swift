//
//  GroupInvitationView.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class GroupInvitationView: UIView {
    weak var delegate: GroupInvitationViewDelegate?

    // MARK: - Modal header
    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleXS
        label.text = "invitation.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let closeIconButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "xmark"), for: .normal)
        btn.tintColor = Colors.gray500
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    // MARK: - Invitation Card
    private let invitationCardHeader = CardHeader(
        headerTitle: "invitation.card.header".localized)

    private lazy var invitationCardContent: UIStackView = {
        let stack = UIStackView(
            axis: .vertical, spacing: Metrics.spacing5,
            arrangedSubviews: [groupInfoStack, separatorLine, permissionsSummaryStack])
        stack.layoutMargins = UIEdgeInsets(
            top: Metrics.spacing5, left: Metrics.spacing5,
            bottom: Metrics.spacing5, right: Metrics.spacing5)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.backgroundColor = Colors.gray100
        stack.layer.borderWidth = 1
        stack.layer.borderColor = Colors.gray300.cgColor
        stack.layer.cornerRadius = CornerRadius.extraLarge
        stack.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        stack.clipsToBounds = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // Group info section
    private let groupIconView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "person.3.fill")
        iv.tintColor = Colors.mainMagenta
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let groupNameLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let inviterLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var groupInfoStack: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(groupIconView)
        let textStack = UIStackView(axis: .vertical, spacing: 2,
            arrangedSubviews: [groupNameLabel, inviterLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textStack)

        NSLayoutConstraint.activate([
            groupIconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            groupIconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            groupIconView.widthAnchor.constraint(equalToConstant: 32),
            groupIconView.heightAnchor.constraint(equalToConstant: 32),

            textStack.leadingAnchor.constraint(equalTo: groupIconView.trailingAnchor, constant: Metrics.spacing3),
            textStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),

            container.heightAnchor.constraint(equalToConstant: 48),
        ])
        return container
    }()

    private let separatorLine: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }()

    // Permissions summary
    private let permissionsTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.text = "invitation.permissions.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let permissionsListLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var permissionsSummaryStack: UIStackView = {
        return UIStackView(axis: .vertical, spacing: Metrics.spacing3,
            arrangedSubviews: [permissionsTitleLabel, permissionsListLabel])
    }()

    // MARK: - Action Buttons
    let acceptButton = Button(variant: .base, label: "invitation.accept.button".localized)

    private let declineButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("invitation.decline.button".localized, for: .normal)
        btn.titleLabel?.font = Fonts.buttonSM.font
        btn.setTitleColor(Colors.gray500, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight).isActive = true
        return btn
    }()

    // MARK: - Content Stack
    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing7
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing10,
            leading: Metrics.spacing8,
            bottom: Metrics.spacing4,
            trailing: Metrics.spacing8)
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray100
        setupView()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(contentStackView)

        // Header row
        let headerStack = UIStackView(arrangedSubviews: [headerTitleLabel, UIView(), closeIconButton])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        closeIconButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        closeIconButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        contentStackView.addArrangedSubview(headerStack)

        // Invitation card
        contentStackView.addArrangedSubview(invitationCardHeader)
        contentStackView.addArrangedSubview(invitationCardContent)
        contentStackView.setCustomSpacing(0, after: invitationCardHeader)

        // Buttons
        let buttonStack = UIStackView(axis: .vertical, spacing: Metrics.spacing3,
            arrangedSubviews: [acceptButton, declineButton])
        contentStackView.addArrangedSubview(buttonStack)

        closeIconButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        acceptButton.addTarget(self, action: #selector(acceptTapped), for: .touchUpInside)
        declineButton.addTarget(self, action: #selector(declineTapped), for: .touchUpInside)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    // MARK: - Configuration

    func configure(with invitation: GroupInvitation, permissions: GroupPermissions) {
        groupNameLabel.text = invitation.groupName
        inviterLabel.text = String(format: "invitation.invitedBy".localized, invitation.inviterName)

        let enabledPerms = permissions.allPermissions
            .filter { $0.isEnabled }
            .map { "\u{2022} \($0.label)" }
            .joined(separator: "\n")
        permissionsListLabel.text = enabledPerms.isEmpty
            ? "invitation.permissions.viewOnly".localized
            : enabledPerms
    }

    @objc private func acceptTapped() { delegate?.didTapAccept() }
    @objc private func declineTapped() { delegate?.didTapDecline() }
    @objc private func closeTapped() { delegate?.didTapClose() }
}
