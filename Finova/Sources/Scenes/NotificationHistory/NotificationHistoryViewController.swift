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
}

final class NotificationHistoryViewController: UIViewController {
  let contentView: NotificationHistoryView
  private let viewModel: NotificationHistoryViewModel
  weak var flowDelegate: NotificationHistoryFlowDelegate?

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
  }

  private func setupDelegates() {
    contentView.delegate = self
    contentView.tableView.delegate = self
    contentView.tableView.dataSource = self
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
      cell.configure(with: item)
    }
  }

  func didRequestOpenAppStore() {
    flowDelegate?.openAppStoreFromNotificationHistory()
  }

  func didRequestNavigateToTransaction(id: Int) {
    flowDelegate?.navigateToTransactionDetailsFromNotificationHistory(transactionId: id)
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

    cell.configure(with: item)
    return cell
  }
}

// MARK: - UITableViewDelegate
extension NotificationHistoryViewController: UITableViewDelegate {
  func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    return 98
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    viewModel.didSelectNotification(at: indexPath.row)
  }

  func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
    // Mark notification as read when it becomes visible
    viewModel.notificationBecameVisible(at: indexPath.row)
  }
}
