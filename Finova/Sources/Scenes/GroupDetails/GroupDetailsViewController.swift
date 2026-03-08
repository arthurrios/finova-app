//
//  GroupDetailsViewController.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class GroupDetailsViewController: UIViewController {
    let contentView: GroupDetailsView
    private let viewModel: GroupDetailsViewModel
    weak var flowDelegate: GroupDetailsFlowDelegate?

    init(contentView: GroupDetailsView, viewModel: GroupDetailsViewModel, flowDelegate: GroupDetailsFlowDelegate) {
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
        viewModel.loadGroupDetails()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGroupDataChanged),
            name: .budgetGroupDataChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadGroupDetails()
    }

    @objc private func handleGroupDataChanged() {
        viewModel.loadGroupDetails()
    }

    private func setupDelegates() {
        contentView.delegate = self
    }

    private func setupTableView() {
        contentView.membersTableView.delegate = self
        contentView.membersTableView.dataSource = self
        contentView.membersTableView.register(GroupMemberCell.self, forCellReuseIdentifier: GroupMemberCell.identifier)

        contentView.sharedCardsTableView.delegate = self
        contentView.sharedCardsTableView.dataSource = self
        contentView.sharedCardsTableView.register(SharedCardTableViewCell.self, forCellReuseIdentifier: SharedCardTableViewCell.identifier)
    }

    private func bindViewModel() {
        viewModel.onGroupUpdated = { [weak self] in
            guard let self = self else { return }
            self.contentView.configure(with: self.viewModel.group)
            self.contentView.membersTableView.reloadData()
            self.contentView.updateMembersTableHeight(count: self.viewModel.group.members.count)
            self.contentView.sharedCardsTableView.reloadData()
            self.contentView.updateSharedCardsTableHeight()
        }

        viewModel.onError = { [weak self] message in
            let alert = UIAlertController(title: "alert.error".localized, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default))
            self?.present(alert, animated: true)
        }
    }
}

// MARK: - GroupDetailsViewDelegate
extension GroupDetailsViewController: GroupDetailsViewDelegate {
    func handleDidTapBackButton() {
        flowDelegate?.dismissGroupDetails()
    }

    func didTapInvite() {
        flowDelegate?.openInviteMemberModal(group: viewModel.group)
    }

    func didTapLeaveGroup() {
        let alert = UIAlertController(
            title: "groupDetails.leave.button".localized,
            message: "groupDetails.leave.confirm".localized,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        alert.addAction(UIAlertAction(title: "groupDetails.leave.button".localized, style: .destructive) { [weak self] _ in
            self?.viewModel.leaveGroup()
            self?.flowDelegate?.dismissGroupDetails()
        })
        present(alert, animated: true)
    }

    func didTapDeleteGroup() {
        let alert = UIAlertController(
            title: "groupDetails.delete.button".localized,
            message: "groupDetails.delete.confirm".localized,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        alert.addAction(UIAlertAction(title: "alert.delete".localized, style: .destructive) { [weak self] _ in
            self?.viewModel.deleteGroup()
            self?.flowDelegate?.dismissGroupDetails()
        })
        present(alert, animated: true)
    }

    func didTapRenameGroup() {
        let alert = UIAlertController(
            title: "groupDetails.rename.title".localized,
            message: nil,
            preferredStyle: .alert)
        alert.addTextField { [weak self] textField in
            textField.text = self?.viewModel.group.name
            textField.font = Fonts.input.font
        }
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        alert.addAction(UIAlertAction(title: "common.save".localized, style: .default) { [weak self] _ in
            guard let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return }
            self?.viewModel.renameGroup(to: name)
        })
        present(alert, animated: true)
    }

    func didTapCurrency() {
        guard viewModel.isOwner else { return }
        showCurrencyPicker()
    }

    func didSelectMember(_ member: GroupMember) {
        guard viewModel.isOwner, member.role != .owner else { return }
        flowDelegate?.navigateToMemberPermissions(member: member, group: viewModel.group)
    }

    func didTapMigrateData() {
        let counts = viewModel.fetchMigrationCounts()

        if counts.isEmpty {
            let alert = UIAlertController(
                title: "groupDetails.migration.empty.title".localized,
                message: "groupDetails.migration.empty.message".localized,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default))
            present(alert, animated: true)
            return
        }

        let message = String(
            format: "groupDetails.migration.actionSheet.message".localized,
            counts.transactions, counts.budgets, counts.creditCards, counts.allocations)

        let actionSheet = UIAlertController(
            title: "groupDetails.migration.actionSheet.title".localized,
            message: message,
            preferredStyle: .actionSheet)

        actionSheet.addAction(UIAlertAction(
            title: "groupDetails.migration.actionSheet.confirm".localized,
            style: .default
        ) { [weak self] _ in
            self?.confirmMigration(counts: counts)
        })
        actionSheet.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))

        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        present(actionSheet, animated: true)
    }
}

// MARK: - Migration Flow
extension GroupDetailsViewController {

    private func confirmMigration(counts: MigrationCounts) {
        let message = String(
            format: "groupDetails.migration.confirm.message".localized,
            counts.total, viewModel.group.name)

        let alert = UIAlertController(
            title: "groupDetails.migration.confirm.title".localized,
            message: message,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        alert.addAction(UIAlertAction(
            title: "groupDetails.migration.confirm.action".localized,
            style: .destructive
        ) { [weak self] _ in
            self?.executeMigration(counts: counts)
        })
        present(alert, animated: true)
    }

    private func executeMigration(counts: MigrationCounts) {
        LoadingManager.shared.showLoading(on: self)

        viewModel.migratePersonalData { [weak self] in
            guard let self = self else { return }
            LoadingManager.shared.hideLoading()

            let message = String(
                format: "groupDetails.migration.success.message".localized,
                counts.transactions, counts.budgets, counts.creditCards, counts.allocations)

            let alert = UIAlertController(
                title: "groupDetails.migration.success.title".localized,
                message: message,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default) { [weak self] _ in
                self?.viewModel.loadGroupDetails()
            })
            self.present(alert, animated: true)
        }
    }
}

// MARK: - Currency Picker
extension GroupDetailsViewController {

    private func showCurrencyPicker() {
        let alert = UIAlertController(
            title: "settings.currency.picker.title".localized,
            message: "settings.currency.picker.message".localized,
            preferredStyle: .actionSheet
        )

        let currentCode = viewModel.group.currency

        // Individual currency options
        for currency in SettingsViewModel.availableCurrencies {
            let title = "\(currency.code) - \(currency.name)"
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.viewModel.updateGroupCurrency(to: currency.code)
            }
            if currentCode == currency.code {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))

        // For iPad support
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }

        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate
extension GroupDetailsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView === contentView.sharedCardsTableView {
            return viewModel.group.sharedCards.count
        }
        return viewModel.group.members.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView === contentView.sharedCardsTableView {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: SharedCardTableViewCell.identifier, for: indexPath) as? SharedCardTableViewCell else {
                return UITableViewCell()
            }
            let card = viewModel.group.sharedCards[indexPath.row]
            cell.configure(with: card)
            return cell
        }

        guard let cell = tableView.dequeueReusableCell(withIdentifier: GroupMemberCell.identifier, for: indexPath) as? GroupMemberCell else {
            return UITableViewCell()
        }
        let member = viewModel.group.members[indexPath.row]
        cell.configure(with: member, isCurrentUserOwner: viewModel.isOwner)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView === contentView.sharedCardsTableView { return }
        let member = viewModel.group.members[indexPath.row]
        didSelectMember(member)
    }
}
