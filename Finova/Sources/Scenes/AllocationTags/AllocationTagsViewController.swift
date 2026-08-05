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
        // Long-press-and-drag to reorder, without an edit mode. `dragInteractionEnabled` is what makes
        // the lift happen outside `isEditing`; tap-to-edit and swipe-to-delete still work because
        // UIKit tells the three gestures apart by press duration and direction.
        contentView.tableView.dragInteractionEnabled = true
        contentView.tableView.dragDelegate = self
        contentView.tableView.dropDelegate = self
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
        AllocationTagCreationPrompt.present(from: self) { [weak self] tag in
            guard let self else { return }
            self.viewModel.loadTags()
            // Straight into editing: a tag with no categories has no effect on anything.
            self.flowDelegate?.navigateToAllocationTagEdit(tag: tag)
        }
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

// MARK: - Drag to reorder

extension AllocationTagsViewController: UITableViewDragDelegate, UITableViewDropDelegate {

    func tableView(
        _ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard viewModel.tags.indices.contains(indexPath.row) else { return [] }
        // An empty provider on purpose: this drag never leaves the table, so there is nothing to
        // serialise for another app. `localObject` carries the identity, and the source index path
        // comes from the coordinator.
        let item = UIDragItem(itemProvider: NSItemProvider())
        item.localObject = viewModel.tags[indexPath.row].id
        return [item]
    }

    func tableView(
        _ tableView: UITableView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?
    ) -> UITableViewDropProposal {
        // Refuse anything that did not start here, so a drag from another app cannot land on the list.
        guard session.localDragSession != nil else {
            return UITableViewDropProposal(operation: .cancel)
        }
        return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let item = coordinator.items.first, let source = item.sourceIndexPath else { return }
        // A drop past the last row reports no destination; treat it as "to the end".
        let destination = coordinator.destinationIndexPath
            ?? IndexPath(row: max(viewModel.tags.count - 1, 0), section: 0)
        guard source != destination else { return }

        viewModel.moveTag(from: source.row, to: destination.row)
        tableView.moveRow(at: source, to: destination)
        coordinator.drop(item.dragItem, toRowAt: destination)

        // The donut and the chip strip order themselves by `sortOrder`, so they need telling. The
        // service already posted `.allocationTagsChanged` from `reorder`, which is what redraws them -
        // this only refreshes the visible rows, whose subtitles are unaffected by order.
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
        cell.configure(
            with: tag,
            categoryCount: viewModel.categoryCount(for: tag),
            isReorderable: viewModel.tags.count > 1)
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
