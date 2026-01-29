//
//  NotificationHistoryView.swift
//  Finova
//
//  Created by Claude on 29/01/2026.
//

import UIKit

protocol NotificationHistoryViewDelegate: AnyObject {
  func handleDidTapBackButton()
  func didSelectNotification(at index: Int)
  func viewDidAppear()
}

final class NotificationHistoryView: UIView {
  weak var delegate: NotificationHistoryViewDelegate?

  private let headerContainerView: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray100
    view.translatesAutoresizingMaskIntoConstraints = false
    view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight - 12).isActive = true
    return view
  }()

  private let headerItemsView: UIView = {
    let view = UIView()
    view.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: Metrics.spacing4, leading: Metrics.spacing5, bottom: Metrics.spacing5,
      trailing: Metrics.spacing5)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let backButton: UIButton = {
    let button = UIButton(type: .system)

    if let originalImage = UIImage(named: "chevronLeft") {
      let size = CGSize(width: Metrics.backButtonSize, height: Metrics.backButtonSize)
      UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
      originalImage.draw(in: CGRect(origin: .zero, size: size))
      let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
      UIGraphicsEndImageContext()

      button.setImage(resizedImage, for: .normal)
    } else {
      button.setImage(UIImage(named: "chevronLeft"), for: .normal)
    }

    button.imageView?.contentMode = .scaleAspectFit
    button.tintColor = Colors.gray500
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }()

  private let headerTitleLabel: UILabel = {
    let label = UILabel()
    label.fontStyle = Fonts.titleSM
    label.text = "notificationHistory.header.title".localized
    label.applyStyle()
    label.textColor = Colors.gray700
    label.textAlignment = .left
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  let tableView: UITableView = {
    let table = UITableView(frame: .zero, style: .plain)
    table.backgroundColor = Colors.gray200
    table.separatorStyle = .none
    table.translatesAutoresizingMaskIntoConstraints = false
    table.register(NotificationHistoryCell.self, forCellReuseIdentifier: NotificationHistoryCell.identifier)
    return table
  }()

  private let emptyStateView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isHidden = true
    return view
  }()

  private let emptyStateIcon: UIImageView = {
    let imageView = UIImageView()
    imageView.image = UIImage(systemName: "bell.slash")
    imageView.tintColor = Colors.gray400
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false
    return imageView
  }()

  private let emptyStateLabel: UILabel = {
    let label = UILabel()
    label.text = "notificationHistory.empty.title".localized
    label.font = Fonts.titleSM.font
    label.textColor = Colors.gray500
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let emptyStateSubtitleLabel: UILabel = {
    let label = UILabel()
    label.text = "notificationHistory.empty.subtitle".localized
    label.font = Fonts.textSM.font
    label.textColor = Colors.gray400
    label.textAlignment = .center
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: .zero)
    setupView()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    backgroundColor = Colors.gray200

    backButton.addTarget(self, action: #selector(handleDidTapBackButton), for: .touchUpInside)

    addSubview(headerContainerView)
    headerContainerView.addSubview(headerItemsView)
    headerItemsView.addSubview(backButton)
    headerItemsView.addSubview(headerTitleLabel)

    addSubview(tableView)
    addSubview(emptyStateView)
    emptyStateView.addSubview(emptyStateIcon)
    emptyStateView.addSubview(emptyStateLabel)
    emptyStateView.addSubview(emptyStateSubtitleLabel)

    setupConstraints()
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      headerContainerView.topAnchor.constraint(equalTo: topAnchor),
      headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

      headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
      headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
      headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

      backButton.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
      backButton.leadingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),

      headerTitleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: Metrics.spacing4),
      headerTitleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),

      tableView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

      emptyStateView.centerXAnchor.constraint(equalTo: centerXAnchor),
      emptyStateView.centerYAnchor.constraint(equalTo: centerYAnchor),
      emptyStateView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing6),
      emptyStateView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing6),

      emptyStateIcon.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
      emptyStateIcon.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
      emptyStateIcon.widthAnchor.constraint(equalToConstant: 48),
      emptyStateIcon.heightAnchor.constraint(equalToConstant: 48),

      emptyStateLabel.topAnchor.constraint(equalTo: emptyStateIcon.bottomAnchor, constant: Metrics.spacing4),
      emptyStateLabel.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),

      emptyStateSubtitleLabel.topAnchor.constraint(equalTo: emptyStateLabel.bottomAnchor, constant: Metrics.spacing2),
      emptyStateSubtitleLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
      emptyStateSubtitleLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
      emptyStateSubtitleLabel.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
    ])
  }

  func showEmptyState(_ show: Bool) {
    emptyStateView.isHidden = !show
    tableView.isHidden = show
  }

  @objc
  private func handleDidTapBackButton() {
    delegate?.handleDidTapBackButton()
  }
}

// MARK: - NotificationHistoryCell

protocol NotificationHistoryCellDelegate: AnyObject {
  func cellDidRequestExpand(_ cell: NotificationHistoryCell)
}

final class NotificationHistoryCell: UITableViewCell {
  static let identifier = "NotificationHistoryCell"

  weak var delegate: NotificationHistoryCellDelegate?
  private var isExpanded = false

  private let containerView: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray100
    view.layer.cornerRadius = CornerRadius.large
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let iconContainerView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let iconView: UIImageView = {
    let imageView = UIImageView()
    imageView.tintColor = Colors.gray600
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false
    return imageView
  }()

