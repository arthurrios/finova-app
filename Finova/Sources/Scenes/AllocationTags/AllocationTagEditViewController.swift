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
    func didResetTranslationOverride()
}

final class AllocationTagEditViewController: UIViewController {

    let contentView: AllocationTagEditView
    private let tagService: AllocationTagService
    private let translationCache: TagTranslationCache
    private var tag: AllocationTag
    weak var flowDelegate: AllocationTagEditFlowDelegate?

    init(
        contentView: AllocationTagEditView,
        tag: AllocationTag,
        tagService: AllocationTagService = .shared,
        translationCache: TagTranslationCache = .shared,
        flowDelegate: AllocationTagEditFlowDelegate
    ) {
        self.contentView = contentView
        self.tag = tag
        self.tagService = tagService
        self.translationCache = translationCache
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
        refreshTranslationField()
    }

    /// Shows the "shown in <language>" field only when there is a translation to correct.
    ///
    /// Hidden when translation is off, unsupported, or the tag was authored in the phone's own
    /// language - which is most tags for most users, and offering to re-name them in the language
    /// they are already in would be noise.
    private func refreshTranslationField() {
        let language = Locale.current.language
        let target = language.minimalIdentifier
        guard supportsTranslation, UserDefaultsManager.isTagNameTranslationEnabled(),
            !isAuthoredInTargetLanguage(target: language)
        else {
            contentView.hideTranslationField()
            return
        }
        contentView.configureTranslation(
            languageName: Self.languageName(target),
            // The automatic result, with any override deliberately ignored - it is the placeholder,
            // so it has to show what would be used if the override were cleared.
            automaticName: tag.displayName(
                in: language, cache: translationCache, isEnabled: true, ignoringOverride: true),
            override: translationCache.override(forTagId: tag.id, language: target))
    }

    private func isAuthoredInTargetLanguage(target: Locale.Language) -> Bool {
        guard let source = translationCache.sourceLanguage(forTagId: tag.id, name: tag.name) else {
            return false
        }
        return Locale.Language(identifier: source).languageCode == target.languageCode
    }

    private var supportsTranslation: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    private static func languageName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier)
            ?? Locale.current.localizedString(forLanguageCode: identifier)
            ?? identifier
    }

    /// Like the name, committed on the way out rather than per keystroke.
    ///
    /// Order matters against `commitNameIfNeeded`: the override is keyed by tag id and language and
    /// deliberately survives a rename, so which happens first does not change the outcome - but
    /// reading the field before the rename keeps that independence obvious.
    private func commitTranslationOverrideIfNeeded() {
        guard !contentView.isTranslationFieldHidden else { return }
        let target = Locale.current.language.minimalIdentifier
        let typed = (contentView.translatedNameInput.textField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = translationCache.override(forTagId: tag.id, language: target) ?? ""
        guard typed != existing else { return }
        translationCache.setOverride(
            typed.isEmpty ? nil : typed, forTagId: tag.id, language: target)
        // Redraw everywhere the tag is shown, and let the pass pick the tag back up if the override
        // was just cleared.
        NotificationCenter.default.post(name: .allocationTagsChanged, object: nil)
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
        commitTranslationOverrideIfNeeded()
        commitNameIfNeeded()
        flowDelegate?.dismissAllocationTagEdit()
    }

    func didChangeName(_ name: String) {
        // Committed on exit; nothing to do per keystroke.
    }

    func didResetTranslationOverride() {
        // The field is already cleared; write it through immediately rather than waiting for exit,
        // so the machine translation reappears in the placeholder while the user is still looking.
        commitTranslationOverrideIfNeeded()
        refreshTranslationField()
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
        commitTranslationOverrideIfNeeded()
        commitNameIfNeeded()
        flowDelegate?.navigateToAllocationTagCategories(tag: tag)
    }

    func didTapDeleteTag() {
        confirmDelete()
    }
}
