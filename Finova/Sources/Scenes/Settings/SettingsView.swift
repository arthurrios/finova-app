//
//  SettingsView.swift
//  Finova
//
//  Created by Arthur Rios on 17/07/25.
//

import UIKit

final class SettingsView: UIView {
    weak var delegate: SettingsViewDelegate?
    
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
        label.text = "settings.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Security Section
    private let securityHeaderView = createSectionHeader(title: "settings.section.security".localized)

    let biometricContainer = createSettingContainer()
    private let biometricIconView = createIconView(imageName: "faceid")
    let biometricLabel = createSettingLabel(text: "Face ID / Touch ID")
    let biometricSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.onTintColor = Colors.mainMagenta
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }()

    // Preferences Section
    private let preferencesHeaderView = createSectionHeader(title: "settings.section.preferences".localized)

    private let currencyContainer: UIView = {
        let container = createSettingContainer()
        container.isUserInteractionEnabled = true
        return container
    }()
    private let currencyIconView = createIconView(imageName: "dollarsign.circle")
    private let currencyLabel = createSettingLabel(text: "settings.currency.title".localized)
    let currencyValueLabel = createDetailLabel(text: "")
    private let currencyChevron = createChevronView()

    // Sharing Section
    private let sharingHeaderView = createSectionHeader(title: "settings.section.sharing".localized)

    private let syncSettingsContainer: UIView = {
        let container = createSettingContainer()
        container.isUserInteractionEnabled = true
        return container
    }()
    private let syncSettingsIconView = createIconView(imageName: "icloud")
    private let syncSettingsLabel = createSettingLabel(text: "settings.sync.title".localized)
    let syncStatusDetailLabel = createDetailLabel(text: "")
    private let syncSettingsChevron = createChevronView()

    // Notifications Section
    private let notificationsHeaderView = createSectionHeader(title: "settings.section.notifications".localized)

    private let notificationsContainer: UIView = {
        let container = createSettingContainer()
        container.isUserInteractionEnabled = true
        return container
    }()
    private let notificationsIconView = createIconView(imageName: "bell")
    private let notificationsLabel = createSettingLabel(text: "settings.notifications.title".localized)
    private let notificationsChevron = createChevronView()

    // About Section
    private let aboutHeaderView = createSectionHeader(title: "settings.section.about".localized)
    
    private let versionContainer = createSettingContainer()
    private let versionIconView = createIconView(imageName: "info.circle")
    private let versionTitleLabel = createSettingLabel(text: "settings.version.title".localized)
    let versionLabel = createDetailLabel(text: "")
    
    override init(frame: CGRect) {
        super.init(frame: .zero)
        setupView()
        setupActions()
    }
    
    // Account Section
    private let accountHeaderView = createSectionHeader(title: "settings.section.account".localized)
    
    private let deleteAccountContainer: UIView = {
        let container = createSettingContainer()
        container.isUserInteractionEnabled = true
        return container
    }()
    
    private let deleteAccountIconView = createIconView(imageName: "trash", tintColor: Colors.mainRed)
    private let deleteAccountLabel: UILabel = {
        let label = createSettingLabel(text: "settings.delete.account.title".localized)
        label.textColor = Colors.mainRed
        return label
    }()

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
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
        // Security section
        contentStackView.addArrangedSubview(securityHeaderView)
        setupBiometricContainer()
        contentStackView.addArrangedSubview(biometricContainer)

        // Preferences section
        contentStackView.addArrangedSubview(preferencesHeaderView)
        setupCurrencyContainer()
        contentStackView.addArrangedSubview(currencyContainer)

        // Sharing section
        contentStackView.addArrangedSubview(sharingHeaderView)
        setupSyncSettingsContainer()
        contentStackView.addArrangedSubview(syncSettingsContainer)

        // Notifications section
        contentStackView.addArrangedSubview(notificationsHeaderView)
        setupNotificationsContainer()
        contentStackView.addArrangedSubview(notificationsContainer)

        // About section
        contentStackView.addArrangedSubview(aboutHeaderView)
        setupVersionContainer()
        contentStackView.addArrangedSubview(versionContainer)

        // Account Section
        contentStackView.addArrangedSubview(accountHeaderView)
        setupDeleteAccountContainer()
        contentStackView.addArrangedSubview(deleteAccountContainer)
    }
    
    private func setupBiometricContainer() {
        biometricContainer.addSubview(biometricIconView)
        biometricContainer.addSubview(biometricLabel)
        biometricContainer.addSubview(biometricSwitch)

        NSLayoutConstraint.activate([
            biometricIconView.leadingAnchor.constraint(equalTo: biometricContainer.leadingAnchor, constant: Metrics.spacing4),
            biometricIconView.centerYAnchor.constraint(equalTo: biometricContainer.centerYAnchor),

            biometricLabel.leadingAnchor.constraint(equalTo: biometricIconView.trailingAnchor, constant: Metrics.spacing3),
            biometricLabel.centerYAnchor.constraint(equalTo: biometricContainer.centerYAnchor),

            biometricSwitch.trailingAnchor.constraint(equalTo: biometricContainer.trailingAnchor, constant: -Metrics.spacing4),
            biometricSwitch.centerYAnchor.constraint(equalTo: biometricContainer.centerYAnchor)
        ])
    }

    private func setupCurrencyContainer() {
        currencyContainer.addSubview(currencyIconView)
        currencyContainer.addSubview(currencyLabel)
        currencyContainer.addSubview(currencyValueLabel)
        currencyContainer.addSubview(currencyChevron)

        NSLayoutConstraint.activate([
            currencyIconView.leadingAnchor.constraint(equalTo: currencyContainer.leadingAnchor, constant: Metrics.spacing4),
            currencyIconView.centerYAnchor.constraint(equalTo: currencyContainer.centerYAnchor),

            currencyLabel.leadingAnchor.constraint(equalTo: currencyIconView.trailingAnchor, constant: Metrics.spacing3),
            currencyLabel.centerYAnchor.constraint(equalTo: currencyContainer.centerYAnchor),

            currencyChevron.trailingAnchor.constraint(equalTo: currencyContainer.trailingAnchor, constant: -Metrics.spacing4),
            currencyChevron.centerYAnchor.constraint(equalTo: currencyContainer.centerYAnchor),

            currencyValueLabel.trailingAnchor.constraint(equalTo: currencyChevron.leadingAnchor, constant: -Metrics.spacing2),
            currencyValueLabel.centerYAnchor.constraint(equalTo: currencyContainer.centerYAnchor)
        ])
    }

    private func setupSyncSettingsContainer() {
        syncSettingsContainer.addSubview(syncSettingsIconView)
        syncSettingsContainer.addSubview(syncSettingsLabel)
        syncSettingsContainer.addSubview(syncStatusDetailLabel)
        syncSettingsContainer.addSubview(syncSettingsChevron)

        NSLayoutConstraint.activate([
            syncSettingsIconView.leadingAnchor.constraint(equalTo: syncSettingsContainer.leadingAnchor, constant: Metrics.spacing4),
            syncSettingsIconView.centerYAnchor.constraint(equalTo: syncSettingsContainer.centerYAnchor),

            syncSettingsLabel.leadingAnchor.constraint(equalTo: syncSettingsIconView.trailingAnchor, constant: Metrics.spacing3),
            syncSettingsLabel.centerYAnchor.constraint(equalTo: syncSettingsContainer.centerYAnchor),

            syncSettingsChevron.trailingAnchor.constraint(equalTo: syncSettingsContainer.trailingAnchor, constant: -Metrics.spacing4),
            syncSettingsChevron.centerYAnchor.constraint(equalTo: syncSettingsContainer.centerYAnchor),

            syncStatusDetailLabel.trailingAnchor.constraint(equalTo: syncSettingsChevron.leadingAnchor, constant: -Metrics.spacing2),
            syncStatusDetailLabel.centerYAnchor.constraint(equalTo: syncSettingsContainer.centerYAnchor)
        ])
    }

    private func setupNotificationsContainer() {
        notificationsContainer.addSubview(notificationsIconView)
        notificationsContainer.addSubview(notificationsLabel)
        notificationsContainer.addSubview(notificationsChevron)

        NSLayoutConstraint.activate([
            notificationsIconView.leadingAnchor.constraint(equalTo: notificationsContainer.leadingAnchor, constant: Metrics.spacing4),
            notificationsIconView.centerYAnchor.constraint(equalTo: notificationsContainer.centerYAnchor),

            notificationsLabel.leadingAnchor.constraint(equalTo: notificationsIconView.trailingAnchor, constant: Metrics.spacing3),
            notificationsLabel.centerYAnchor.constraint(equalTo: notificationsContainer.centerYAnchor),

            notificationsChevron.trailingAnchor.constraint(equalTo: notificationsContainer.trailingAnchor, constant: -Metrics.spacing4),
            notificationsChevron.centerYAnchor.constraint(equalTo: notificationsContainer.centerYAnchor)
        ])
    }
    
    private func setupVersionContainer() {
        versionContainer.addSubview(versionIconView)
        versionContainer.addSubview(versionTitleLabel)
        versionContainer.addSubview(versionLabel)
        
        NSLayoutConstraint.activate([
            versionIconView.leadingAnchor.constraint(equalTo: versionContainer.leadingAnchor, constant: Metrics.spacing4),
            versionIconView.centerYAnchor.constraint(equalTo: versionContainer.centerYAnchor),
            
            versionTitleLabel.leadingAnchor.constraint(equalTo: versionIconView.trailingAnchor, constant: Metrics.spacing3),
            versionTitleLabel.centerYAnchor.constraint(equalTo: versionContainer.centerYAnchor),
            
            versionLabel.trailingAnchor.constraint(equalTo: versionContainer.trailingAnchor, constant: -Metrics.spacing4),
            versionLabel.centerYAnchor.constraint(equalTo: versionContainer.centerYAnchor)
        ])
    }
    
    private func setupDeleteAccountContainer() {
        deleteAccountContainer.addSubview(deleteAccountIconView)
        deleteAccountContainer.addSubview(deleteAccountLabel)

        NSLayoutConstraint.activate([
            deleteAccountIconView.leadingAnchor.constraint(equalTo: deleteAccountContainer.leadingAnchor, constant: Metrics.spacing4),
            deleteAccountIconView.centerYAnchor.constraint(equalTo: deleteAccountContainer.centerYAnchor),

            deleteAccountLabel.leadingAnchor.constraint(equalTo: deleteAccountIconView.trailingAnchor, constant: Metrics.spacing3),
            deleteAccountLabel.centerYAnchor.constraint(equalTo: deleteAccountContainer.centerYAnchor)
        ])
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Header fixed at top
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

            // Scroll view fills area below header
            scrollView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Content stack defines scroll content size
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

    private func setupActions() {
        biometricSwitch.addTarget(self, action: #selector(biometricToggled), for: .valueChanged)

        let currencyTap = UITapGestureRecognizer(target: self, action: #selector(currencyTapped))
        currencyContainer.addGestureRecognizer(currencyTap)

        let deleteAccountTap = UITapGestureRecognizer(target: self, action: #selector(deleteAccountTapped))
        deleteAccountContainer.addGestureRecognizer(deleteAccountTap)

        let notificationsTap = UITapGestureRecognizer(target: self, action: #selector(notificationsTapped))
        notificationsContainer.addGestureRecognizer(notificationsTap)

        let syncSettingsTap = UITapGestureRecognizer(target: self, action: #selector(syncSettingsTapped))
        syncSettingsContainer.addGestureRecognizer(syncSettingsTap)
    }

    @objc
    private func biometricToggled() {
        delegate?.didToggleBiometric(biometricSwitch.isOn)
    }

    @objc
    private func currencyTapped() {
        delegate?.didTapCurrency()
    }

    @objc
    private func deleteAccountTapped() {
        delegate?.didTapDeleteAccount()
    }

    @objc
    private func notificationsTapped() {
        delegate?.didTapNotifications()
    }

    @objc
    private func handleDidTapBackButton() {
        delegate?.handleDidTapBackButton()
    }

    @objc
    private func syncSettingsTapped() {
        delegate?.didTapSyncSettings()
    }
}


// MARK: - Factory Methods
extension SettingsView {
    
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
    
    private static func createDetailLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.textAlignment = .right
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
