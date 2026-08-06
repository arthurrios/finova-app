//
//  SettingsViewController.swift
//  Finova
//
//  Created by Arthur Rios on 17/07/25.
//

import UIKit

final class SettingsViewController: UIViewController {
    let contentView: SettingsView
    private let viewModel: SettingsViewModel
    weak var flowDelegate: SettingsFlowDelegate?
    /// What the download row is currently showing. Needed only to notice the transition into "done",
    /// which is otherwise indistinguishable from "there was never anything to download".
    private var lastDownloadState: SettingsView.TranslationDownloadState = .hidden
    
    init(contentView: SettingsView, viewModel: SettingsViewModel, flowDelegate: SettingsFlowDelegate) {
        self.contentView = contentView
        self.viewModel = viewModel
        self.flowDelegate = flowDelegate
        super.init(nibName: nil, bundle: nil)
        
        self.viewModel.delegate = self
        self.viewModel.refreshAllSettings()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleTranslationDownloadStateChanged),
            name: .tagTranslationDownloadStateChanged, object: nil)
        setup()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh all settings when returning to settings
        viewModel.refreshAllSettings()
    }
    
    private func setup() {
        view.addSubview(contentView)
        buildHierarchy()
        setupDelegates()
    }
    
    private func setupDelegates() {
        contentView.delegate = self
    }
    
    private func buildHierarchy() {
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
    }
}

extension SettingsViewController: SettingsViewDelegate {
    func didTapDeleteAccount() {
        showDeleteAccountConfirmation()
    }

    func didToggleBiometric(_ isEnabled: Bool) {
        viewModel.toggleBiometric(isEnabled)
    }

    func didTapCurrency() {
        showCurrencyPicker()
    }

    /// Redraws the download row when the watch reports the language has landed, so the user sees it
    /// finish without having to navigate away and back.
    @objc private func handleTranslationDownloadStateChanged() {
        refreshDownloadLanguagesRow()
    }

    func didTapDownloadTranslationLanguages() {
        let coordinator = AllocationTagTranslationCoordinator.shared
        // Re-tappable if a download was dismissed: the only way back from a cancelled system sheet is
        // to ask for it again, so this must never latch permanently.
        guard !coordinator.isDownloadingLanguages else { return }  // sheet already up

        // Set before awaiting, so the row responds to the tap rather than to the sheet closing.
        applyDownloadState(.downloading)
        announce("settings.translateTags.download.a11y.started".localized)
        // `self` is the presenter: Apple's sheet belongs to the screen the user tapped on, and
        // handing it over beats the old approach of walking the window to guess one.
        coordinator.downloadMissingLanguages(from: self) { [weak self] in
            self?.refreshDownloadLanguagesRow()
        }
    }

