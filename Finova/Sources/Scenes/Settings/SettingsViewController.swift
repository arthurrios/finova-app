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

    /// Redraws the download row when a poll reports the language has landed, so the user sees it
    /// finish without having to navigate away and back.
    @objc private func handleTranslationDownloadStateChanged() {
        refreshDownloadLanguagesRow()
    }

    func didTapDownloadTranslationLanguages() {
        let coordinator = AllocationTagTranslationCoordinator.shared
        // Re-tappable if a download was dismissed: the only way back from a cancelled system sheet is
        // to ask for it again, so this must never latch permanently.
        guard !coordinator.isDownloadingLanguages else { return }  // sheet already up

        refreshDownloadLanguagesRow(isDownloading: true)
        coordinator.downloadMissingLanguages { [weak self] in
            self?.refreshDownloadLanguagesRow(isDownloading: false)
        }
    }

    /// Renders the row from the coordinator's state rather than from whatever this screen last set,
    /// so leaving and returning mid-download shows the truth instead of a stale "Downloading…".
    private func refreshDownloadLanguagesRow(isDownloading: Bool? = nil) {
        let coordinator = AllocationTagTranslationCoordinator.shared
        // "Downloading…" covers both the sheet being up AND the period after it closes while the
        // system finishes in the background - the row must not vanish and leave the user guessing.
        let downloading = (isDownloading ?? coordinator.isDownloadingLanguages)
            || coordinator.hasDownloadInProgress
        contentView.downloadLanguagesDetailLabel.text =
            downloading ? "settings.translateTags.downloading".localized : ""
        // Still tappable while downloading: re-tapping is harmless and is the only way to recover if
        // the user dismissed the sheet before confirming.
        contentView.downloadLanguagesContainer.isUserInteractionEnabled = true
        contentView.downloadLanguagesContainer.isHidden =
            !(coordinator.hasLanguagesToDownload || downloading)
    }

    func didToggleTagTranslation(_ isEnabled: Bool) {
        UserDefaultsManager.setTagNameTranslationEnabled(isEnabled)
        // Re-render immediately: turning it off must drop back to the typed names at once, not on the
        // next tag edit.
        NotificationCenter.default.post(name: .allocationTagsChanged, object: nil)
        AllocationTagTranslationCoordinator.shared.reconcile()
    }

    func didTapNotifications() {
        flowDelegate?.navigateToNotificationSettings()
    }

    func didTapSyncSettings() {
        flowDelegate?.navigateToSyncSettings()
    }

    func didToggleTransparency(_ isEnabled: Bool) {
        viewModel.toggleTransparency(isEnabled)
    }

    func didTapTransparencyGroupPicker() {
        let groups = viewModel.availableGroups
        if !groups.isEmpty {
            showGroupSelectionSheet(groups: groups)
        }
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
        contentView.translateTagsSwitch.isOn = isEnabled && isSupported
        contentView.translateTagsSwitch.isEnabled = isSupported
        contentView.translateTagsDetailLabel.text =
            isSupported ? "" : "settings.translateTags.unavailable".localized
        guard isEnabled && isSupported else {
            contentView.downloadLanguagesContainer.isHidden = true
            return
        }
        refreshDownloadLanguagesRow()
        // Ask the system whether the pair arrived while we were away. This is the only status Apple
        // offers - there is no progress figure and no way to reopen its sheet.
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
    
    func didUpdateTransparency(isEnabled: Bool, groupName: String?) {
        contentView.transparencySwitch.isOn = isEnabled
        contentView.transparencyGroupContainer.isHidden = !isEnabled
        if let groupName = groupName {
            contentView.transparencyGroupLabel.text = groupName
        } else {
            contentView.transparencyGroupLabel.text = "settings.transparency.noGroup".localized
        }
    }

    func didRequestGroupSelection(groups: [BudgetGroup]) {
        showGroupSelectionSheet(groups: groups)
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

// MARK: - Group Sharing — Group Selection
extension SettingsViewController {

    private func showGroupSelectionSheet(groups: [BudgetGroup]) {
        let alert = UIAlertController(
            title: "settings.transparency.selectGroup.title".localized,
            message: "settings.transparency.selectGroup.message".localized,
            preferredStyle: .actionSheet
        )

        for group in groups {
            let action = UIAlertAction(title: group.name, style: .default) { [weak self] _ in
                self?.viewModel.selectTransparencyGroup(group)
            }
            if self.viewModel.isPublishing(to: group) {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel) { [weak self] _ in
            // If the user cancels without selecting a group and sharing was just toggled on,
            // revert the toggle since no group was selected
            if !(self?.viewModel.isPublishingToAnyGroup ?? false) {
                self?.contentView.transparencySwitch.isOn = false
                self?.contentView.transparencyGroupContainer.isHidden = true
            }
        })

        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = contentView.transparencyGroupContainer
            popoverController.sourceRect = contentView.transparencyGroupContainer.bounds
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
