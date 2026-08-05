//
//  AllocationTagCategoriesViewController.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import UIKit

/// Links spending categories to one tag.
///
/// The map is 1:1 - a category belongs to exactly one tag - because exclusive tags partition the plan,
/// which is what makes the subtotals add up to the budget and lets the donut draw each tag as one
/// contiguous arc. That exclusivity is the most confusing thing about the feature, so a category owned
/// by another tag says so on its row and asks before moving.
final class AllocationTagCategoriesViewController: UIViewController {

    let contentView: AllocationTagCategoriesView
    private let tagService: AllocationTagService
    private let tag: AllocationTag
    weak var flowDelegate: AllocationTagCategoriesFlowDelegate?

    /// Income-only categories are excluded: a tag answers "what does this group cost", and salary can
    /// never be part of that. Payment-method categories (`transfer`, `bankSlip`, `creditCard`) stay,
    /// because real expense transactions do land in them and would otherwise be untaggable.
    private let categories = TransactionCategory.allCases.filter { $0 != .salary }

    init(
        contentView: AllocationTagCategoriesView,
        tag: AllocationTag,
        tagService: AllocationTagService = .shared,
        flowDelegate: AllocationTagCategoriesFlowDelegate
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
        contentView.configure(tagName: tag.displayName)
        contentView.tableView.delegate = self
        contentView.tableView.dataSource = self
        contentView.tableView.register(
            AllocationTagCategoryCell.self,
            forCellReuseIdentifier: AllocationTagCategoryCell.identifier)
    }

    private func toggle(_ category: TransactionCategory) {
        let owner = tagService.tag(forCategoryKey: category.key)

        if owner?.id == tag.id {
            tagService.unassign(categoryKey: category.key)
            contentView.tableView.reloadData()
            return
        }

        guard let owner else {
            tagService.assign(categoryKey: category.key, toTagId: tag.id)
            contentView.tableView.reloadData()
            return
        }

        // Owned elsewhere: confirm, because the effect is invisible on this screen - the other tag
        // silently loses a category and its subtotal changes.
        let alert = UIAlertController(
            title: "allocationTags.categories.move.title".localized,
            message: String(
                format: "allocationTags.categories.move.message".localized,
                category.displayName, owner.name),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        alert.addAction(
            UIAlertAction(title: "allocationTags.categories.move.button".localized, style: .default) {
                [weak self] _ in
                guard let self else { return }
                self.tagService.assign(categoryKey: category.key, toTagId: self.tag.id)
                self.contentView.tableView.reloadData()
            })
        present(alert, animated: true)
    }
}

// MARK: - AllocationTagCategoriesViewDelegate

extension AllocationTagCategoriesViewController: AllocationTagCategoriesViewDelegate {
    func didTapBackButton() {
        flowDelegate?.dismissAllocationTagCategories()
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension AllocationTagCategoriesViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        categories.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard
            let cell = tableView.dequeueReusableCell(
                withIdentifier: AllocationTagCategoryCell.identifier, for: indexPath)
                as? AllocationTagCategoryCell
        else {
            return UITableViewCell()
        }

        let category = categories[indexPath.row]
        let owner = tagService.tag(forCategoryKey: category.key)
        cell.configure(
            category: category,
            isSelected: owner?.id == tag.id,
            otherTagName: owner?.id == tag.id ? nil : owner?.name)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        toggle(categories[indexPath.row])
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        56
    }
}
