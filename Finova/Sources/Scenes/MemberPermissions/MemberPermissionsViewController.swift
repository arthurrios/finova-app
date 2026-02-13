//
//  MemberPermissionsViewController.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class MemberPermissionsViewController: UIViewController {
    let contentView: MemberPermissionsView
    private let viewModel: MemberPermissionsViewModel
    weak var flowDelegate: MemberPermissionsFlowDelegate?

    init(contentView: MemberPermissionsView, viewModel: MemberPermissionsViewModel, flowDelegate: MemberPermissionsFlowDelegate) {
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
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
        contentView.delegate = self
        contentView.configure(with: viewModel.member)
        setupToggleCallbacks()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            viewModel.savePermissions()
        }
    }

    private func setupToggleCallbacks() {
        contentView.canCreateToggle.onToggleChanged = { [weak self] isOn in
            self?.viewModel.updatePermission(key: "canCreateTransactions", value: isOn)
        }
        contentView.canEditToggle.onToggleChanged = { [weak self] isOn in
            self?.viewModel.updatePermission(key: "canEditTransactions", value: isOn)
        }
        contentView.canDeleteToggle.onToggleChanged = { [weak self] isOn in
            self?.viewModel.updatePermission(key: "canDeleteTransactions", value: isOn)
        }
        contentView.canEditBudgetsToggle.onToggleChanged = { [weak self] isOn in
            self?.viewModel.updatePermission(key: "canEditBudgets", value: isOn)
        }
        contentView.canEditAllocationsToggle.onToggleChanged = { [weak self] isOn in
            self?.viewModel.updatePermission(key: "canEditAllocations", value: isOn)
        }
        contentView.canViewCardsToggle.onToggleChanged = { [weak self] isOn in
            self?.viewModel.updatePermission(key: "canViewCreditCards", value: isOn)
        }
        contentView.canManageCardsToggle.onToggleChanged = { [weak self] isOn in
            self?.viewModel.updatePermission(key: "canManageCreditCards", value: isOn)
        }
        contentView.canInviteToggle.onToggleChanged = { [weak self] isOn in
            self?.viewModel.updatePermission(key: "canInviteMembers", value: isOn)
        }
    }
}

// MARK: - MemberPermissionsViewDelegate
extension MemberPermissionsViewController: MemberPermissionsViewDelegate {
    func handleDidTapBackButton() {
        flowDelegate?.dismissMemberPermissions()
    }

    func didTapRemoveMember() {
        let alert = UIAlertController(
            title: "permissions.removeMember.confirm.title".localized,
            message: String(format: "permissions.removeMember.confirm.message".localized, viewModel.member.name),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        alert.addAction(UIAlertAction(title: "permissions.removeMember.button".localized, style: .destructive) { [weak self] _ in
            self?.viewModel.removeMember()
            self?.flowDelegate?.dismissMemberPermissions()
        })
        present(alert, animated: true)
    }
}
