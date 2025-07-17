//
//  SettingsViewController.swift
//  Finova
//
//  Created by Arthur Rios on 17/07/25.
//

import UIKit

final class SettingsViewController: UIViewController {
    let contentView: SettingsView
    let viewModel: SettingsViewModel
    weak var flowDelegate: SettingsFlowDelegate?
    
    init(contentView: SettingsView, viewModel: SettingsViewModel, flowDelegate: SettingsFlowDelegate) {
        self.contentView = contentView
        self.viewModel = viewModel
        self.flowDelegate = flowDelegate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
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
        print("Tapped delete account")
    }
    
    func didToggleBiometric(_ isEnabled: Bool) {
        //
    }
    
    func handleDidTapBackButton() {
        self.flowDelegate?.didTapBackButton()
    }
}
