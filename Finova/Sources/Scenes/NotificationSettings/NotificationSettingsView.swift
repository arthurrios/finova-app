//
//  NotificationSettingsView.swift
//  Finova
//
//  Created by Claude on 29/01/2026.
//

import UIKit

protocol NotificationSettingsViewDelegate: AnyObject {
  func handleDidTapBackButton()
  func didToggleAllNotifications(_ isEnabled: Bool)
  func didToggleTransactionNotifications(_ isEnabled: Bool)
  func didToggleAppUpdateNotifications(_ isEnabled: Bool)
  func didToggleNegativeBalanceNotifications(_ isEnabled: Bool)
}

final class NotificationSettingsView: UIView {
  weak var delegate: NotificationSettingsViewDelegate?

  private let scrollView: UIScrollView = {
    let scrollView = UIScrollView()
    scrollView.showsVerticalScrollIndicator = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    return scrollView
  }()

  private let contentStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = Metrics.spacing4
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

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
    label.text = "notificationSettings.header.title".localized
    label.applyStyle()
    label.textColor = Colors.gray700
    label.textAlignment = .left
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  // General Section
  private let generalHeaderView = createSectionHeader(title: "notificationSettings.section.general".localized)

  private let allNotificationsContainer = createSettingContainer()
  private let allNotificationsIconView = createIconView(imageName: "bell.slash.fill")
  private let allNotificationsLabel = createSettingLabel(text: "notificationSettings.disableAll.title".localized)
  let allNotificationsSwitch: UISwitch = {
    let toggle = UISwitch()
    toggle.onTintColor = Colors.mainRed
    toggle.translatesAutoresizingMaskIntoConstraints = false
    return toggle
  }()

