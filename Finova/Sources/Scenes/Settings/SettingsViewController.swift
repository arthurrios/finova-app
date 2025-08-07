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
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Update tab bar selection when settings appears
        flowDelegate?.settingsDidAppear()
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
    
    func handleDidTapBackButton() {
        self.flowDelegate?.dismissSettings()
    }
}

extension SettingsViewController: SettingsViewModelDelegate {
    func didUpdateBiometricUI(isEnabled: Bool, isAvailable: Bool, biometricType: String) {
        contentView.biometricSwitch.isOn = isEnabled
        contentView.biometricSwitch.isEnabled = isAvailable
        contentView.biometricLabel.text = biometricType
        contentView.biometricLabel.textColor = isAvailable ? Colors.gray700 : Colors.gray400
    }
    
    func didUpdateAppVersion(version: String) {
        contentView.versionLabel.text = version
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
