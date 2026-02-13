//
//  InviteMemberView.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class InviteMemberView: UIView {
    weak var delegate: InviteMemberViewDelegate?

    var onPresetChanged: ((Int) -> Void)?

    // MARK: - Modal header
    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleXS
        label.text = "invite.header.title".localized
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

    // MARK: - ScrollView (for form content)
    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // MARK: - Content
    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing7
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing8,
            leading: Metrics.spacing8,
            bottom: Metrics.spacing4,
            trailing: Metrics.spacing8)
        return stack
    }()

    // MARK: - Email Input
    private let emailSectionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray400
        label.text = "invite.email.section".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let emailInput = Input(
        type: .email,
        placeholder: "invite.email.placeholder".localized,
        icon: UIImage(systemName: "envelope"),
        iconPosition: .left
    )

    // MARK: - Permission Presets (UIButton + UIMenu dropdown)
    private let presetSectionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray400
        label.text = "invite.preset.section".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let presetButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "invite.preset.viewOnly".localized
        config.baseForegroundColor = Colors.gray700
        config.background.backgroundColor = Colors.gray200
        config.background.strokeColor = Colors.gray300
        config.background.strokeWidth = 1
        config.background.cornerRadius = CornerRadius.large
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Metrics.spacing4, bottom: 0, trailing: Metrics.spacing4 + Metrics.inputIconSize + Metrics.spacing2)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = Fonts.input.font
            return outgoing
        }
        config.image = UIImage(systemName: "chevron.down")
        config.imagePlacement = .trailing
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: Metrics.inputIconSize * 0.6)
        config.imagePadding = Metrics.spacing2

        let btn = UIButton(configuration: config)
        btn.contentHorizontalAlignment = .leading
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: Metrics.inputHeight).isActive = true
        btn.tintColor = Colors.gray600
        btn.showsMenuAsPrimaryAction = true
        return btn
    }()

    // MARK: - Custom Permissions (hidden by default)
    private let customPermissionsSectionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.text = "invite.custom.section".localized.uppercased()
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let customPermissionsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing2
        stack.isHidden = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let scrollFadeView: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    // MARK: - Footer (separator + button, pinned to bottom)
    private let footerStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing7
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: Metrics.spacing8,
            bottom: Metrics.spacing4,
            trailing: Metrics.spacing8)
        return stack
    }()

    private let separatorView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }()

    let sendButton = Button(variant: .base, label: "invite.send.button".localized)

    private(set) var footerBottomConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray100
        setupView()
        setupLayout()
        setupPresetMenu()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(scrollView)
        scrollView.addSubview(contentStackView)
        addSubview(footerStackView)

        // Header row
        let headerStack = UIStackView(
            axis: .horizontal, alignment: .center,
            arrangedSubviews: [headerTitleLabel, closeIconButton])
        contentStackView.addArrangedSubview(headerStack)

        // Email section
        let emailGroup = UIStackView(axis: .vertical, spacing: Metrics.spacing3,
            arrangedSubviews: [emailSectionLabel, emailInput])
        contentStackView.addArrangedSubview(emailGroup)

        // Preset section
        let presetGroup = UIStackView(axis: .vertical, spacing: Metrics.spacing3,
            arrangedSubviews: [presetSectionLabel, presetButton])
        contentStackView.addArrangedSubview(presetGroup)

        // Custom permissions (collapsible)
        contentStackView.addArrangedSubview(customPermissionsSectionLabel)
        contentStackView.setCustomSpacing(Metrics.spacing3, after: customPermissionsSectionLabel)
        contentStackView.addArrangedSubview(customPermissionsStack)
        setupPermissionToggles()

        // Footer (separator + button)
        footerStackView.addArrangedSubview(separatorView)
        footerStackView.addArrangedSubview(sendButton)

        // Scroll fade indicator
        addSubview(scrollFadeView)
        setupScrollFade()

        closeIconButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        scrollView.delegate = self
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerStackView.topAnchor),

            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            footerStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerStackView.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollFadeView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            scrollFadeView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            scrollFadeView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            scrollFadeView.heightAnchor.constraint(equalToConstant: 32),
        ])

        footerBottomConstraint = footerStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
        footerBottomConstraint.isActive = true
    }

    private func setupScrollFade() {
        let gradient = CAGradientLayer()
        gradient.colors = [
            Colors.gray100.withAlphaComponent(0).cgColor,
            Colors.gray100.cgColor,
        ]
        gradient.locations = [0.0, 1.0]
        scrollFadeView.layer.addSublayer(gradient)
        scrollFadeView.layer.setValue(gradient, forKey: "gradientLayer")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let gradient = scrollFadeView.layer.value(forKey: "gradientLayer") as? CAGradientLayer {
            gradient.frame = scrollFadeView.bounds
        }
    }

    private func updateScrollFadeVisibility() {
        let contentHeight = scrollView.contentSize.height
        let scrollableHeight = scrollView.bounds.height
        let currentOffset = scrollView.contentOffset.y
        let isAtBottom = currentOffset >= contentHeight - scrollableHeight - 8
        scrollFadeView.isHidden = isAtBottom || customPermissionsStack.isHidden
    }

    private func setupPresetMenu() {
        let options: [(String, Int)] = [
            ("invite.preset.viewOnly".localized, 0),
            ("invite.preset.canAdd".localized, 1),
            ("invite.preset.fullAccess".localized, 2),
            ("invite.preset.custom".localized, 3),
        ]

        let actions = options.map { title, index in
            UIAction(title: title, state: index == 0 ? .on : .off) { [weak self] action in
                self?.presetButton.configuration?.title = action.title
                self?.onPresetChanged?(index)
                self?.updateMenuState(selectedIndex: index)
            }
        }

        presetButton.menu = UIMenu(children: actions)
    }

    private func updateMenuState(selectedIndex: Int) {
        guard let menu = presetButton.menu else { return }
        let updatedActions = menu.children.enumerated().map { index, element -> UIAction in
            guard let action = element as? UIAction else { return element as! UIAction }
            action.state = index == selectedIndex ? .on : .off
            return action
        }
        presetButton.menu = UIMenu(children: updatedActions)
    }

    private func setupPermissionToggles() {
        let permissions = GroupPermissions.memberDefault.allPermissions
        for perm in permissions {
            let row = PermissionToggleRow()
            row.configure(
                title: perm.label,
                description: "",
                isOn: perm.isEnabled
            )
            row.accessibilityIdentifier = perm.key
            customPermissionsStack.addArrangedSubview(row)
        }
    }

    func showCustomPermissions(_ show: Bool) {
        UIView.animate(withDuration: 0.3) {
            self.customPermissionsSectionLabel.isHidden = !show
            self.customPermissionsStack.isHidden = !show
            self.customPermissionsSectionLabel.alpha = show ? 1 : 0
            self.customPermissionsStack.alpha = show ? 1 : 0
        } completion: { _ in
            self.scrollView.showsVerticalScrollIndicator = show
            self.updateScrollFadeVisibility()
            if show {
                // Flash scroll indicator briefly to hint at scrollability
                self.scrollView.flashScrollIndicators()
            }
        }
    }

    func updateToggles(with permissions: GroupPermissions) {
        let allPerms = permissions.allPermissions
        for (index, perm) in allPerms.enumerated() {
            guard index < customPermissionsStack.arrangedSubviews.count,
                  let row = customPermissionsStack.arrangedSubviews[index] as? PermissionToggleRow else { continue }
            row.configure(title: perm.label, description: "", isOn: perm.isEnabled)
        }
    }

    @objc private func closeTapped() { delegate?.didTapClose() }
    @objc private func sendTapped() { delegate?.didTapSendInvitation() }
}

// MARK: - UIScrollViewDelegate
extension InviteMemberView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateScrollFadeVisibility()
    }
}