  private let allNotificationsDescriptionLabel: UILabel = {
    let label = UILabel()
    label.text = "notificationSettings.disableAll.description".localized
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray500
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  // Local Notifications Section
  private let localHeaderView = createSectionHeader(title: "notificationSettings.section.local".localized)

  private let transactionContainer = createSettingContainer()
  private let transactionIconView = createIconView(imageName: "creditcard.fill")
  private let transactionLabel = createSettingLabel(text: "notificationSettings.transactions.title".localized)
  let transactionSwitch: UISwitch = {
    let toggle = UISwitch()
    toggle.onTintColor = Colors.mainMagenta
    toggle.translatesAutoresizingMaskIntoConstraints = false
    return toggle
  }()

  private let transactionDescriptionLabel: UILabel = {
    let label = UILabel()
    label.text = "notificationSettings.transactions.description".localized
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray500
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let negativeBalanceContainer = createSettingContainer()
  private let negativeBalanceIconView = createIconView(imageName: "exclamationmark.triangle.fill")
  private let negativeBalanceLabel = createSettingLabel(text: "notificationSettings.negativeBalance.title".localized)
  let negativeBalanceSwitch: UISwitch = {
    let toggle = UISwitch()
    toggle.onTintColor = Colors.mainMagenta
    toggle.translatesAutoresizingMaskIntoConstraints = false
    return toggle
  }()

  private let negativeBalanceDescriptionLabel: UILabel = {
    let label = UILabel()
    label.text = "notificationSettings.negativeBalance.description".localized
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray500
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  // Push Notifications Section
  private let pushHeaderView = createSectionHeader(title: "notificationSettings.section.push".localized)

  private let appUpdateContainer = createSettingContainer()
  private let appUpdateIconView = createIconView(imageName: "arrow.down.app.fill")
  private let appUpdateLabel = createSettingLabel(text: "notificationSettings.appUpdate.title".localized)
  let appUpdateSwitch: UISwitch = {
    let toggle = UISwitch()
    toggle.onTintColor = Colors.mainMagenta
    toggle.translatesAutoresizingMaskIntoConstraints = false
    return toggle
  }()

  private let appUpdateDescriptionLabel: UILabel = {
    let label = UILabel()
    label.text = "notificationSettings.appUpdate.description".localized
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray500
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: .zero)
    setupView()
    setupActions()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    backgroundColor = Colors.gray200

    backButton.addTarget(self, action: #selector(handleDidTapBackButton), for: .touchUpInside)

    addSubview(scrollView)
    scrollView.addSubview(headerContainerView)
    scrollView.addSubview(contentStackView)
    headerContainerView.addSubview(headerItemsView)
    headerItemsView.addSubview(backButton)
    headerItemsView.addSubview(headerTitleLabel)

    setupSections()
    setupConstraints()
  }

  private func setupSections() {
    // General section (Disable All)
    contentStackView.addArrangedSubview(generalHeaderView)
    setupAllNotificationsContainer()
    contentStackView.addArrangedSubview(allNotificationsContainer)
    contentStackView.addArrangedSubview(allNotificationsDescriptionLabel)

    // Local notifications section
    contentStackView.addArrangedSubview(localHeaderView)
    setupTransactionContainer()
    contentStackView.addArrangedSubview(transactionContainer)
    contentStackView.addArrangedSubview(transactionDescriptionLabel)

    setupNegativeBalanceContainer()
    contentStackView.addArrangedSubview(negativeBalanceContainer)
    contentStackView.addArrangedSubview(negativeBalanceDescriptionLabel)

    // Push notifications section
    contentStackView.addArrangedSubview(pushHeaderView)
    setupAppUpdateContainer()
    contentStackView.addArrangedSubview(appUpdateContainer)
    contentStackView.addArrangedSubview(appUpdateDescriptionLabel)
  }

  private func setupAllNotificationsContainer() {
    allNotificationsContainer.addSubview(allNotificationsIconView)
    allNotificationsContainer.addSubview(allNotificationsLabel)
    allNotificationsContainer.addSubview(allNotificationsSwitch)

    NSLayoutConstraint.activate([
      allNotificationsIconView.leadingAnchor.constraint(equalTo: allNotificationsContainer.leadingAnchor, constant: Metrics.spacing4),
      allNotificationsIconView.centerYAnchor.constraint(equalTo: allNotificationsContainer.centerYAnchor),

      allNotificationsLabel.leadingAnchor.constraint(equalTo: allNotificationsIconView.trailingAnchor, constant: Metrics.spacing3),
      allNotificationsLabel.centerYAnchor.constraint(equalTo: allNotificationsContainer.centerYAnchor),

      allNotificationsSwitch.trailingAnchor.constraint(equalTo: allNotificationsContainer.trailingAnchor, constant: -Metrics.spacing4),
      allNotificationsSwitch.centerYAnchor.constraint(equalTo: allNotificationsContainer.centerYAnchor)
    ])
  }

  private func setupTransactionContainer() {
    transactionContainer.addSubview(transactionIconView)
    transactionContainer.addSubview(transactionLabel)
    transactionContainer.addSubview(transactionSwitch)

    NSLayoutConstraint.activate([
      transactionIconView.leadingAnchor.constraint(equalTo: transactionContainer.leadingAnchor, constant: Metrics.spacing4),
      transactionIconView.centerYAnchor.constraint(equalTo: transactionContainer.centerYAnchor),

      transactionLabel.leadingAnchor.constraint(equalTo: transactionIconView.trailingAnchor, constant: Metrics.spacing3),
      transactionLabel.centerYAnchor.constraint(equalTo: transactionContainer.centerYAnchor),

      transactionSwitch.trailingAnchor.constraint(equalTo: transactionContainer.trailingAnchor, constant: -Metrics.spacing4),
      transactionSwitch.centerYAnchor.constraint(equalTo: transactionContainer.centerYAnchor)
    ])
  }

  private func setupNegativeBalanceContainer() {
    negativeBalanceContainer.addSubview(negativeBalanceIconView)
    negativeBalanceContainer.addSubview(negativeBalanceLabel)
    negativeBalanceContainer.addSubview(negativeBalanceSwitch)

    NSLayoutConstraint.activate([
      negativeBalanceIconView.leadingAnchor.constraint(equalTo: negativeBalanceContainer.leadingAnchor, constant: Metrics.spacing4),
      negativeBalanceIconView.centerYAnchor.constraint(equalTo: negativeBalanceContainer.centerYAnchor),

      negativeBalanceLabel.leadingAnchor.constraint(equalTo: negativeBalanceIconView.trailingAnchor, constant: Metrics.spacing3),
      negativeBalanceLabel.centerYAnchor.constraint(equalTo: negativeBalanceContainer.centerYAnchor),

      negativeBalanceSwitch.trailingAnchor.constraint(equalTo: negativeBalanceContainer.trailingAnchor, constant: -Metrics.spacing4),
      negativeBalanceSwitch.centerYAnchor.constraint(equalTo: negativeBalanceContainer.centerYAnchor)
    ])
  }

  private func setupAppUpdateContainer() {
    appUpdateContainer.addSubview(appUpdateIconView)
    appUpdateContainer.addSubview(appUpdateLabel)
    appUpdateContainer.addSubview(appUpdateSwitch)

    NSLayoutConstraint.activate([
      appUpdateIconView.leadingAnchor.constraint(equalTo: appUpdateContainer.leadingAnchor, constant: Metrics.spacing4),
      appUpdateIconView.centerYAnchor.constraint(equalTo: appUpdateContainer.centerYAnchor),

      appUpdateLabel.leadingAnchor.constraint(equalTo: appUpdateIconView.trailingAnchor, constant: Metrics.spacing3),
      appUpdateLabel.centerYAnchor.constraint(equalTo: appUpdateContainer.centerYAnchor),

      appUpdateSwitch.trailingAnchor.constraint(equalTo: appUpdateContainer.trailingAnchor, constant: -Metrics.spacing4),
      appUpdateSwitch.centerYAnchor.constraint(equalTo: appUpdateContainer.centerYAnchor)
    ])
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

      headerContainerView.topAnchor.constraint(equalTo: topAnchor),
      headerContainerView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      headerContainerView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),

      headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
      headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
      headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

      backButton.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
      backButton.leadingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),

      headerTitleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: Metrics.spacing4),
      headerTitleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),

