//
//  SyncSettingsView.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

protocol SyncSettingsViewDelegate: AnyObject {
  func handleDidTapBackButton()
  func didTapSyncNow()
  func didTapResetSync()
  func didTapResumeUpload()
  func didToggleSyncEnabled(_ isEnabled: Bool)
  func didTapCloudCleanup()
  func didTapForceRePush()
  func didTapRecoverySync()
  func didTapRepairData()
  func didTapCreateBackup()
  func didTapPurgeDeadZones()
}

final class SyncSettingsView: UIView {
  weak var delegate: SyncSettingsViewDelegate?

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
    button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
    button.imageView?.contentMode = .scaleAspectFit
    button.translatesAutoresizingMaskIntoConstraints = false

    if #available(iOS 26.0, *) {
      button.tintColor = Colors.gray700
    } else {
      button.tintColor = Colors.gray500
    }

    return button
  }()

  private lazy var backButtonGlassContainer: UIView = {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    return container
  }()

  private let headerTitleLabel: UILabel = {
    let label = UILabel()
    label.fontStyle = Fonts.titleSM
    label.text = "syncSettings.header.title".localized
    label.applyStyle()
    label.textColor = Colors.gray700
    label.textAlignment = .left
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  // Sync Enabled Section
  private let syncEnabledHeaderView = createSectionHeader(title: "syncSettings.syncEnabled.title".localized)
  private let syncEnabledContainer = createSettingContainer()
  private let syncEnabledIconView = createIconView(imageName: "icloud")
  private let syncEnabledLabel = createSettingLabel(text: "syncSettings.syncEnabled.title".localized)
  private let syncEnabledSwitch: UISwitch = {
    let toggle = UISwitch()
    toggle.onTintColor = Colors.mainMagenta
    toggle.translatesAutoresizingMaskIntoConstraints = false
    return toggle
  }()

  // Status Section
  private let statusHeaderView = createSectionHeader(title: "syncSettings.section.status".localized)
  private let statusContainer = createSettingContainer()
  private let syncStatusIndicator = SyncStatusIndicator()

  // Last Sync Row
  private let lastSyncContainer = createSettingContainer()
  private let lastSyncIconView = createIconView(imageName: "clock")
  private let lastSyncLabel = createSettingLabel(text: "syncSettings.lastSync.title".localized)
  private let lastSyncDetailLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textSM.font
    label.textColor = Colors.gray500
    label.textAlignment = .right
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  // Data Sync Section
  private let dataSyncSectionStack: UIStackView = {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = Metrics.spacing4
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  private let dataSyncHeaderView = createSectionHeader(title: "syncSettings.dataSync.title".localized)

  // Download row
  private let downloadContainer = createSettingContainer()
  private let downloadIconView = createIconView(imageName: "arrow.down.circle")
  private let downloadLabel = createSettingLabel(text: "syncSettings.download.title".localized)
  private let downloadDetailLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textSM.font
    label.textColor = Colors.gray500
    label.textAlignment = .right
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  // Upload container
  private let uploadProgressContainer: UIView = {
    let container = UIView()
    container.backgroundColor = Colors.gray100
    container.layer.cornerRadius = CornerRadius.large
    container.translatesAutoresizingMaskIntoConstraints = false
    return container
  }()

  private let uploadIconView = createIconView(imageName: "arrow.up.circle")

  private let uploadStatusLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.titleSM.font
    label.textColor = Colors.gray700
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let uploadDetailLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray500
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let uploadProgressBar: RoundedProgressBar = {
    let bar = RoundedProgressBar()
    bar.trackTintColor = Colors.gray200
    bar.progressTintColor = Colors.mainMagenta
    bar.cornerRadius = 3
    bar.translatesAutoresizingMaskIntoConstraints = false
    return bar
  }()

  private let uploadResumeButton: UIButton = {
    let btn = UIButton(type: .system)
    btn.setTitle("syncSettings.upload.resume".localized, for: .normal)
    btn.setTitleColor(.white, for: .normal)
    btn.titleLabel?.font = Fonts.buttonSM.font
    btn.backgroundColor = Colors.mainMagenta
    btn.layer.cornerRadius = CornerRadius.large
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.isHidden = true
    return btn
  }()

  // Actions Section
  private let actionsHeaderView = createSectionHeader(title: "syncSettings.section.actions".localized)

  private let syncNowContainer = createSettingContainer()
  private let syncNowIconView = createIconView(imageName: "arrow.triangle.2.circlepath", tintColor: Colors.mainMagenta)
  private let syncNowLabel: UILabel = {
    let label = createSettingLabel(text: "syncSettings.syncNow.title".localized)
    label.textColor = Colors.mainMagenta
    return label
  }()
  private let syncNowButton: UIButton = {
    let btn = UIButton(type: .custom)
    btn.backgroundColor = .clear
    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
  }()

  private let resetContainer = createSettingContainer()
  private let resetIconView = createIconView(imageName: "arrow.counterclockwise", tintColor: Colors.mainRed)
  private let resetLabel: UILabel = {
    let label = createSettingLabel(text: "syncSettings.reset.title".localized)
    label.textColor = Colors.mainRed
    return label
  }()
  private let resetButton: UIButton = {
    let btn = UIButton(type: .custom)
    btn.backgroundColor = .clear
    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
  }()

  private let cloudCleanupContainer = createSettingContainer()
  private let cloudCleanupIconView = createIconView(imageName: "xmark.icloud", tintColor: Colors.mainRed)
  private let cloudCleanupLabel: UILabel = {
    let label = createSettingLabel(text: "syncSettings.cloudCleanup.title".localized)
    label.textColor = Colors.mainRed
    return label
  }()
  private let cloudCleanupButton: UIButton = {
    let btn = UIButton(type: .custom)
    btn.backgroundColor = .clear
    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
  }()

  private let forceRePushContainer = createSettingContainer()
  private let forceRePushIconView = createIconView(imageName: "icloud.and.arrow.up", tintColor: Colors.mainMagenta)
  private let forceRePushLabel: UILabel = {
    let label = createSettingLabel(text: "syncSettings.forceRePush.title".localized)
    label.textColor = Colors.mainMagenta
    return label
  }()
  private let forceRePushButton: UIButton = {
    let btn = UIButton(type: .custom)
    btn.backgroundColor = .clear
    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
  }()

  private let purgeZonesContainer = createSettingContainer()
  private let purgeZonesIconView = createIconView(imageName: "trash", tintColor: Colors.mainRed)
  private let purgeZonesLabel: UILabel = {
    let label = createSettingLabel(text: "syncSettings.purgeZones.title".localized)
    label.textColor = Colors.mainRed
    return label
  }()
  private let purgeZonesButton: UIButton = {
    let btn = UIButton(type: .custom)
    btn.backgroundColor = .clear
    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
  }()

  private let backupContainer = createSettingContainer()
  private let backupIconView = createIconView(imageName: "externaldrive.badge.timemachine", tintColor: Colors.gray600)
  private let backupLabel = createSettingLabel(text: "syncSettings.backup.title".localized)
  private let backupButton: UIButton = {
    let btn = UIButton(type: .custom)
    btn.backgroundColor = .clear
    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
  }()

  private let repairDataContainer = createSettingContainer()
  private let repairDataIconView = createIconView(imageName: "wrench.and.screwdriver", tintColor: Colors.gray600)
  private let repairDataLabel = createSettingLabel(text: "syncSettings.repairData.title".localized)
  private let repairDataButton: UIButton = {
    let btn = UIButton(type: .custom)
    btn.backgroundColor = .clear
    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
  }()

  private let recoverySyncContainer = createSettingContainer()
  private let recoverySyncIconView = createIconView(imageName: "arrow.3.trianglepath", tintColor: Colors.mainRed)
  private let recoverySyncLabel: UILabel = {
    let label = createSettingLabel(text: "syncSettings.recoverySync.title".localized)
    label.textColor = Colors.mainRed
    return label
  }()
  private let recoverySyncButton: UIButton = {
    let btn = UIButton(type: .custom)
    btn.backgroundColor = .clear
    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
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
    syncNowButton.addTarget(self, action: #selector(didTapSyncNow), for: .touchUpInside)
    resetButton.addTarget(self, action: #selector(didTapResetSync), for: .touchUpInside)
    cloudCleanupButton.addTarget(self, action: #selector(didTapCloudCleanup), for: .touchUpInside)
    forceRePushButton.addTarget(self, action: #selector(didTapForceRePush), for: .touchUpInside)
    backupButton.addTarget(self, action: #selector(didTapCreateBackup), for: .touchUpInside)
    repairDataButton.addTarget(self, action: #selector(didTapRepairData), for: .touchUpInside)
    purgeZonesButton.addTarget(self, action: #selector(didTapPurgeDeadZones), for: .touchUpInside)
    recoverySyncButton.addTarget(self, action: #selector(didTapRecoverySync), for: .touchUpInside)
    uploadResumeButton.addTarget(self, action: #selector(didTapResumeUpload), for: .touchUpInside)
    syncEnabledSwitch.addTarget(self, action: #selector(syncEnabledToggled), for: .valueChanged)

    addSubview(headerContainerView)
    addSubview(scrollView)
    scrollView.addSubview(contentStackView)
    headerContainerView.addSubview(headerItemsView)
    headerItemsView.addSubview(backButtonGlassContainer)
    backButtonGlassContainer.addSubview(backButton)
    setupBackButtonGlassEffect()
    headerItemsView.addSubview(headerTitleLabel)

    setupSections()
    setupConstraints()
  }

  private func setupSections() {
    // Sync enabled toggle
    contentStackView.addArrangedSubview(syncEnabledHeaderView)
    setupSyncEnabledContainer()
    contentStackView.addArrangedSubview(syncEnabledContainer)

    // Status section
    contentStackView.addArrangedSubview(statusHeaderView)
    setupStatusContainer()
    contentStackView.addArrangedSubview(statusContainer)

    // Last sync row
    setupLastSyncContainer()
    contentStackView.addArrangedSubview(lastSyncContainer)

    // Data sync section (download + upload)
    setupDataSyncSection()
    contentStackView.addArrangedSubview(dataSyncSectionStack)

    // Actions section
    contentStackView.addArrangedSubview(actionsHeaderView)
    setupSyncNowContainer()
    contentStackView.addArrangedSubview(syncNowContainer)
    setupResetContainer()
    contentStackView.addArrangedSubview(resetContainer)
    setupCloudCleanupContainer()
    contentStackView.addArrangedSubview(cloudCleanupContainer)
    setupForceRePushContainer()
    contentStackView.addArrangedSubview(forceRePushContainer)
    setupRecoverySyncContainer()
    contentStackView.addArrangedSubview(backupContainer)
    contentStackView.addArrangedSubview(repairDataContainer)
    contentStackView.addArrangedSubview(purgeZonesContainer)
    contentStackView.addArrangedSubview(recoverySyncContainer)
  }

  private func setupSyncEnabledContainer() {
    syncEnabledContainer.addSubview(syncEnabledIconView)
    syncEnabledContainer.addSubview(syncEnabledLabel)
    syncEnabledContainer.addSubview(syncEnabledSwitch)

    NSLayoutConstraint.activate([
      syncEnabledIconView.leadingAnchor.constraint(equalTo: syncEnabledContainer.leadingAnchor, constant: Metrics.spacing4),
      syncEnabledIconView.centerYAnchor.constraint(equalTo: syncEnabledContainer.centerYAnchor),

      syncEnabledLabel.leadingAnchor.constraint(equalTo: syncEnabledIconView.trailingAnchor, constant: Metrics.spacing3),
      syncEnabledLabel.centerYAnchor.constraint(equalTo: syncEnabledContainer.centerYAnchor),

      syncEnabledSwitch.trailingAnchor.constraint(equalTo: syncEnabledContainer.trailingAnchor, constant: -Metrics.spacing4),
      syncEnabledSwitch.centerYAnchor.constraint(equalTo: syncEnabledContainer.centerYAnchor),
    ])
  }

  private func setupStatusContainer() {
    statusContainer.addSubview(syncStatusIndicator)

    NSLayoutConstraint.activate([
      syncStatusIndicator.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: Metrics.spacing4),
      syncStatusIndicator.centerYAnchor.constraint(equalTo: statusContainer.centerYAnchor)
    ])
  }

  private func setupLastSyncContainer() {
    lastSyncContainer.addSubview(lastSyncIconView)
    lastSyncContainer.addSubview(lastSyncLabel)
    lastSyncContainer.addSubview(lastSyncDetailLabel)

    NSLayoutConstraint.activate([
      lastSyncIconView.leadingAnchor.constraint(equalTo: lastSyncContainer.leadingAnchor, constant: Metrics.spacing4),
      lastSyncIconView.centerYAnchor.constraint(equalTo: lastSyncContainer.centerYAnchor),

      lastSyncLabel.leadingAnchor.constraint(equalTo: lastSyncIconView.trailingAnchor, constant: Metrics.spacing3),
      lastSyncLabel.centerYAnchor.constraint(equalTo: lastSyncContainer.centerYAnchor),

      lastSyncDetailLabel.trailingAnchor.constraint(equalTo: lastSyncContainer.trailingAnchor, constant: -Metrics.spacing4),
      lastSyncDetailLabel.centerYAnchor.constraint(equalTo: lastSyncContainer.centerYAnchor),
      lastSyncDetailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: lastSyncLabel.trailingAnchor, constant: Metrics.spacing2)
    ])
  }

  private func setupSyncNowContainer() {
    syncNowContainer.addSubview(syncNowIconView)
    syncNowContainer.addSubview(syncNowLabel)
    syncNowContainer.addSubview(syncNowButton)

    NSLayoutConstraint.activate([
      syncNowIconView.leadingAnchor.constraint(equalTo: syncNowContainer.leadingAnchor, constant: Metrics.spacing4),
      syncNowIconView.centerYAnchor.constraint(equalTo: syncNowContainer.centerYAnchor),

      syncNowLabel.leadingAnchor.constraint(equalTo: syncNowIconView.trailingAnchor, constant: Metrics.spacing3),
      syncNowLabel.centerYAnchor.constraint(equalTo: syncNowContainer.centerYAnchor),

      syncNowButton.topAnchor.constraint(equalTo: syncNowContainer.topAnchor),
      syncNowButton.leadingAnchor.constraint(equalTo: syncNowContainer.leadingAnchor),
      syncNowButton.trailingAnchor.constraint(equalTo: syncNowContainer.trailingAnchor),
      syncNowButton.bottomAnchor.constraint(equalTo: syncNowContainer.bottomAnchor)
    ])
  }

  private func setupResetContainer() {
    resetContainer.addSubview(resetIconView)
    resetContainer.addSubview(resetLabel)
    resetContainer.addSubview(resetButton)

    NSLayoutConstraint.activate([
      resetIconView.leadingAnchor.constraint(equalTo: resetContainer.leadingAnchor, constant: Metrics.spacing4),
      resetIconView.centerYAnchor.constraint(equalTo: resetContainer.centerYAnchor),

      resetLabel.leadingAnchor.constraint(equalTo: resetIconView.trailingAnchor, constant: Metrics.spacing3),
      resetLabel.centerYAnchor.constraint(equalTo: resetContainer.centerYAnchor),

      resetButton.topAnchor.constraint(equalTo: resetContainer.topAnchor),
      resetButton.leadingAnchor.constraint(equalTo: resetContainer.leadingAnchor),
      resetButton.trailingAnchor.constraint(equalTo: resetContainer.trailingAnchor),
      resetButton.bottomAnchor.constraint(equalTo: resetContainer.bottomAnchor)
    ])
  }

  private func setupCloudCleanupContainer() {
    cloudCleanupContainer.addSubview(cloudCleanupIconView)
    cloudCleanupContainer.addSubview(cloudCleanupLabel)
    cloudCleanupContainer.addSubview(cloudCleanupButton)

    NSLayoutConstraint.activate([
      cloudCleanupIconView.leadingAnchor.constraint(equalTo: cloudCleanupContainer.leadingAnchor, constant: Metrics.spacing4),
      cloudCleanupIconView.centerYAnchor.constraint(equalTo: cloudCleanupContainer.centerYAnchor),

      cloudCleanupLabel.leadingAnchor.constraint(equalTo: cloudCleanupIconView.trailingAnchor, constant: Metrics.spacing3),
      cloudCleanupLabel.centerYAnchor.constraint(equalTo: cloudCleanupContainer.centerYAnchor),

      cloudCleanupButton.topAnchor.constraint(equalTo: cloudCleanupContainer.topAnchor),
      cloudCleanupButton.leadingAnchor.constraint(equalTo: cloudCleanupContainer.leadingAnchor),
      cloudCleanupButton.trailingAnchor.constraint(equalTo: cloudCleanupContainer.trailingAnchor),
      cloudCleanupButton.bottomAnchor.constraint(equalTo: cloudCleanupContainer.bottomAnchor)
    ])
  }

  private func setupForceRePushContainer() {
    forceRePushContainer.addSubview(forceRePushIconView)
    forceRePushContainer.addSubview(forceRePushLabel)
    forceRePushContainer.addSubview(forceRePushButton)

    NSLayoutConstraint.activate([
      forceRePushIconView.leadingAnchor.constraint(equalTo: forceRePushContainer.leadingAnchor, constant: Metrics.spacing4),
      forceRePushIconView.centerYAnchor.constraint(equalTo: forceRePushContainer.centerYAnchor),

      forceRePushLabel.leadingAnchor.constraint(equalTo: forceRePushIconView.trailingAnchor, constant: Metrics.spacing3),
      forceRePushLabel.centerYAnchor.constraint(equalTo: forceRePushContainer.centerYAnchor),

      forceRePushButton.topAnchor.constraint(equalTo: forceRePushContainer.topAnchor),
      forceRePushButton.leadingAnchor.constraint(equalTo: forceRePushContainer.leadingAnchor),
      forceRePushButton.trailingAnchor.constraint(equalTo: forceRePushContainer.trailingAnchor),
      forceRePushButton.bottomAnchor.constraint(equalTo: forceRePushContainer.bottomAnchor)
    ])
  }

  private func setupRecoverySyncContainer() {
    purgeZonesContainer.addSubview(purgeZonesIconView)
    purgeZonesContainer.addSubview(purgeZonesLabel)
    purgeZonesContainer.addSubview(purgeZonesButton)
    NSLayoutConstraint.activate([
      purgeZonesIconView.leadingAnchor.constraint(equalTo: purgeZonesContainer.leadingAnchor, constant: Metrics.spacing4),
      purgeZonesIconView.centerYAnchor.constraint(equalTo: purgeZonesContainer.centerYAnchor),
      purgeZonesLabel.leadingAnchor.constraint(equalTo: purgeZonesIconView.trailingAnchor, constant: Metrics.spacing3),
      purgeZonesLabel.centerYAnchor.constraint(equalTo: purgeZonesContainer.centerYAnchor),
      purgeZonesButton.topAnchor.constraint(equalTo: purgeZonesContainer.topAnchor),
      purgeZonesButton.leadingAnchor.constraint(equalTo: purgeZonesContainer.leadingAnchor),
      purgeZonesButton.trailingAnchor.constraint(equalTo: purgeZonesContainer.trailingAnchor),
      purgeZonesButton.bottomAnchor.constraint(equalTo: purgeZonesContainer.bottomAnchor)
    ])

    backupContainer.addSubview(backupIconView)
    backupContainer.addSubview(backupLabel)
    backupContainer.addSubview(backupButton)
    NSLayoutConstraint.activate([
      backupIconView.leadingAnchor.constraint(equalTo: backupContainer.leadingAnchor, constant: Metrics.spacing4),
      backupIconView.centerYAnchor.constraint(equalTo: backupContainer.centerYAnchor),
      backupLabel.leadingAnchor.constraint(equalTo: backupIconView.trailingAnchor, constant: Metrics.spacing3),
      backupLabel.centerYAnchor.constraint(equalTo: backupContainer.centerYAnchor),
      backupButton.topAnchor.constraint(equalTo: backupContainer.topAnchor),
      backupButton.leadingAnchor.constraint(equalTo: backupContainer.leadingAnchor),
      backupButton.trailingAnchor.constraint(equalTo: backupContainer.trailingAnchor),
      backupButton.bottomAnchor.constraint(equalTo: backupContainer.bottomAnchor)
    ])

    repairDataContainer.addSubview(repairDataIconView)
    repairDataContainer.addSubview(repairDataLabel)
    repairDataContainer.addSubview(repairDataButton)
    NSLayoutConstraint.activate([
      repairDataIconView.leadingAnchor.constraint(equalTo: repairDataContainer.leadingAnchor, constant: Metrics.spacing4),
      repairDataIconView.centerYAnchor.constraint(equalTo: repairDataContainer.centerYAnchor),
      repairDataLabel.leadingAnchor.constraint(equalTo: repairDataIconView.trailingAnchor, constant: Metrics.spacing3),
      repairDataLabel.centerYAnchor.constraint(equalTo: repairDataContainer.centerYAnchor),
      repairDataButton.topAnchor.constraint(equalTo: repairDataContainer.topAnchor),
      repairDataButton.leadingAnchor.constraint(equalTo: repairDataContainer.leadingAnchor),
      repairDataButton.trailingAnchor.constraint(equalTo: repairDataContainer.trailingAnchor),
      repairDataButton.bottomAnchor.constraint(equalTo: repairDataContainer.bottomAnchor)
    ])

    recoverySyncContainer.addSubview(recoverySyncIconView)
    recoverySyncContainer.addSubview(recoverySyncLabel)
    recoverySyncContainer.addSubview(recoverySyncButton)

    NSLayoutConstraint.activate([
      recoverySyncIconView.leadingAnchor.constraint(equalTo: recoverySyncContainer.leadingAnchor, constant: Metrics.spacing4),
      recoverySyncIconView.centerYAnchor.constraint(equalTo: recoverySyncContainer.centerYAnchor),

      recoverySyncLabel.leadingAnchor.constraint(equalTo: recoverySyncIconView.trailingAnchor, constant: Metrics.spacing3),
      recoverySyncLabel.centerYAnchor.constraint(equalTo: recoverySyncContainer.centerYAnchor),

      recoverySyncButton.topAnchor.constraint(equalTo: recoverySyncContainer.topAnchor),
      recoverySyncButton.leadingAnchor.constraint(equalTo: recoverySyncContainer.leadingAnchor),
      recoverySyncButton.trailingAnchor.constraint(equalTo: recoverySyncContainer.trailingAnchor),
      recoverySyncButton.bottomAnchor.constraint(equalTo: recoverySyncContainer.bottomAnchor)
    ])
  }

  private func setupDataSyncSection() {
    dataSyncSectionStack.addArrangedSubview(dataSyncHeaderView)

    // Download row
    setupDownloadContainer()
    dataSyncSectionStack.addArrangedSubview(downloadContainer)

    // Upload container
    dataSyncSectionStack.addArrangedSubview(uploadProgressContainer)

    uploadProgressContainer.addSubview(uploadIconView)
    uploadProgressContainer.addSubview(uploadStatusLabel)
    uploadProgressContainer.addSubview(uploadDetailLabel)
    uploadProgressContainer.addSubview(uploadProgressBar)
    uploadProgressContainer.addSubview(uploadResumeButton)

    NSLayoutConstraint.activate([
      uploadIconView.topAnchor.constraint(equalTo: uploadProgressContainer.topAnchor, constant: Metrics.spacing4),
      uploadIconView.leadingAnchor.constraint(equalTo: uploadProgressContainer.leadingAnchor, constant: Metrics.spacing4),

      uploadStatusLabel.centerYAnchor.constraint(equalTo: uploadIconView.centerYAnchor),
      uploadStatusLabel.leadingAnchor.constraint(equalTo: uploadIconView.trailingAnchor, constant: Metrics.spacing3),
      uploadStatusLabel.trailingAnchor.constraint(equalTo: uploadResumeButton.leadingAnchor, constant: -Metrics.spacing2),

      uploadDetailLabel.topAnchor.constraint(equalTo: uploadIconView.bottomAnchor, constant: Metrics.spacing2),
      uploadDetailLabel.leadingAnchor.constraint(equalTo: uploadProgressContainer.leadingAnchor, constant: Metrics.spacing4),
      uploadDetailLabel.trailingAnchor.constraint(equalTo: uploadProgressContainer.trailingAnchor, constant: -Metrics.spacing4),

      uploadProgressBar.topAnchor.constraint(equalTo: uploadDetailLabel.bottomAnchor, constant: Metrics.spacing3),
      uploadProgressBar.leadingAnchor.constraint(equalTo: uploadProgressContainer.leadingAnchor, constant: Metrics.spacing4),
      uploadProgressBar.trailingAnchor.constraint(equalTo: uploadProgressContainer.trailingAnchor, constant: -Metrics.spacing4),
      uploadProgressBar.heightAnchor.constraint(equalToConstant: 6),
      uploadProgressBar.bottomAnchor.constraint(equalTo: uploadProgressContainer.bottomAnchor, constant: -Metrics.spacing4),

      uploadResumeButton.centerYAnchor.constraint(equalTo: uploadStatusLabel.centerYAnchor),
      uploadResumeButton.trailingAnchor.constraint(equalTo: uploadProgressContainer.trailingAnchor, constant: -Metrics.spacing4),
      uploadResumeButton.heightAnchor.constraint(equalToConstant: 32),
      uploadResumeButton.widthAnchor.constraint(equalToConstant: 80),
    ])
  }

  private func setupDownloadContainer() {
    downloadContainer.addSubview(downloadIconView)
    downloadContainer.addSubview(downloadLabel)
    downloadContainer.addSubview(downloadDetailLabel)

    NSLayoutConstraint.activate([
      downloadIconView.leadingAnchor.constraint(equalTo: downloadContainer.leadingAnchor, constant: Metrics.spacing4),
      downloadIconView.centerYAnchor.constraint(equalTo: downloadContainer.centerYAnchor),

      downloadLabel.leadingAnchor.constraint(equalTo: downloadIconView.trailingAnchor, constant: Metrics.spacing3),
      downloadLabel.centerYAnchor.constraint(equalTo: downloadContainer.centerYAnchor),

      downloadDetailLabel.trailingAnchor.constraint(equalTo: downloadContainer.trailingAnchor, constant: -Metrics.spacing4),
      downloadDetailLabel.centerYAnchor.constraint(equalTo: downloadContainer.centerYAnchor),
      downloadDetailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: downloadLabel.trailingAnchor, constant: Metrics.spacing2)
    ])
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      // Header — fixed above scroll view
      headerContainerView.topAnchor.constraint(equalTo: topAnchor),
      headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

      headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
      headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
      headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

      backButtonGlassContainer.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
      backButtonGlassContainer.leadingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
      backButtonGlassContainer.widthAnchor.constraint(equalToConstant: 36),
      backButtonGlassContainer.heightAnchor.constraint(equalToConstant: 36),

      backButton.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
      backButton.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
      backButton.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
      backButton.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),

      headerTitleLabel.leadingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
      headerTitleLabel.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),

      // Scroll view — below header, fills remaining space
      scrollView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

      // Content stack — defines scrollable content size
      contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Metrics.spacing4),
      contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Metrics.spacing4),
      contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing4),
      contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Metrics.spacing4),
      contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * Metrics.spacing4)
    ])
  }

  private func setupBackButtonGlassEffect() {
    if #available(iOS 26.0, *) {
      let glassEffect = UIGlassEffect(style: .clear)
      glassEffect.isInteractive = true
      let glassView = UIVisualEffectView(effect: glassEffect)
      glassView.translatesAutoresizingMaskIntoConstraints = false

      backButtonGlassContainer.insertSubview(glassView, at: 0)
      backButtonGlassContainer.layer.cornerRadius = 18
      backButtonGlassContainer.clipsToBounds = true

      NSLayoutConstraint.activate([
        glassView.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
        glassView.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
        glassView.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
        glassView.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),
      ])
    }
  }

  // MARK: - Public Methods

  func updateSyncEnabled(_ isEnabled: Bool) {
    syncEnabledSwitch.isOn = isEnabled
    setSyncSectionsEnabled(isEnabled)
  }

  func updateUI(status: SyncStatusIndicator.Status, lastSyncText: String) {
    syncStatusIndicator.updateStatus(status)
    lastSyncDetailLabel.text = lastSyncText
  }

  func updateUploadProgress(current: Int, total: Int, status: UploadStatus) {
    switch status {
    case .uploading:
      uploadStatusLabel.text = "syncSettings.upload.uploading".localized
      uploadStatusLabel.textColor = Colors.mainMagenta
      uploadIconView.tintColor = Colors.mainMagenta
      uploadResumeButton.isHidden = true
    case .complete:
      uploadStatusLabel.text = "syncSettings.upload.complete".localized
      uploadStatusLabel.textColor = Colors.mainGreen
      uploadIconView.tintColor = Colors.mainGreen
      uploadResumeButton.isHidden = true
    case .incomplete:
      uploadStatusLabel.text = "syncSettings.upload.incomplete".localized
      uploadStatusLabel.textColor = Colors.mainRed
      uploadIconView.tintColor = Colors.mainRed
      uploadResumeButton.isHidden = false
    }

    if total > 0 {
      uploadDetailLabel.text = String(format: "syncSettings.upload.records".localized, current, total)
    } else {
      uploadDetailLabel.text = nil
    }

    let fraction: Float = total > 0 ? Float(current) / Float(total) : (status == .complete ? 1.0 : 0.0)
    uploadProgressBar.setProgress(fraction, animated: true)
  }

  func updateDownloadStatus(_ status: SyncStatusIndicator.Status) {
    switch status {
    case .syncing:
      downloadDetailLabel.text = "syncSettings.download.syncing".localized
      downloadDetailLabel.textColor = Colors.mainMagenta
      downloadIconView.tintColor = Colors.mainMagenta
    case .synced:
      downloadDetailLabel.text = "syncSettings.download.upToDate".localized
      downloadDetailLabel.textColor = Colors.mainGreen
      downloadIconView.tintColor = Colors.mainGreen
    case .error:
      downloadDetailLabel.text = "syncSettings.download.error".localized
      downloadDetailLabel.textColor = Colors.mainRed
      downloadIconView.tintColor = Colors.mainRed
    case .idle, .offline:
      downloadDetailLabel.text = "syncSettings.download.idle".localized
      downloadDetailLabel.textColor = Colors.gray500
      downloadIconView.tintColor = Colors.gray600
    }
  }

  // MARK: - Private Methods

  private func setSyncSectionsEnabled(_ isEnabled: Bool) {
    let alpha: CGFloat = isEnabled ? 1.0 : 0.4

    statusHeaderView.alpha = alpha
    statusContainer.alpha = alpha
    lastSyncContainer.alpha = alpha
    dataSyncSectionStack.alpha = alpha
    actionsHeaderView.alpha = alpha
    syncNowContainer.alpha = alpha
    resetContainer.alpha = alpha

    statusContainer.isUserInteractionEnabled = isEnabled
    lastSyncContainer.isUserInteractionEnabled = isEnabled
    dataSyncSectionStack.isUserInteractionEnabled = isEnabled
    syncNowButton.isEnabled = isEnabled
    resetButton.isEnabled = isEnabled
    uploadResumeButton.isEnabled = isEnabled
  }

  // MARK: - Actions

  @objc
  private func handleDidTapBackButton() {
    delegate?.handleDidTapBackButton()
  }

  @objc
  private func didTapSyncNow() {
    delegate?.didTapSyncNow()
  }

  @objc
  private func didTapResetSync() {
    delegate?.didTapResetSync()
  }

  @objc
  private func didTapResumeUpload() {
    delegate?.didTapResumeUpload()
  }

  @objc
  private func didTapCloudCleanup() {
    delegate?.didTapCloudCleanup()
  }

  @objc
  private func didTapForceRePush() {
    delegate?.didTapForceRePush()
  }

  @objc
  private func didTapPurgeDeadZones() {
    delegate?.didTapPurgeDeadZones()
  }

  @objc
  private func didTapCreateBackup() {
    delegate?.didTapCreateBackup()
  }

  @objc
  private func didTapRepairData() {
    delegate?.didTapRepairData()
  }

  @objc
  private func didTapRecoverySync() {
    delegate?.didTapRecoverySync()
  }

  @objc
  private func syncEnabledToggled() {
    let isEnabled = syncEnabledSwitch.isOn
    setSyncSectionsEnabled(isEnabled)
    delegate?.didToggleSyncEnabled(isEnabled)
  }
}

// MARK: - Factory Methods
extension SyncSettingsView {

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
