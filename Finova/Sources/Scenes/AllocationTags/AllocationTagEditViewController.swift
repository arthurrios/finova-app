//
//  AllocationTagEditViewController.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import UIKit

protocol AllocationTagEditViewDelegate: AnyObject {
    func didTapBackButton()
    func didChangeName(_ name: String)
    func didChangeColorIndex(_ index: Int)
    func didChangeIconAssetName(_ assetName: String?)
    func didTapCategories()
    func didTapDeleteTag()
}

final class AllocationTagEditViewController: UIViewController {

    let contentView: AllocationTagEditView
    private let tagService: AllocationTagService
    private var tag: AllocationTag
    weak var flowDelegate: AllocationTagEditFlowDelegate?

    init(
        contentView: AllocationTagEditView,
        tag: AllocationTag,
        tagService: AllocationTagService = .shared,
        flowDelegate: AllocationTagEditFlowDelegate
    ) {
        self.contentView = contentView
        self.tag = tag
        self.tagService = tagService
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
        refreshFromStore()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The category screen writes through the service, so the count here is stale on return.
        refreshFromStore()
    }

    /// Colour and icon commit on tap, so the view is always redrawn from what was actually stored
    /// rather than from an optimistic local copy.
    private func refreshFromStore() {
        if let fresh = tagService.tag(id: tag.id) {
            tag = fresh
        }
        contentView.configure(
            with: tag, categoryCount: tagService.categoryCount(forTagId: tag.id))
    }

    /// The name is the one field that is typed rather than tapped, so it commits on the way out
    /// instead of on every keystroke - one write per edit, not one per character.
    private func commitNameIfNeeded() {
        let typed = (contentView.nameInput.textField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, typed != tag.name else { return }
        tagService.rename(tagId: tag.id, to: typed)
    }

    private func showNameRequiredAlert() {
        let alert = UIAlertController(
            title: "allocationTags.edit.error.name.title".localized,
            message: "allocationTags.edit.error.name.message".localized,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default))
        present(alert, animated: true)
    }

    private func confirmDelete() {
        let alert = UIAlertController(
            title: "allocationTags.delete.title".localized,
            message: "allocationTags.delete.message".localized,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        alert.addAction(
            UIAlertAction(title: "allocationTags.delete.confirm".localized, style: .destructive) {
                [weak self] _ in
                guard let self else { return }
                self.tagService.deleteTag(id: self.tag.id)
                self.flowDelegate?.dismissAllocationTagEdit()
            })
        present(alert, animated: true)
    }
}

// MARK: - AllocationTagEditViewDelegate

extension AllocationTagEditViewController: AllocationTagEditViewDelegate {

    func didTapBackButton() {
        let typed = (contentView.nameInput.textField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            // Refuse to leave a tag with a blank name rather than silently keeping the old one - the
            // user cleared the field on purpose and deserves to know it was not saved.
            showNameRequiredAlert()
            return
        }
        commitNameIfNeeded()
        flowDelegate?.dismissAllocationTagEdit()
    }

    func didChangeName(_ name: String) {
        // Committed on exit; nothing to do per keystroke.
    }

    func didChangeColorIndex(_ index: Int) {
        tagService.setColorIndex(index, forTagId: tag.id)
        refreshFromStore()
    }

    func didChangeIconAssetName(_ assetName: String?) {
        tagService.setIconAssetName(assetName, forTagId: tag.id)
        refreshFromStore()
    }

    func didTapCategories() {
        commitNameIfNeeded()
        flowDelegate?.navigateToAllocationTagCategories(tag: tag)
    }

    func didTapDeleteTag() {
        confirmDelete()
    }
}
