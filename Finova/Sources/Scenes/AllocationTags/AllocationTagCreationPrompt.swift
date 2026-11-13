//
//  AllocationTagCreationPrompt.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import UIKit

/// The one place a tag gets created from.
///
/// Two entry points reach it - the Tags list's `+` button and the `+` chip at the end of the dashboard
/// strip - and both must behave identically: same wording, same validation, and the same push into the
/// edit screen afterwards, because a tag with no categories linked does nothing at all. Duplicating the
/// alert at each call site is how those two drift apart.
enum AllocationTagCreationPrompt {

    /// - Parameter onCreated: called with the new tag, on the main thread, after it is persisted. The
    ///   caller decides where to go next - the list pushes edit, the dashboard pushes edit too, but
    ///   from a different navigation position.
    static func present(
        from presenter: UIViewController,
        tagService: AllocationTagService = .shared,
        onCreated: @escaping (AllocationTag) -> Void
    ) {
        let alert = UIAlertController(
            title: "allocationTags.create.title".localized,
            message: "allocationTags.create.message".localized,
            preferredStyle: .alert)

        alert.addTextField { textField in
            textField.placeholder = "allocationTags.create.namePlaceholder".localized
            textField.autocapitalizationType = .words
        }

        let createAction = UIAlertAction(
            title: "allocationTags.create.button".localized, style: .default
        ) { [weak alert] _ in
            guard
                let name = alert?.textFields?.first?.text?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty,
                let tag = tagService.createTag(name: name)
            else { return }
            onCreated(tag)
        }

        alert.addAction(createAction)
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))

        presenter.present(alert, animated: true)
    }
}
