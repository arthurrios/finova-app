//
//  ProfileViewController.swift
//  Finova
//
//  Created by Arthur Rios on 10/02/26.
//

import UIKit

final class ProfileViewController: UIViewController {
    let contentView: ProfileView
    private let viewModel: ProfileViewModel
    weak var flowDelegate: ProfileFlowDelegate?

    init(contentView: ProfileView, viewModel: ProfileViewModel, flowDelegate: ProfileFlowDelegate) {
        self.contentView = contentView
        self.viewModel = viewModel
        self.flowDelegate = flowDelegate
        super.init(nibName: nil, bundle: nil)

        self.viewModel.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        viewModel.loadUserData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadUserData()
    }

    private func setup() {
        view.addSubview(contentView)
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
        contentView.delegate = self
    }
}

// MARK: - ProfileViewDelegate
extension ProfileViewController: ProfileViewDelegate {
    func handleDidTapBackButton() {
        flowDelegate?.dismissProfile()
    }

    func didTapAvatar() {
        selectProfileImage()
    }

    func didTapCreditCards() {
        flowDelegate?.navigateToCreditCards()
    }

    func didTapSettings() {
        flowDelegate?.navigateToSettings()
    }

    func didTapLogout() {
        let alert = UIAlertController(
            title: "profile.logout.confirm.title".localized,
            message: "profile.logout.confirm.message".localized,
            preferredStyle: .alert
        )

        let logoutAction = UIAlertAction(
            title: "profile.logout.title".localized,
            style: .destructive
        ) { [weak self] _ in
            AuthenticationManager.shared.signOut()
            SecureLocalDataManager.shared.signOut()
            UserDefaultsManager.signOutCurrentUser()

            logInfo("Complete logout performed from Profile")
            self?.flowDelegate?.logout()
        }

        let cancelAction = UIAlertAction(
            title: "alert.cancel".localized,
            style: .cancel
        )

        alert.addAction(logoutAction)
        alert.addAction(cancelAction)

        present(alert, animated: true)
    }
}

// MARK: - ProfileViewModelDelegate
extension ProfileViewController: ProfileViewModelDelegate {
    func didUpdateUserInfo() {
        contentView.nameLabel.text = viewModel.userName
        contentView.emailLabel.text = viewModel.userEmail
        contentView.versionLabel.text = viewModel.appVersion
    }

    func didUpdateProfileImage(_ image: UIImage?) {
        contentView.updateAvatar(image: image)
    }
}

// MARK: - UIImagePickerControllerDelegate
extension ProfileViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private func selectProfileImage() {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        imagePicker.allowsEditing = true
        present(imagePicker, animated: true, completion: nil)
    }

    internal func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        if let editedImage = info[UIImagePickerController.InfoKey.editedImage] as? UIImage {
            viewModel.updateProfileImage(editedImage)
        } else if let originalImage = info[.originalImage] as? UIImage {
            viewModel.updateProfileImage(originalImage)
        }

        dismiss(animated: true)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true)
    }
}
