//
//  ProfileImageManager.swift
//  Finova
//
//  Created by Arthur Rios on 13/02/26.
//

import UIKit

class ProfileImageManager {

    static let shared = ProfileImageManager()

    private init() {}

    private var profileImagesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ProfileImages")
    }

    private func imageURL(for uid: String) -> URL {
        return profileImagesDirectory.appendingPathComponent("\(uid).jpg")
    }

    private func ensureDirectoryExists() {
        let dir = profileImagesDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func saveProfileImage(_ image: UIImage) {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return }
        ensureDirectoryExists()
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: imageURL(for: uid))
        }
    }

    func loadProfileImage() -> UIImage? {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return nil }
        let url = imageURL(for: uid)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func removeProfileImage() {
        guard let uid = UIDUserDefaultsManager.shared.currentUserUID else { return }
        removeProfileImage(for: uid)
    }

    func removeProfileImage(for uid: String) {
        let url = imageURL(for: uid)
        try? FileManager.default.removeItem(at: url)
    }
}
