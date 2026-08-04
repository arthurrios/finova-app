//
//  BudgetGroupsViewController.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class BudgetGroupsViewController: UIViewController {
    let contentView: BudgetGroupsView
    private let viewModel: BudgetGroupsViewModel
    weak var flowDelegate: BudgetGroupsFlowDelegate?

    init(contentView: BudgetGroupsView, viewModel: BudgetGroupsViewModel, flowDelegate: BudgetGroupsFlowDelegate) {
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
        setupDelegates()
        setupTableView()
        bindViewModel()
        setupObservers()
        viewModel.loadGroups()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadGroups()
    }

    private func setupDelegates() {
        contentView.delegate = self
    }

    private func setupTableView() {
        contentView.tableView.delegate = self
        contentView.tableView.dataSource = self
        contentView.tableView.register(BudgetGroupCell.self, forCellReuseIdentifier: BudgetGroupCell.identifier)
        contentView.tableView.register(PendingInvitationCell.self, forCellReuseIdentifier: PendingInvitationCell.identifier)
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(reloadData),
            name: .budgetGroupDataChanged, object: nil
        )
    }

    @objc private func reloadData() {
        viewModel.loadGroups()
    }

    private func bindViewModel() {
        viewModel.onGroupsUpdated = { [weak self] in
            guard let self = self else { return }
            self.contentView.tableView.reloadData()
            self.contentView.updateEmptyState(isEmpty: self.viewModel.isEmpty)
        }

        viewModel.onError = { [weak self] message in
            let alert = UIAlertController(title: "alert.error".localized, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default))
            self?.present(alert, animated: true)
        }
    }

    private func showCreateGroupAlert() {
        let alert = UIAlertController(
            title: "budgetGroups.create.title".localized,
            message: "budgetGroups.create.message".localized,
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "budgetGroups.create.namePlaceholder".localized
            textField.autocapitalizationType = .words
        }

        let createAction = UIAlertAction(title: "budgetGroups.create.button".localized, style: .default) { [weak self, weak alert] _ in
            guard let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return }
            guard let self else { return }
            // Creating a group is a CloudKit round-trip; without this the sheet closed onto an
            // unchanged list and the group appeared seconds later with no explanation.
            LoadingManager.shared.showLoading(on: self)
            self.viewModel.createGroup(name: name) { _ in
                LoadingManager.shared.hideLoading()
            }
        }

        alert.addAction(createAction)
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))

        present(alert, animated: true)
    }
}

// MARK: - BudgetGroupsViewDelegate
extension BudgetGroupsViewController: BudgetGroupsViewDelegate {
    func handleDidTapBackButton() {
        flowDelegate?.dismissBudgetGroups()
    }

    func didTapCreateGroup() {
        showCreateGroupAlert()
    }

    func didSelectGroup(_ group: BudgetGroup) {
        flowDelegate?.navigateToGroupDetails(group: group)
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate
extension BudgetGroupsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? viewModel.pendingInvitations.count : viewModel.groups.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: PendingInvitationCell.identifier, for: indexPath) as? PendingInvitationCell else {
                return UITableViewCell()
            }
            cell.configure(with: viewModel.pendingInvitations[indexPath.row])
            return cell
        } else {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: BudgetGroupCell.identifier, for: indexPath) as? BudgetGroupCell else {
                return UITableViewCell()
            }
            cell.configure(with: viewModel.groups[indexPath.row])
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            let invitation = viewModel.pendingInvitations[indexPath.row]
            flowDelegate?.presentGroupInvitationFromGroups(invitation: invitation)
        } else {
            let group = viewModel.groups[indexPath.row]
            didSelectGroup(group)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // No swipe actions for pending invitations
        guard indexPath.section == 1 else { return nil }

        let group = viewModel.groups[indexPath.row]

        if group.isOwner {
            let deleteAction = UIContextualAction(style: .destructive, title: "alert.delete".localized) { [weak self] _, _, completionHandler in
                self?.viewModel.deleteGroup(at: indexPath.row)
                completionHandler(true)
            }
            return UISwipeActionsConfiguration(actions: [deleteAction])
        } else {
            let leaveAction = UIContextualAction(style: .destructive, title: "groupDetails.leave.button".localized) { [weak self] _, _, completionHandler in
                let alert = UIAlertController(
                    title: "groupDetails.leave.button".localized,
                    message: "groupDetails.leave.confirm".localized,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel) { _ in
                    completionHandler(false)
                })
                alert.addAction(UIAlertAction(title: "groupDetails.leave.button".localized, style: .destructive) { _ in
                    self?.viewModel.leaveGroup(at: indexPath.row)
                    completionHandler(true)
                })
                self?.present(alert, animated: true)
            }
            return UISwipeActionsConfiguration(actions: [leaveAction])
        }
    }
}
