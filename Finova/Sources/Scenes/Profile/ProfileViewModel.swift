//
//  ProfileViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 10/02/26.
//

import UIKit

final class ProfileViewModel {
    weak var delegate: ProfileViewModelDelegate?

    var userName: String = ""
    var userEmail: String = ""
    var profileImage: UIImage?

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Finova v\(version) (\(build))"
    }

    func loadUserData() {
        if let user = UserDefaultsManager.getUser() {
            userName = user.name
            userEmail = user.email
        }

        profileImage = SecureLocalDataManager.shared.loadProfileImage()

        delegate?.didUpdateUserInfo()
        delegate?.didUpdateProfileImage(profileImage)
    }

    func updateProfileImage(_ image: UIImage) {
        SecureLocalDataManager.shared.saveProfileImage(image)
        profileImage = image
        delegate?.didUpdateProfileImage(image)
    }
}
