//
//  AllocationTagsViewController.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import UIKit

final class AllocationTagsViewController: UIViewController {

    let contentView: AllocationTagsView
    private let viewModel: AllocationTagsViewModel
    weak var flowDelegate: AllocationTagsFlowDelegate?

    init(
        contentView: AllocationTagsView,
        viewModel: AllocationTagsViewModel,
        flowDelegate: AllocationTagsFlowDelegate
    ) {
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
        setupTableView()
        bindViewModel()
        viewModel.loadTags()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Category links and names change on the pushed screens, so the counts here are stale on
        // every return.
        viewModel.loadTags()
    }

    private func setupTableView() {
        contentView.tableView.delegate = self
        contentView.tableView.dataSource = self
        contentView.tableView.register(
            AllocationTagCell.self, forCellReuseIdentifier: AllocationTagCell.identifier)
    }

    private func bindViewModel() {
        viewModel.onTagsUpdated = { [weak self] in
            guard let self else { return }
            self.contentView.tableView.reloadData()
            self.contentView.updateEmptyState(isEmpty: self.viewModel.isEmpty)
        }
    }

    private func showCreateTagAlert() {
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
        ) { [weak self, weak alert] _ in
            guard
                let name = alert?.textFields?.first?.text?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty,
                let tag = self?.viewModel.createTag(name: name)
            else { return }
            // Straight into editing: a tag with no categories has no effect on anything.
            self?.flowDelegate?.navigateToAllocationTagEdit(tag: tag)
        }

        alert.addAction(createAction)
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))

        present(alert, animated: true)
    }

    private func confirmDelete(at index: Int, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(
            title: "allocationTags.delete.title".localized,
            // Spelled out because nobody assumes it: deleting a lens must not read as deleting the
            // money behind it.
            message: "allocationTags.delete.message".localized,
            preferredStyle: .alert)

        alert.addAction(
            UIAlertAction(title: "alert.cancel".localized, style: .cancel) { _ in
                completion(false)
            })
        alert.addAction(
            UIAlertAction(title: "allocationTags.delete.confirm".localized, style: .destructive) {
                [weak self] _ in
                self?.viewModel.deleteTag(at: index)
                completion(true)
            })

        present(alert, animated: true)
    }
}

// MARK: - AllocationTagsViewDelegate

extension AllocationTagsViewController: AllocationTagsViewDelegate {
    func didTapBackButton() {
        flowDelegate?.dismissAllocationTags()
    }

    func didTapCreateTag() {
        showCreateTagAlert()
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension AllocationTagsViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.tags.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard
            let cell = tableView.dequeueReusableCell(
                withIdentifier: AllocationTagCell.identifier, for: indexPath) as? AllocationTagCell
        else {
            return UITableViewCell()
        }
        let tag = viewModel.tags[indexPath.row]
        cell.configure(with: tag, categoryCount: viewModel.categoryCount(for: tag))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        flowDelegate?.navigateToAllocationTagEdit(tag: viewModel.tags[indexPath.row])
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(
            style: .destructive, title: "alert.delete".localized
        ) { [weak self] _, _, completionHandler in
            self?.confirmDelete(at: indexPath.row, completion: completionHandler)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}