  private let unreadBadge: UIView = {
    let badge = UIView()
    badge.backgroundColor = Colors.mainMagenta
    badge.layer.cornerRadius = 4
    badge.translatesAutoresizingMaskIntoConstraints = false
    return badge
  }()

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.titleSM.font
    label.textColor = Colors.gray700
    label.numberOfLines = 1
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let bodyLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textSM.font
    label.textColor = Colors.gray500
    label.numberOfLines = 1
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let dateLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray400
    label.textAlignment = .right
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let expandButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
    button.tintColor = Colors.gray400
    button.translatesAutoresizingMaskIntoConstraints = false
    button.isHidden = true
    return button
  }()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    setupCell()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupCell() {
    backgroundColor = .clear
    selectionStyle = .none

    contentView.addSubview(containerView)
    containerView.addSubview(iconContainerView)
    iconContainerView.addSubview(iconView)
    iconContainerView.addSubview(unreadBadge)
    containerView.addSubview(titleLabel)
    containerView.addSubview(bodyLabel)
    containerView.addSubview(dateLabel)
    containerView.addSubview(expandButton)

    expandButton.addTarget(self, action: #selector(expandButtonTapped), for: .touchUpInside)

    NSLayoutConstraint.activate([
      containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing2),
      containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
      containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),
      containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      iconContainerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Metrics.spacing3),
      iconContainerView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Metrics.spacing3),
      iconContainerView.widthAnchor.constraint(equalToConstant: 24),

      iconView.topAnchor.constraint(equalTo: iconContainerView.topAnchor),
      iconView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 24),
      iconView.heightAnchor.constraint(equalToConstant: 24),

      unreadBadge.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: Metrics.spacing1),
      unreadBadge.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
      unreadBadge.widthAnchor.constraint(equalToConstant: 8),
      unreadBadge.heightAnchor.constraint(equalToConstant: 8),
      unreadBadge.bottomAnchor.constraint(lessThanOrEqualTo: iconContainerView.bottomAnchor),

      titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Metrics.spacing3),
      titleLabel.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: Metrics.spacing3),
      titleLabel.trailingAnchor.constraint(equalTo: dateLabel.leadingAnchor, constant: -Metrics.spacing2),

      bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Metrics.spacing1),
      bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      bodyLabel.trailingAnchor.constraint(equalTo: expandButton.leadingAnchor, constant: -Metrics.spacing1),
      bodyLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -Metrics.spacing3),

      dateLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Metrics.spacing3),
      dateLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Metrics.spacing3),
      dateLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 80),

      expandButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Metrics.spacing3),
      expandButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Metrics.spacing2),
      expandButton.widthAnchor.constraint(equalToConstant: 24),
      expandButton.heightAnchor.constraint(equalToConstant: 24)
    ])
  }

  private var currentBodyText: String = ""

  func configure(with item: NotificationHistoryItem, isExpanded: Bool = false) {
    self.isExpanded = isExpanded
    titleLabel.text = item.title
    bodyLabel.text = item.body
    currentBodyText = item.body
    dateLabel.text = formatDate(item.date)

    // Update read/unread state
    unreadBadge.isHidden = item.isRead
    titleLabel.font = item.isRead ? Fonts.textSM.font : Fonts.titleSM.font
    titleLabel.textColor = item.isRead ? Colors.gray600 : Colors.gray700

    // Set icon based on type
    iconView.image = icon(for: item.type)

    // Update expand state
    bodyLabel.numberOfLines = isExpanded ? 0 : 1
    expandButton.setImage(
      UIImage(systemName: isExpanded ? "chevron.up" : "chevron.down"),
      for: .normal
    )

    // Initially hide expand button, will show in layoutSubviews if needed
    expandButton.isHidden = true
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    // Check if text would be truncated when limited to 1 line
    guard !currentBodyText.isEmpty, let font = bodyLabel.font else {
      expandButton.isHidden = true
      return
    }

    // Calculate available width for body text
    let availableWidth = bodyLabel.bounds.width
    guard availableWidth > 0 else { return }

    // Calculate the size needed for full text in single line
    let textSize = (currentBodyText as NSString).boundingRect(
      with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
      options: .usesLineFragmentOrigin,
      attributes: [.font: font],
      context: nil
    ).size

    // Show expand button only if text would be truncated (wider than available space)
    let wouldBeTruncated = textSize.width > availableWidth
    expandButton.isHidden = !wouldBeTruncated && !isExpanded
  }

  @objc private func expandButtonTapped() {
    delegate?.cellDidRequestExpand(self)
  }

  private func formatDate(_ date: Date) -> String {
    let calendar = Calendar.current

    if calendar.isDateInToday(date) {
      let formatter = DateFormatter()
      formatter.dateFormat = "HH:mm"
      return formatter.string(from: date)
    } else if calendar.isDateInYesterday(date) {
      return "notificationHistory.yesterday".localized
    } else {
      let formatter = DateFormatter()
      formatter.dateFormat = "dd/MM"
      return formatter.string(from: date)
    }
  }

  private func icon(for type: NotificationHistoryItem.NotificationType) -> UIImage? {
    switch type {
    case .transaction:
      return UIImage(systemName: "creditcard")
    case .negativeBalance:
      return UIImage(systemName: "exclamationmark.triangle")
    case .appUpdate:
      return UIImage(systemName: "arrow.down.app")
    case .installment:
      return UIImage(systemName: "calendar")
    case .recurring:
      return UIImage(systemName: "arrow.clockwise")
    case .monthly:
      return UIImage(systemName: "calendar.badge.clock")
    case .other:
      return UIImage(systemName: "bell")
    }
  }
}