    /// Renders the row from the coordinator's state rather than from whatever this screen last set,
    /// so leaving and returning mid-download shows the truth instead of a stale "Downloading…".
    private func refreshDownloadLanguagesRow() {
        let coordinator = AllocationTagTranslationCoordinator.shared
        guard viewModel.isTagTranslationSupported,
            UserDefaultsManager.isTagNameTranslationEnabled()
        else {
            applyDownloadState(.hidden)
            return
        }

        if coordinator.isDownloadingLanguages || coordinator.hasDownloadInProgress {
            applyDownloadState(.downloading)
        } else if coordinator.hasLanguagesToDownload {
            applyDownloadState(.available(languageName: Self.targetLanguageName))
        } else if lastDownloadState == .downloading {
            // It was downloading a moment ago and now there is nothing pending, so it landed. Held
            // briefly rather than just vanishing — otherwise the row disappears and the user never
            // learns it worked.
            applyDownloadState(.downloaded)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard self?.lastDownloadState == .downloaded else { return }
                self?.refreshDownloadLanguagesRow()
            }
            announce("settings.translateTags.download.a11y.finished".localized)
        } else {
            applyDownloadState(.hidden)
        }
    }

    private func applyDownloadState(_ state: SettingsView.TranslationDownloadState) {
        lastDownloadState = state
        contentView.applyDownloadState(state)
        contentView.setTranslationFooter(Self.footerText(for: state))
    }

    /// The footer carries every word of the row's state, since the row itself is only an icon, a
    /// title and a chevron.
    private static func footerText(for state: SettingsView.TranslationDownloadState) -> String {
        let base = "settings.translateTags.footer".localized
        switch state {
        case .available(let languageName):
            // The language and the data-cost warning only earn their place while there is actually
            // something to download; the rest of the time they are a caveat about nothing.
            return base + "\n"
                + String(
                    format: "settings.translateTags.download.footer".localized, languageName)
        case .downloading:
            return "settings.translateTags.footer.downloading".localized
        case .downloaded:
            return "settings.translateTags.footer.downloaded".localized
        case .stalled:
            return "settings.translateTags.footer.failed".localized
        case .hidden:
            return base
        }
    }

    /// The one language a download could ever be for: the phone's own.
    private static var targetLanguageName: String {
        let language = Locale.current.language.minimalIdentifier
        return Locale.current.localizedString(forIdentifier: language)
            ?? Locale.current.localizedString(forLanguageCode: language)
            ?? language
    }

    /// `.announcement` rather than `.layoutChanged`: a download lands minutes later, and yanking
    /// VoiceOver focus back to a Settings row at that point would be hostile.
    private func announce(_ message: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    func didToggleTagTranslation(_ isEnabled: Bool) {
        UserDefaultsManager.setTagNameTranslationEnabled(isEnabled)
        // Re-render immediately: turning it off must drop back to the typed names at once, not on the
        // next tag edit.
        NotificationCenter.default.post(name: .allocationTagsChanged, object: nil)
        AllocationTagTranslationCoordinator.shared.reconcile()
        refreshDownloadLanguagesRow()
    }

    func didTapNotifications() {
        flowDelegate?.navigateToNotificationSettings()
    }

    func handleDidTapBackButton() {
        self.flowDelegate?.dismissSettings()
    }
}

extension SettingsViewController: SettingsViewModelDelegate {
    func didUpdateBiometricUI(isEnabled: Bool, biometricType: String) {
        contentView.biometricSwitch.isOn = isEnabled
        contentView.biometricLabel.text = biometricType
    }