      contentStackView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing4),
      contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Metrics.spacing4),
      contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing4),
      contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Metrics.spacing4),
      contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * Metrics.spacing4)
    ])
  }

  private func setupActions() {
    allNotificationsSwitch.addTarget(self, action: #selector(allNotificationsToggled), for: .valueChanged)
    transactionSwitch.addTarget(self, action: #selector(transactionToggled), for: .valueChanged)
    negativeBalanceSwitch.addTarget(self, action: #selector(negativeBalanceToggled), for: .valueChanged)
    appUpdateSwitch.addTarget(self, action: #selector(appUpdateToggled), for: .valueChanged)
  }

  // MARK: - Public Methods

  func updateUI(allDisabled: Bool, transactionEnabled: Bool, appUpdateEnabled: Bool, negativeBalanceEnabled: Bool) {
    allNotificationsSwitch.isOn = allDisabled

    // When all notifications are disabled, disable individual toggles
    transactionSwitch.isOn = transactionEnabled && !allDisabled
    transactionSwitch.isEnabled = !allDisabled
    transactionContainer.alpha = allDisabled ? 0.5 : 1.0

    negativeBalanceSwitch.isOn = negativeBalanceEnabled && !allDisabled
    negativeBalanceSwitch.isEnabled = !allDisabled
    negativeBalanceContainer.alpha = allDisabled ? 0.5 : 1.0

    appUpdateSwitch.isOn = appUpdateEnabled && !allDisabled
    appUpdateSwitch.isEnabled = !allDisabled
    appUpdateContainer.alpha = allDisabled ? 0.5 : 1.0
  }

  // MARK: - Actions

  @objc
  private func allNotificationsToggled() {
    delegate?.didToggleAllNotifications(allNotificationsSwitch.isOn)
  }

  @objc
  private func transactionToggled() {
    delegate?.didToggleTransactionNotifications(transactionSwitch.isOn)
  }

  @objc
  private func negativeBalanceToggled() {
    delegate?.didToggleNegativeBalanceNotifications(negativeBalanceSwitch.isOn)
  }

  @objc
  private func appUpdateToggled() {
    delegate?.didToggleAppUpdateNotifications(appUpdateSwitch.isOn)
  }

  @objc
  private func handleDidTapBackButton() {
    delegate?.handleDidTapBackButton()
  }
}

// MARK: - Factory Methods
extension NotificationSettingsView {

  private static func createSectionHeader(title: String) -> UIView {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let label = UILabel()
    label.text = title.uppercased()
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray500
    label.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(label)

    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.spacing2),
      label.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.spacing3),
      label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      container.heightAnchor.constraint(equalToConstant: 24)
    ])

    return container
  }

  private static func createSettingContainer() -> UIView {
    let container = UIView()
    container.backgroundColor = Colors.gray100
    container.layer.cornerRadius = CornerRadius.large
    container.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      container.heightAnchor.constraint(equalToConstant: 56)
    ])

    return container
  }

  private static func createIconView(imageName: String, tintColor: UIColor = Colors.gray600) -> UIImageView {
    let imageView = UIImageView()
    imageView.image = UIImage(systemName: imageName)
    imageView.tintColor = tintColor
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      imageView.heightAnchor.constraint(equalToConstant: 20),
      imageView.widthAnchor.constraint(equalToConstant: 20)
    ])

    return imageView
  }

  private static func createSettingLabel(text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = Fonts.titleSM.font
    label.textColor = Colors.gray700
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }
}
