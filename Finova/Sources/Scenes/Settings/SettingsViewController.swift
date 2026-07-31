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

    func didTapNotifications() {
        flowDelegate?.navigateToNotificationSettings()
    }

    func didTapSyncSettings() {
        flowDelegate?.navigateToSyncSettings()
    }

    func didToggleMirrorMode(_ isEnabled: Bool) {
        viewModel.toggleMirrorMode(isEnabled)
    }

    func didTapMirrorGroupPicker() {
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
    
    func didUpdateMirrorMode(isEnabled: Bool, groupName: String?) {
        contentView.mirrorModeSwitch.isOn = isEnabled
        contentView.mirrorGroupContainer.isHidden = !isEnabled
        if let groupName = groupName {
            contentView.mirrorGroupLabel.text = groupName
        } else {
            contentView.mirrorGroupLabel.text = "settings.mirrorMode.noGroup".localized
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

// MARK: - Mirror Mode Group Selection
extension SettingsViewController {

    private func showGroupSelectionSheet(groups: [BudgetGroup]) {
        let alert = UIAlertController(
            title: "settings.mirrorMode.selectGroup.title".localized,
            message: "settings.mirrorMode.selectGroup.message".localized,
            preferredStyle: .actionSheet
        )

        for group in groups {
            let action = UIAlertAction(title: group.name, style: .default) { [weak self] _ in
                self?.viewModel.selectMirrorGroup(group)
            }
            if self.viewModel.isPublishing(to: group) {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel) { [weak self] _ in
            // If user cancels without selecting a group and mirror mode was just toggled on,
            // revert the toggle since no group was selected
            if !(self?.viewModel.isMirrorModeEnabled ?? false) {
                self?.contentView.mirrorModeSwitch.isOn = false
                self?.contentView.mirrorGroupContainer.isHidden = true
            }
        })

        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = contentView.mirrorGroupContainer
            popoverController.sourceRect = contentView.mirrorGroupContainer.bounds
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