    func didRequestOpenSettings(title: String, message: String) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )

        let openSettingsAction = UIAlertAction(
            title: "settings.biometric.openSettings".localized,
            style: .default
        ) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }

        let cancelAction = UIAlertAction(
            title: "alert.cancel".localized,
            style: .cancel
        )

        alert.addAction(openSettingsAction)
        alert.addAction(cancelAction)

        present(alert, animated: true)
    }

    func didUpdateAppVersion(version: String) {
        contentView.versionLabel.text = version
    }

    func didUpdateCurrency(displayText: String) {
        logDebug("SettingsViewController.didUpdateCurrency: \(displayText)")
        contentView.currencyValueLabel.text = displayText
    }

    func didUpdateTagTranslation(isEnabled: Bool, isSupported: Bool) {
        // Below iOS 26 the whole group goes away rather than showing a permanently disabled row: a
        // user on an older phone can do nothing about it, and a row explaining that is clutter.
        guard isSupported else {
            contentView.setTranslationGroupHidden(true)
            return
        }
        contentView.setTranslationGroupHidden(false)
        contentView.translateTagsSwitch.isOn = isEnabled
        contentView.translateTagsSwitch.isEnabled = true

        refreshDownloadLanguagesRow()
        guard isEnabled else { return }
        // Re-ask whether a pending pair arrived while we were away. A translation succeeding is the
        // only trustworthy signal — Apple offers no progress figure, and its status was observed on
        // device still reporting "supported" long after a language was installed.
        AllocationTagTranslationCoordinator.shared.refreshDownloadState { [weak self] in
            self?.refreshDownloadLanguagesRow()
        }
    }
    
    func didEncounterBiometricError(title: String, message: String) {
        contentView.biometricSwitch.isOn = false
        showErrorAlert(title: title, message: message)
    }
    
    func didRequestReAuthentication() {
        showReAuthenticationAlert()
    }
    
    func didCompleteAccountDeletion() {
        showSuccessAlert()
    }
    
    func didFailAccountDeletion(title: String, message: String) {
        showErrorAlert(title: title, message: message)
    }
    
    func shouldShowLoading(_ show: Bool, message: String?) {
        if show, let message = message {
            LoadingManager.shared.showLoading(on: self, message: message)
        } else {
            LoadingManager.shared.hideLoading()
        }
    }
    
    func didCompleteDataRecovery(success: Bool, message: String) {
        let alert = UIAlertController(
            title: success ? "✅ Recovery Complete" : "❌ Recovery Failed",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Currency Picker
extension SettingsViewController {

    private func showCurrencyPicker() {
        let alert = UIAlertController(
            title: "settings.currency.picker.title".localized,
            message: "settings.currency.picker.message".localized,
            preferredStyle: .actionSheet
        )

        // Auto option (device locale)
        let currentCode = viewModel.getCurrentCurrencyCode()
        logDebug("showCurrencyPicker - currentCode: \(currentCode)")
        let autoTitle = "\("settings.currency.auto".localized) (\(AppConfig.deviceLocaleCurrencyCode))"
        let autoAction = UIAlertAction(title: autoTitle, style: .default) { [weak self] _ in
            logDebug("Auto action handler called, self exists: \(self != nil)")
            self?.viewModel.setCurrencyToAuto()
        }
        if currentCode == UserDefaultsManager.currencyAutoValue {
            autoAction.setValue(true, forKey: "checked")
        }
        alert.addAction(autoAction)

        // Individual currency options
        for currency in SettingsViewModel.availableCurrencies {
            let title = "\(currency.code) - \(currency.name)"
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                logDebug("Currency action handler called for: \(currency.code), self exists: \(self != nil)")
                self?.viewModel.setCurrency(code: currency.code)
            }
            if currentCode == currency.code {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))

        // For iPad support
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = contentView.currencyValueLabel
            popoverController.sourceRect = contentView.currencyValueLabel.bounds
        }

        present(alert, animated: true)
    }
}

// MARK: - Alert Methods
extension SettingsViewController {

    private func showDeleteAccountConfirmation() {
        let alert = UIAlertController(
            title: "settings.delete.account.title".localized,
            message: "settings.delete.account.warning".localized,
            preferredStyle: .alert
        )
        
        let deleteAction = UIAlertAction(
            title: "settings.delete.account.confirm".localized,
            style: .destructive
        ) { [weak self] _ in
            self?.viewModel.deleteAccount()
        }
        
        let cancelAction = UIAlertAction(
            title: "alert.cancel".localized,
            style: .cancel
        )
        
        alert.addAction(deleteAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    private func showReAuthenticationAlert() {
        let alert = UIAlertController(
            title: "settings.delete.account.reauth.title".localized,
            message: "settings.delete.account.reauth.message".localized,
            preferredStyle: .alert
        )
        
        let signOutAction = UIAlertAction(
            title: "settings.delete.account.signout".localized,
            style: .default
        ) { [weak self] _ in
            // This only clears current user data, preserving other users' data
            self?.viewModel.handleReAuthenticationSignOut()
            self?.flowDelegate?.logout()
        }
        
        let cancelAction = UIAlertAction(
            title: "alert.cancel".localized,
            style: .cancel
        )
        
        alert.addAction(signOutAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    private func showSuccessAlert() {
        let alert = UIAlertController(
            title: "settings.delete.account.success.title".localized,
            message: "settings.delete.account.success.message".localized,
            preferredStyle: .alert
        )
        
        let okAction = UIAlertAction(
            title: "alert.ok".localized,
            style: .default
        ) { [weak self] _ in
            self?.flowDelegate?.logout()
        }
        
        alert.addAction(okAction)
        present(alert, animated: true)
    }
    
    private func showErrorAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default))
        present(alert, animated: true)
    }
}
