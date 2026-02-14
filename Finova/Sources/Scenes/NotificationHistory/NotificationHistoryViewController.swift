//
//  NotificationHistoryViewController.swift
//  Finova
//
//  Created by Claude on 29/01/2026.
//

import UIKit

protocol NotificationHistoryFlowDelegate: AnyObject {
  func dismissNotificationHistory()
  func openAppStoreFromNotificationHistory()
  func navigateToTransactionDetailsFromNotificationHistory(transactionId: Int)
  func navigateToStatementDetailsFromNotificationHistory(statementId: Int)
  func navigateToGroupInvitationFromNotificationHistory(invitationId: String)
}

final class NotificationHistoryViewController: UIViewController {
  let contentView: NotificationHistoryView
  private let viewModel: NotificationHistoryViewModel
  weak var flowDelegate: NotificationHistoryFlowDelegate?

  /// Tracks which notifications are expanded (by notification ID)
  private var expandedNotificationIds: Set<String> = []

  init(
    contentView: NotificationHistoryView,
    viewModel: NotificationHistoryViewModel,
    flowDelegate: NotificationHistoryFlowDelegate
  ) {
    self.contentView = contentView
    self.viewModel = viewModel
    self.flowDelegate = flowDelegate
    super.init(nibName: nil, bundle: nil)

    self.viewModel.delegate = self
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setup()
    viewModel.loadNotifications()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    viewModel.viewWillDisappear()
  }

  private func setup() {
    view.addSubview(contentView)
    buildHierarchy()
    setupDelegates()
    setupTableView()
  }

  private func setupDelegates() {
    contentView.delegate = self
    contentView.tableView.delegate = self
    contentView.tableView.dataSource = self
  }

  private func setupTableView() {
    contentView.tableView.estimatedRowHeight = 72
    contentView.tableView.rowHeight = UITableView.automaticDimension
  }

  private func buildHierarchy() {
    setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
  }
}

// MARK: - NotificationHistoryViewDelegate
extension NotificationHistoryViewController: NotificationHistoryViewDelegate {
  func handleDidTapBackButton() {
    flowDelegate?.dismissNotificationHistory()
  }

  func handleDidTapClearAll() {
    let alert = UIAlertController(
      title: "notificationHistory.clearAll.title".localized,
      message: "notificationHistory.clearAll.message".localized,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
    alert.addAction(UIAlertAction(title: "notificationHistory.clearAll".localized, style: .destructive) { [weak self] _ in
      self?.viewModel.clearAllNotifications()
    })
    present(alert, animated: true)
  }

  func didSelectNotification(at index: Int) {
    viewModel.didSelectNotification(at: index)
  }

  func viewDidAppear() {
    // Mark visible notifications as read
  }
}

// MARK: - NotificationHistoryViewModelDelegate
extension NotificationHistoryViewController: NotificationHistoryViewModelDelegate {
  func didUpdateNotifications(_ notifications: [NotificationHistoryItem]) {
    contentView.showEmptyState(notifications.isEmpty)
    contentView.tableView.reloadData()
  }

  func didMarkNotificationAsRead(at index: Int) {
    let indexPath = IndexPath(row: index, section: 0)
    if let cell = contentView.tableView.cellForRow(at: indexPath) as? NotificationHistoryCell,
       let item = viewModel.notification(at: index) {
      let isExpanded = expandedNotificationIds.contains(item.id)
      cell.configure(with: item, isExpanded: isExpanded)
    }
  }

  func didDeleteNotification(at index: Int) {
    let indexPath = IndexPath(row: index, section: 0)
    contentView.tableView.deleteRows(at: [indexPath], with: .automatic)
    contentView.showEmptyState(viewModel.numberOfNotifications() == 0)
  }

  func didClearAllNotifications() {
    expandedNotificationIds.removeAll()
    contentView.tableView.reloadData()
    contentView.showEmptyState(true)
  }

  func didRequestOpenAppStore() {
    flowDelegate?.openAppStoreFromNotificationHistory()
  }

  func didRequestNavigateToTransaction(id: Int) {
    flowDelegate?.navigateToTransactionDetailsFromNotificationHistory(transactionId: id)
  }

  func didRequestNavigateToStatement(statementId: Int) {
    flowDelegate?.navigateToStatementDetailsFromNotificationHistory(statementId: statementId)
  }

  func didRequestNavigateToGroupInvitation(invitationId: String) {
    flowDelegate?.navigateToGroupInvitationFromNotificationHistory(invitationId: invitationId)
  }
}

// MARK: - UITableViewDataSource
extension NotificationHistoryViewController: UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return viewModel.numberOfNotifications()
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    guard let cell = tableView.dequeueReusableCell(
      withIdentifier: NotificationHistoryCell.identifier,
      for: indexPath
    ) as? NotificationHistoryCell,
    let item = viewModel.notification(at: indexPath.row) else {
      return UITableViewCell()
    }

    let isExpanded = expandedNotificationIds.contains(item.id)
    cell.configure(with: item, isExpanded: isExpanded)
    cell.delegate = self
    return cell
  }
}

// MARK: - UITableViewDelegate
extension NotificationHistoryViewController: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    viewModel.didSelectNotification(at: indexPath.row)
  }

  func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
    // Mark notification as read when it becomes visible
    viewModel.notificationBecameVisible(at: indexPath.row)
  }

  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    let deleteAction = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, completionHandler in
      self?.viewModel.deleteNotification(at: indexPath.row)
      completionHandler(true)
    }
    deleteAction.image = UIImage(systemName: "trash")
    deleteAction.backgroundColor = Colors.mainRed

    let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
    configuration.performsFirstActionWithFullSwipe = true
    return configuration
  }
}

// MARK: - NotificationHistoryCellDelegate
extension NotificationHistoryViewController: NotificationHistoryCellDelegate {
  func cellDidRequestExpand(_ cell: NotificationHistoryCell) {
    guard let indexPath = contentView.tableView.indexPath(for: cell),
          let item = viewModel.notification(at: indexPath.row) else {
      return
    }

    // Toggle expanded state
    if expandedNotificationIds.contains(item.id) {
      expandedNotificationIds.remove(item.id)
    } else {
      expandedNotificationIds.insert(item.id)
    }

    // Reload the cell with animation
    contentView.tableView.beginUpdates()
    contentView.tableView.reloadRows(at: [indexPath], with: .automatic)
    contentView.tableView.endUpdates()
  }
}
