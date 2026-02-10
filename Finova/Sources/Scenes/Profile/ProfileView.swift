//
//  ProfileView.swift
//  Finova
//
//  Created by Arthur Rios on 10/02/26.
//

import UIKit

final class ProfileView: UIView {
    weak var delegate: ProfileViewDelegate?

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
        label.text = "profile.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - ScrollView

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - User Info Section

    private let userInfoContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let largeAvatar: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.layer.borderWidth = 1
        view.layer.borderColor = Colors.gray700.cgColor
        view.layer.masksToBounds = true
        view.isUserInteractionEnabled = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    let avatarIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFit
        imageView.image = UIImage(named: "user")
        imageView.tintColor = Colors.gray500
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let editBadge: UIView = {
        let badge = UIView()
        badge.backgroundColor = Colors.mainMagenta
        badge.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView()
        iconView.image = UIImage(named: "edit")?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        badge.addSubview(iconView)

        let badgeSize: CGFloat = 24
        let iconSize: CGFloat = 12

        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: badgeSize),
            badge.heightAnchor.constraint(equalToConstant: badgeSize),
            iconView.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize)
        ])

        badge.layer.cornerRadius = badgeSize / 2
        badge.clipsToBounds = true

        return badge
    }()

    let nameLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray700
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let emailLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Financial Section

    private let financialHeaderView = createSectionHeader(title: "profile.section.financial".localized)

    private let creditCardsContainer: UIView = {
        let container = createSettingContainer()
        container.isUserInteractionEnabled = true
        return container
    }()
    private let creditCardsIconView = createIconView(imageName: "creditcard")
    private let creditCardsLabel = createSettingLabel(text: "profile.creditCards.title".localized)
    private let creditCardsChevron = createChevronView()

    // MARK: - General Section

    private let generalHeaderView = createSectionHeader(title: "profile.section.general".localized)

    private let settingsContainer: UIView = {
        let container = createSettingContainer()
        container.isUserInteractionEnabled = true
        return container
    }()
    private let settingsIconView = createIconView(imageName: "gearshape")
    private let settingsLabel = createSettingLabel(text: "profile.settings.title".localized)
    private let settingsChevron = createChevronView()

    // MARK: - Account Section

    private let accountHeaderView = createSectionHeader(title: "profile.section.account".localized)

    private let logoutContainer: UIView = {
        let container = createSettingContainer()
        container.isUserInteractionEnabled = true
        return container
    }()

    private let logoutIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "logout")
        imageView.tintColor = Colors.mainRed
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: 20),
            imageView.widthAnchor.constraint(equalToConstant: 20)
        ])

        return imageView
    }()

    private let logoutLabel: UILabel = {
        let label = createSettingLabel(text: "profile.logout.title".localized)
        label.textColor = Colors.mainRed
        return label
    }()

    // MARK: - Version Footer

    let versionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray400
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: .zero)
        setupView()
        setupActions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = Colors.gray200

        backButton.addTarget(self, action: #selector(handleDidTapBackButton), for: .touchUpInside)

        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        addSubview(scrollView)
        scrollView.addSubview(contentStackView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        setupBackButtonGlassEffect()
        headerItemsView.addSubview(headerTitleLabel)

        setupSections()
        setupConstraints()
    }

    private func setupSections() {
        // User info section
        setupUserInfoContainer()
        contentStackView.addArrangedSubview(userInfoContainer)

        // Financial section
        contentStackView.addArrangedSubview(financialHeaderView)
        setupCreditCardsContainer()
        contentStackView.addArrangedSubview(creditCardsContainer)

        // General section
        contentStackView.addArrangedSubview(generalHeaderView)
        setupSettingsContainer()
        contentStackView.addArrangedSubview(settingsContainer)

        // Account section
        contentStackView.addArrangedSubview(accountHeaderView)
        setupLogoutContainer()
        contentStackView.addArrangedSubview(logoutContainer)

        // Version footer
        let versionContainer = UIView()
        versionContainer.translatesAutoresizingMaskIntoConstraints = false
        versionContainer.addSubview(versionLabel)
        NSLayoutConstraint.activate([
            versionLabel.centerXAnchor.constraint(equalTo: versionContainer.centerXAnchor),
            versionLabel.topAnchor.constraint(equalTo: versionContainer.topAnchor, constant: Metrics.spacing4),
            versionLabel.bottomAnchor.constraint(equalTo: versionContainer.bottomAnchor, constant: -Metrics.spacing4)
        ])
        contentStackView.addArrangedSubview(versionContainer)
    }

    private func setupUserInfoContainer() {
        userInfoContainer.addSubview(largeAvatar)
        largeAvatar.addSubview(avatarImageView)
        largeAvatar.addSubview(avatarIconView)
        userInfoContainer.addSubview(editBadge)
        userInfoContainer.addSubview(nameLabel)
        userInfoContainer.addSubview(emailLabel)

        NSLayoutConstraint.activate([
            userInfoContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),

            largeAvatar.topAnchor.constraint(equalTo: userInfoContainer.topAnchor, constant: Metrics.spacing5),
            largeAvatar.centerXAnchor.constraint(equalTo: userInfoContainer.centerXAnchor),
            largeAvatar.widthAnchor.constraint(equalToConstant: Metrics.profileLargeImageSize),
            largeAvatar.heightAnchor.constraint(equalToConstant: Metrics.profileLargeImageSize),

            avatarImageView.topAnchor.constraint(equalTo: largeAvatar.topAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: largeAvatar.bottomAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: largeAvatar.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: largeAvatar.trailingAnchor),

            avatarIconView.centerXAnchor.constraint(equalTo: largeAvatar.centerXAnchor),
            avatarIconView.centerYAnchor.constraint(equalTo: largeAvatar.centerYAnchor),
            avatarIconView.widthAnchor.constraint(equalToConstant: Metrics.profileLargeIconSize),
            avatarIconView.heightAnchor.constraint(equalToConstant: Metrics.profileLargeIconSize),

            editBadge.bottomAnchor.constraint(equalTo: largeAvatar.bottomAnchor, constant: 2),
            editBadge.trailingAnchor.constraint(equalTo: largeAvatar.trailingAnchor, constant: 2),

            nameLabel.topAnchor.constraint(equalTo: largeAvatar.bottomAnchor, constant: Metrics.spacing3),
            nameLabel.centerXAnchor.constraint(equalTo: userInfoContainer.centerXAnchor),
            nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: userInfoContainer.leadingAnchor, constant: Metrics.spacing5),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: userInfoContainer.trailingAnchor, constant: -Metrics.spacing5),

            emailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Metrics.spacing1),
            emailLabel.centerXAnchor.constraint(equalTo: userInfoContainer.centerXAnchor),
            emailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: userInfoContainer.leadingAnchor, constant: Metrics.spacing5),
            emailLabel.trailingAnchor.constraint(lessThanOrEqualTo: userInfoContainer.trailingAnchor, constant: -Metrics.spacing5),
            emailLabel.bottomAnchor.constraint(equalTo: userInfoContainer.bottomAnchor, constant: -Metrics.spacing5)
        ])
    }

    private func setupCreditCardsContainer() {
        creditCardsContainer.addSubview(creditCardsIconView)
        creditCardsContainer.addSubview(creditCardsLabel)
        creditCardsContainer.addSubview(creditCardsChevron)

        NSLayoutConstraint.activate([
            creditCardsIconView.leadingAnchor.constraint(equalTo: creditCardsContainer.leadingAnchor, constant: Metrics.spacing4),
            creditCardsIconView.centerYAnchor.constraint(equalTo: creditCardsContainer.centerYAnchor),

            creditCardsLabel.leadingAnchor.constraint(equalTo: creditCardsIconView.trailingAnchor, constant: Metrics.spacing3),
            creditCardsLabel.centerYAnchor.constraint(equalTo: creditCardsContainer.centerYAnchor),

            creditCardsChevron.trailingAnchor.constraint(equalTo: creditCardsContainer.trailingAnchor, constant: -Metrics.spacing4),
            creditCardsChevron.centerYAnchor.constraint(equalTo: creditCardsContainer.centerYAnchor)
        ])
    }

    private func setupSettingsContainer() {
        settingsContainer.addSubview(settingsIconView)
        settingsContainer.addSubview(settingsLabel)
        settingsContainer.addSubview(settingsChevron)

        NSLayoutConstraint.activate([
            settingsIconView.leadingAnchor.constraint(equalTo: settingsContainer.leadingAnchor, constant: Metrics.spacing4),
            settingsIconView.centerYAnchor.constraint(equalTo: settingsContainer.centerYAnchor),

            settingsLabel.leadingAnchor.constraint(equalTo: settingsIconView.trailingAnchor, constant: Metrics.spacing3),
            settingsLabel.centerYAnchor.constraint(equalTo: settingsContainer.centerYAnchor),

            settingsChevron.trailingAnchor.constraint(equalTo: settingsContainer.trailingAnchor, constant: -Metrics.spacing4),
            settingsChevron.centerYAnchor.constraint(equalTo: settingsContainer.centerYAnchor)
        ])
    }

    private func setupLogoutContainer() {
        logoutContainer.addSubview(logoutIconView)
        logoutContainer.addSubview(logoutLabel)

        NSLayoutConstraint.activate([
            logoutIconView.leadingAnchor.constraint(equalTo: logoutContainer.leadingAnchor, constant: Metrics.spacing4),
            logoutIconView.centerYAnchor.constraint(equalTo: logoutContainer.centerYAnchor),

            logoutLabel.leadingAnchor.constraint(equalTo: logoutIconView.trailingAnchor, constant: Metrics.spacing3),
            logoutLabel.centerYAnchor.constraint(equalTo: logoutContainer.centerYAnchor)
        ])
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

            backButtonGlassContainer.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
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

            scrollView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Metrics.spacing4),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Metrics.spacing4),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing4),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Metrics.spacing4),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * Metrics.spacing4)
        ])
    }

    private func setupBackButtonGlassEffect() {
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .clear)
            glassEffect.isInteractive = true
            let glassView = UIVisualEffectView(effect: glassEffect)
            glassView.translatesAutoresizingMaskIntoConstraints = false

            backButtonGlassContainer.insertSubview(glassView, at: 0)
            backButtonGlassContainer.layer.cornerRadius = 18
            backButtonGlassContainer.clipsToBounds = true

            NSLayoutConstraint.activate([
                glassView.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
                glassView.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
                glassView.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),
            ])
        }
    }

    // MARK: - Actions

    private func setupActions() {
        let avatarTap = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
        largeAvatar.addGestureRecognizer(avatarTap)

        let editBadgeTap = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
        editBadge.addGestureRecognizer(editBadgeTap)

        let creditCardsTap = UITapGestureRecognizer(target: self, action: #selector(creditCardsTapped))
        creditCardsContainer.addGestureRecognizer(creditCardsTap)

        let settingsTap = UITapGestureRecognizer(target: self, action: #selector(settingsTapped))
        settingsContainer.addGestureRecognizer(settingsTap)

        let logoutTap = UITapGestureRecognizer(target: self, action: #selector(logoutTapped))
        logoutContainer.addGestureRecognizer(logoutTap)
    }

    @objc private func handleDidTapBackButton() {
        delegate?.handleDidTapBackButton()
    }

    @objc private func avatarTapped() {
        delegate?.didTapAvatar()
    }

    @objc private func creditCardsTapped() {
        delegate?.didTapCreditCards()
    }

    @objc private func settingsTapped() {
        delegate?.didTapSettings()
    }

    @objc private func logoutTapped() {
        delegate?.didTapLogout()
    }

    // MARK: - Public

    func updateAvatar(image: UIImage?) {
        if let image = image {
            avatarImageView.image = image
            avatarImageView.isHidden = false
            avatarIconView.isHidden = true
        } else {
            avatarImageView.isHidden = true
            avatarIconView.isHidden = false
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        largeAvatar.layer.cornerRadius = Metrics.profileLargeImageSize / 2
    }
}

// MARK: - Factory Methods
extension ProfileView {

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
            container.heightAnchor.constraint(equalToConstant: 24)
        ])

        return container
    }

    private static func createSettingContainer() -> UIView {
        let container = UIView()
        container.backgroundColor = Colors.gray100
        container.layer.cornerRadius = CornerRadius.large
        container.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 56)
        ])

        return container
    }

    private static func createIconView(imageName: String, tintColor: UIColor = Colors.gray600) -> UIImageView {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: imageName)
        imageView.tintColor = tintColor
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: 20),
            imageView.widthAnchor.constraint(equalToConstant: 20)
        ])

        return imageView
    }

    private static func createSettingLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Fonts.titleSM.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func createChevronView() -> UIImageView {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "chevron.right")
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.gray400
        imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: 12),
            imageView.widthAnchor.constraint(equalToConstant: 12)
        ])

        return imageView
    }
}
