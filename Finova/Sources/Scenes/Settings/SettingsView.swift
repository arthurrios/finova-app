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

    let translateTagsContainer = createSettingContainer(growsWithText: true)
    private let translateTagsIconView = createIconView(imageName: "character.book.closed")
    private let translateTagsLabel = createSettingLabel(text: "settings.translateTags.title".localized)
    let translateTagsSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.onTintColor = Colors.mainMagenta
        return toggle
    }()

    /// Hidden until a pass reports a pair the device has not downloaded. Offered here rather than
    /// prompted automatically: the system download sheet belongs to a screen the user chose to be on.
    let downloadLanguagesContainer: UIView = {
        let container = createSettingContainer(growsWithText: true)
        container.isUserInteractionEnabled = true
        container.isHidden = true
        return container
    }()
    private let downloadLanguagesIconView = createIconView(imageName: "arrow.down.circle")
    private let downloadLanguagesLabel = createSettingLabel(
        text: "settings.translateTags.download.title".localized)
    private let downloadLanguagesChevron = createChevronView()

    /// **No value label on this row.** "Download translation languages" is long enough that pairing it
    /// with any right-hand value wraps the title onto two lines at the *default* text size, in a
    /// column where every other row is a single 56pt line. The state lives in the footer instead,
    /// where there is room for a sentence, and the icon carries it at a glance: a grey arrow to
    /// offer, a spinning magenta one in progress, a green check when done, an amber triangle when it
    /// stalled.
    private let translateTagsFooterLabel = createSectionFooter()

    // Sharing Section
    private let sharingHeaderView = createSectionHeader(title: "settings.section.sharing".localized)

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
        setupTranslateTagsContainer()
        contentStackView.addArrangedSubview(translateTagsContainer)
        setupDownloadLanguagesContainer()
        contentStackView.addArrangedSubview(downloadLanguagesContainer)
        contentStackView.addArrangedSubview(translateTagsFooterLabel)

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

    private func setupTranslateTagsContainer() {
        translateTagsLabel.numberOfLines = 0
        translateTagsContainer.addSubview(translateTagsIconView)
        translateTagsContainer.addSubview(translateTagsLabel)
        translateTagsContainer.addSubview(translateTagsSwitch)

        NSLayoutConstraint.activate([
            translateTagsIconView.leadingAnchor.constraint(equalTo: translateTagsContainer.leadingAnchor, constant: Metrics.spacing4),
            translateTagsIconView.centerYAnchor.constraint(equalTo: translateTagsContainer.centerYAnchor),

            translateTagsLabel.leadingAnchor.constraint(equalTo: translateTagsIconView.trailingAnchor, constant: Metrics.spacing3),
            translateTagsLabel.centerYAnchor.constraint(equalTo: translateTagsContainer.centerYAnchor),
            translateTagsLabel.topAnchor.constraint(greaterThanOrEqualTo: translateTagsContainer.topAnchor, constant: Metrics.spacing2),
            translateTagsLabel.trailingAnchor.constraint(lessThanOrEqualTo: translateTagsSwitch.leadingAnchor, constant: -Metrics.spacing2),

            translateTagsSwitch.trailingAnchor.constraint(equalTo: translateTagsContainer.trailingAnchor, constant: -Metrics.spacing4),
            translateTagsSwitch.centerYAnchor.constraint(equalTo: translateTagsContainer.centerYAnchor)
        ])
    }

    private func setupDownloadLanguagesContainer() {
        downloadLanguagesLabel.numberOfLines = 0
        downloadLanguagesContainer.addSubview(downloadLanguagesIconView)
        downloadLanguagesContainer.addSubview(downloadLanguagesLabel)
        downloadLanguagesContainer.addSubview(downloadLanguagesChevron)

        // The whole row reads as one element. Left as three, VoiceOver announces the chevron as an
        // unlabelled image and separates the title from the state it is in.
        downloadLanguagesContainer.isAccessibilityElement = true
        downloadLanguagesContainer.accessibilityTraits = .button

        NSLayoutConstraint.activate([
            downloadLanguagesIconView.leadingAnchor.constraint(equalTo: downloadLanguagesContainer.leadingAnchor, constant: Metrics.spacing4),
            downloadLanguagesIconView.centerYAnchor.constraint(equalTo: downloadLanguagesContainer.centerYAnchor),

            downloadLanguagesLabel.leadingAnchor.constraint(equalTo: downloadLanguagesIconView.trailingAnchor, constant: Metrics.spacing3),
            downloadLanguagesLabel.centerYAnchor.constraint(equalTo: downloadLanguagesContainer.centerYAnchor),
            downloadLanguagesLabel.topAnchor.constraint(greaterThanOrEqualTo: downloadLanguagesContainer.topAnchor, constant: Metrics.spacing2),
            downloadLanguagesLabel.trailingAnchor.constraint(equalTo: downloadLanguagesChevron.leadingAnchor, constant: -Metrics.spacing2),

            downloadLanguagesChevron.trailingAnchor.constraint(equalTo: downloadLanguagesContainer.trailingAnchor, constant: -Metrics.spacing4),
            downloadLanguagesChevron.centerYAnchor.constraint(equalTo: downloadLanguagesContainer.centerYAnchor)
        ])
    }

    // MARK: - Tag translation state

    /// Everything the download row can be. The coordinator decides which one; this view only draws
    /// it. Inferring the state here is how the row previously managed to disappear on a declined
    /// download and never come back.
    enum TranslationDownloadState: Equatable {
        case hidden
        case available(languageName: String)
        case downloading
        case downloaded
        case stalled
    }

    /// The visible translation rows as one rect in this view's coordinate space, so a snapshot test
    /// can crop to them. Nothing in the app uses this.
    var translationGroupFrame: CGRect? {
        let visible = [translateTagsContainer, downloadLanguagesContainer, translateTagsFooterLabel]
            .filter { !$0.isHidden && $0.superview != nil }
        guard let first = visible.first else { return nil }
        return visible.dropFirst().reduce(convert(first.bounds, from: first)) { rect, view in
            rect.union(convert(view.bounds, from: view))
        }
    }

    func setTranslationFooter(_ text: String) {
        translateTagsFooterLabel.text = text
        translateTagsFooterLabel.isHidden = text.isEmpty
    }

    func setTranslationGroupHidden(_ hidden: Bool) {
        translateTagsContainer.isHidden = hidden
        if hidden {
            downloadLanguagesContainer.isHidden = true
            translateTagsFooterLabel.isHidden = true
        }
    }

    func applyDownloadState(_ state: TranslationDownloadState) {
        let wasHidden = downloadLanguagesContainer.isHidden
        downloadLanguagesContainer.isHidden = state == .hidden
        downloadLanguagesIconView.layer.removeAnimation(forKey: "rotationAnimation")

        // Nothing visual says what the state IS except the icon; the words are in the footer. So the
        // accessibility label has to carry it, because an icon's tint is not announced.
        var spokenState: String?

        switch state {
        case .hidden:
            break

        case .available(let languageName):
            downloadLanguagesIconView.image = UIImage(systemName: "arrow.down.circle")
            downloadLanguagesIconView.tintColor = Colors.gray600
            downloadLanguagesChevron.isHidden = false
            downloadLanguagesContainer.isUserInteractionEnabled = true
            downloadLanguagesContainer.accessibilityTraits = .button
            downloadLanguagesContainer.accessibilityHint =
                "settings.translateTags.download.a11y.hint".localized
            spokenState = languageName

        case .downloading:
            downloadLanguagesIconView.image = UIImage(systemName: "arrow.triangle.2.circlepath")
            downloadLanguagesIconView.tintColor = Colors.mainMagenta
            downloadLanguagesChevron.isHidden = true
            // Still tappable. Re-tapping is harmless, and it is the only way back if the user
            // dismissed the system sheet before confirming.
            downloadLanguagesContainer.isUserInteractionEnabled = true
            downloadLanguagesContainer.accessibilityTraits = .button
            downloadLanguagesContainer.accessibilityHint = nil
            spokenState = "settings.translateTags.downloading".localized
            startDownloadIconSpinning()

        case .downloaded:
            downloadLanguagesIconView.image = UIImage(systemName: "checkmark.circle.fill")
            downloadLanguagesIconView.tintColor = Colors.mainGreen
            downloadLanguagesChevron.isHidden = true
            downloadLanguagesContainer.isUserInteractionEnabled = false
            downloadLanguagesContainer.accessibilityTraits = [.button, .notEnabled]
            downloadLanguagesContainer.accessibilityHint = nil
            spokenState = "settings.translateTags.downloaded".localized

        case .stalled:
            downloadLanguagesIconView.image = UIImage(systemName: "exclamationmark.triangle")
            downloadLanguagesIconView.tintColor = Colors.warningAmber
            downloadLanguagesChevron.isHidden = false
            downloadLanguagesContainer.isUserInteractionEnabled = true
            downloadLanguagesContainer.accessibilityTraits = .button
            downloadLanguagesContainer.accessibilityHint =
                "settings.translateTags.download.a11y.hint".localized
            spokenState = "settings.translateTags.retry".localized
        }

        downloadLanguagesContainer.accessibilityLabel = [downloadLanguagesLabel.text, spokenState]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: ", ")

        // The row appearing changes the element count, which VoiceOver has to be told about.
        if wasHidden != downloadLanguagesContainer.isHidden {
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
        }
    }

    private func startDownloadIconSpinning() {
        // The same animation SyncStatusIndicator uses for "in progress", rather than dropping a
        // UIActivityIndicatorView into a Settings row and inventing a second vocabulary for it.
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.toValue = NSNumber(value: Double.pi * 2)
        rotation.duration = 1.5
        rotation.repeatCount = .infinity
        rotation.isCumulative = true
        downloadLanguagesIconView.layer.add(rotation, forKey: "rotationAnimation")
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
        translateTagsSwitch.addTarget(self, action: #selector(translateTagsToggled), for: .valueChanged)

        let downloadTap = UITapGestureRecognizer(target: self, action: #selector(downloadLanguagesTapped))
        downloadLanguagesContainer.addGestureRecognizer(downloadTap)

        let currencyTap = UITapGestureRecognizer(target: self, action: #selector(currencyTapped))
        currencyContainer.addGestureRecognizer(currencyTap)

        let deleteAccountTap = UITapGestureRecognizer(target: self, action: #selector(deleteAccountTapped))
        deleteAccountContainer.addGestureRecognizer(deleteAccountTap)

        let notificationsTap = UITapGestureRecognizer(target: self, action: #selector(notificationsTapped))
        notificationsContainer.addGestureRecognizer(notificationsTap)

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
    private func downloadLanguagesTapped() {
        delegate?.didTapDownloadTranslationLanguages()
    }

    @objc
    private func translateTagsToggled() {
        delegate?.didToggleTagTranslation(translateTagsSwitch.isOn)
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
    
    /// - Parameter growsWithText: pins the height at 56 when false, which is what every existing row
    ///   does. True makes it a minimum instead, so a row whose labels wrap at accessibility text
    ///   sizes can grow rather than clip.
    private static func createSettingContainer(growsWithText: Bool = false) -> UIView {
        let container = UIView()
        container.backgroundColor = Colors.gray100
        container.layer.cornerRadius = CornerRadius.large
        container.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            growsWithText
                ? container.heightAnchor.constraint(greaterThanOrEqualToConstant: 56)
                : container.heightAnchor.constraint(equalToConstant: 56)
        ])

        return container
    }

    /// Explanatory text under a group of rows, the way iOS Settings does it.
    ///
    /// Deliberately not a subtitle inside the row: the copy has to be a sentence or two to set any
    /// real expectation, and a `Fonts.textXS` fragment competing with a 51pt `UISwitch` for the same
    /// edge truncates the moment it says anything useful. A footer has the full width, wraps, and can
    /// speak for more than one row.
    private static func createSectionFooter(text: String = "") -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
