//
//  InviteMemberViewController.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class InviteMemberViewController: UIViewController {
    let contentView: InviteMemberView
    private let viewModel: InviteMemberViewModel
    weak var flowDelegate: InviteMemberFlowDelegate?

    static let defaultDetentIdentifier = UISheetPresentationController.Detent.Identifier("inviteDefault")
    static let expandedDetentIdentifier = UISheetPresentationController.Detent.Identifier("inviteExpanded")

    private lazy var defaultDetent = UISheetPresentationController.Detent.custom(
        identifier: Self.defaultDetentIdentifier
    ) { context in
        context.maximumDetentValue * 0.50
    }

    private lazy var expandedDetent = UISheetPresentationController.Detent.custom(
        identifier: Self.expandedDetentIdentifier
    ) { context in
        context.maximumDetentValue * 0.95
    }

    init(contentView: InviteMemberView, viewModel: InviteMemberViewModel, flowDelegate: InviteMemberFlowDelegate) {
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
        setupPresetHandler()
        setupPermissionToggleCallbacks()
        bindViewModel()
        hideKeyboardWhenTappedAround()

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardTop = keyboardFrame.origin.y
        let sheetBottom = view.convert(view.bounds, to: nil).maxY
        let overlap = max(0, sheetBottom - keyboardTop)
        contentView.adjustFooterForKeyboard(overlap: overlap)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        contentView.adjustFooterForKeyboard(overlap: 0)
    }

    private func setupPresetHandler() {
        contentView.onPresetChanged = { [weak self] selectedIndex in
            guard let self else { return }
            let isCustom = selectedIndex == 3

            self.contentView.showCustomPermissions(isCustom)
            self.updateSheetDetent(isCustom: isCustom)

            switch selectedIndex {
            case 0: self.viewModel.applyPreset(.viewOnly)
            case 1: self.viewModel.applyPreset(.canAdd)
            case 2: self.viewModel.applyPreset(.fullAccess)
            default: break
            }
        }
    }

    private func updateSheetDetent(isCustom: Bool) {
        guard let sheet = sheetPresentationController else { return }

        sheet.animateChanges {
            if isCustom {
                // Add expanded detent and switch to it
                sheet.detents = [self.defaultDetent, self.expandedDetent]
                sheet.selectedDetentIdentifier = Self.expandedDetentIdentifier
            } else {
                // Remove expanded detent — prevents keyboard from expanding sheet
                sheet.detents = [self.defaultDetent]
                sheet.selectedDetentIdentifier = Self.defaultDetentIdentifier
            }
        }
    }

    private func setupPermissionToggleCallbacks() {
        for subview in contentView.customPermissionsStack.arrangedSubviews {
            guard let row = subview as? PermissionToggleRow,
                  let key = row.accessibilityIdentifier else { continue }
            row.onToggleChanged = { [weak self] isOn in
                self?.viewModel.updatePermission(key: key, value: isOn)
            }
        }
    }

    private func bindViewModel() {
        viewModel.onPermissionsUpdated = { [weak self] permissions in
            self?.contentView.updateToggles(with: permissions)
        }
    }
}

// MARK: - InviteMemberViewDelegate
extension InviteMemberViewController: InviteMemberViewDelegate {
    func didTapClose() {
        dismiss(animated: true)
    }

    func didTapSendInvitation() {
        viewModel.email = contentView.emailInput.text ?? ""
        contentView.sendButton.startLoading()

        viewModel.sendInvitation { [weak self] result in
            self?.contentView.sendButton.stopLoading()
            switch result {
            case .success:
                let alert = UIAlertController(
                    title: "invite.success".localized,
                    message: nil,
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default) { [weak self] _ in
                    self?.dismiss(animated: true)
                })
                self?.present(alert, animated: true)
            case .failure(let error):
                let alert = UIAlertController(
                    title: "alert.error".localized,
                    message: error.localizedDescription,
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default))
                self?.present(alert, animated: true)
            }
        }
    }
}
