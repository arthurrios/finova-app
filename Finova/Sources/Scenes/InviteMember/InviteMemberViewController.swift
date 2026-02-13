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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSheetKeyboardObservers()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSheetKeyboardObservers()
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
        let targetIdentifier: UISheetPresentationController.Detent.Identifier = isCustom
            ? Self.expandedDetentIdentifier
            : Self.defaultDetentIdentifier

        sheet.animateChanges {
            sheet.selectedDetentIdentifier = targetIdentifier
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

// MARK: - Keyboard Handling
extension InviteMemberViewController {

    func startSheetKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sheetKeyboardWillShow(notification:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sheetKeyboardWillHide(notification:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    func stopSheetKeyboardObservers() {
        NotificationCenter.default.removeObserver(
            self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(
            self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func sheetKeyboardWillShow(notification: Notification) {
        guard
            let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }

        let keyboardTopInView = view.convert(keyboardFrame, from: nil).origin.y
        let footerBottom = contentView.footerBottomConstraint.constant == 0
            ? view.safeAreaInsets.bottom
            : 0
        let viewBottom = view.bounds.height - footerBottom
        let overlap = viewBottom - keyboardTopInView

        guard overlap > 0 else { return }

        contentView.footerBottomConstraint.constant = -overlap

        UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseInOut]) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func sheetKeyboardWillHide(notification: Notification) {
        guard
            let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }

        contentView.footerBottomConstraint.constant = 0

        UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseInOut]) {
            self.view.layoutIfNeeded()
        }
    }
}
