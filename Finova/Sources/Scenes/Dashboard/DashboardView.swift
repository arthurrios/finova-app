//
//  DashboardView.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation
import ShimmerView
import UIKit

final class DashboardView: UIView {
  public weak var delegate: DashboardViewDelegate?
  public var monthCarouselHeightConstraint: NSLayoutConstraint?

  let headerContainerView: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray100
    view.translatesAutoresizingMaskIntoConstraints = false
    view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight).isActive = true
    return view
  }()

  let headerItemsView: UIView = {
    let view = UIView()
    view.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: Metrics.spacing3, leading: Metrics.spacing5, bottom: Metrics.spacing6,
      trailing: Metrics.spacing5)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  let avatar = Avatar()

  let welcomeTitleLabel: UILabel = {
    let label = UILabel()
    label.fontStyle = Fonts.titleSM
    label.textColor = Colors.gray700
    label.textAlignment = .left
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  let welcomeSubtitleLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textSM.font
    label.textColor = Colors.gray500
    label.text = "dashboard.welcomeSubtitle".localized
    label.textAlignment = .left
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let settingsButton: UIButton = {
    let btn = UIButton(type: .system)
    btn.setImage(UIImage(named: "settingsOutlinedIcon"), for: .normal)
    btn.tintColor = Colors.gray500
    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
  }()

  private let notificationButton: UIButton = {
    let btn = UIButton(type: .system)
    btn.setImage(UIImage(named: "bell"), for: .normal)
    btn.tintColor = Colors.gray500
    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
  }()

  private let notificationBadge: UIView = {
    let badge = UIView()
    badge.backgroundColor = Colors.mainMagenta
    badge.layer.borderColor = Colors.gray100.cgColor
    badge.layer.borderWidth = 2
    badge.translatesAutoresizingMaskIntoConstraints = false
    badge.isHidden = true
    return badge
  }()

  private let notificationBadgeLabel: UILabel = {
    let label = UILabel()
    label.font = UIFont.systemFont(ofSize: 10, weight: .bold)
    label.textColor = .white
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  lazy var monthSelectorView: MonthSelectorView = {
    let sel = MonthSelectorView()
    sel.alpha = 0
    sel.heightAnchor.constraint(equalToConstant: Metrics.spacing8).isActive = true
    sel.translatesAutoresizingMaskIntoConstraints = false
    return sel
  }()

  lazy var monthCarousel: UICollectionView = {
    let layout = UICollectionViewFlowLayout()
    layout.scrollDirection = .horizontal
    layout.minimumLineSpacing = 0

    let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    collectionView.alpha = 0
    collectionView.isPagingEnabled = true
    collectionView.backgroundColor = .clear
    collectionView.showsHorizontalScrollIndicator = false
    collectionView.translatesAutoresizingMaskIntoConstraints = false
    collectionView.isDirectionalLockEnabled = true
    return collectionView
  }()

  private let addTransactionButton: UIButton = {
    let btn = UIButton(type: .system)

    if let originalImage = UIImage(named: "plus") {
      let newSize = CGSize(width: 24, height: 24)
      UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
      originalImage.draw(in: CGRect(origin: .zero, size: newSize))
      let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
      UIGraphicsEndImageContext()

      btn.setImage(resizedImage, for: .normal)
    }

    btn.imageView?.contentMode = .center
    btn.translatesAutoresizingMaskIntoConstraints = false

    // Apply Liquid Glass style for iOS 26+, fallback for older versions
    if #available(iOS 26.0, *) {
      btn.tintColor = Colors.mainMagenta
      btn.backgroundColor = .clear
    } else {
      btn.tintColor = Colors.gray100
      btn.backgroundColor = Colors.gray700
      btn.layer.shadowColor = UIColor.black.cgColor
      btn.layer.shadowOffset = CGSize(width: 0, height: 4)
      btn.layer.shadowOpacity = 0.25
      btn.layer.shadowRadius = 4
      btn.layer.shouldRasterize = true
      btn.layer.rasterizationScale = UIScreen.main.scale
    }

    return btn
  }()

  private lazy var addButtonGlassContainer: UIView = {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    return container
  }()

  let monthSelectorShimmerView: ShimmerView = {
    let style = ShimmerViewStyle(
      baseColor: Colors.gray100, highlightColor: .white, duration: 1.2, interval: 0.4,
      effectSpan: .points(120), effectAngle: 0 * CGFloat.pi)

    let view = ShimmerView()
    view.style = style
    view.layer.cornerRadius = CornerRadius.extraLarge
    view.clipsToBounds = true
    view.startAnimating()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  let monthCardShimmerView: ShimmerView = {
    let style = ShimmerViewStyle(
      baseColor: Colors.gray700, highlightColor: Colors.gray400, duration: 1.2, interval: 0.4,
      effectSpan: .points(120), effectAngle: 0 * CGFloat.pi)

    let view = ShimmerView()
    view.style = style
    view.layer.cornerRadius = CornerRadius.extraLarge
    view.clipsToBounds = true
    view.startAnimating()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  let transactionsTableShimmerView: ShimmerView = {
    let style = ShimmerViewStyle(
      baseColor: Colors.gray100, highlightColor: .white, duration: 1.2, interval: 0.4,
      effectSpan: .points(120), effectAngle: 0 * CGFloat.pi)

    let view = ShimmerView()
    view.style = style
    view.layer.borderColor = Colors.gray300.cgColor
    view.layer.borderWidth = 1
    view.layer.cornerRadius = CornerRadius.extraLarge
    view.clipsToBounds = true
    view.startAnimating()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
    setupLayout()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public func configure(userName: String, profileImage: UIImage) {
    welcomeTitleLabel.text = "dashboard.welcomeTitle".localized + "\(userName)!"
    welcomeTitleLabel.applyStyle()

    avatar.userImage = profileImage
  }

  private func setupView() {
    backgroundColor = Colors.gray200

    addSubview(headerContainerView)
    headerContainerView.addSubview(headerItemsView)
    headerItemsView.addSubview(avatar)
    headerItemsView.addSubview(welcomeTitleLabel)
    headerItemsView.addSubview(welcomeSubtitleLabel)
    headerItemsView.addSubview(settingsButton)
    headerItemsView.addSubview(notificationButton)
    headerItemsView.addSubview(notificationBadge)
    notificationBadge.addSubview(notificationBadgeLabel)

    addSubview(monthSelectorShimmerView)
    addSubview(monthCardShimmerView)
    addSubview(transactionsTableShimmerView)

    addSubview(monthSelectorView)
    addSubview(monthCarousel)

    addSubview(addButtonGlassContainer)
    addButtonGlassContainer.addSubview(addTransactionButton)
    setupAddButtonGlassEffect()

    bringSubviewToFront(addButtonGlassContainer)

    settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)

    notificationButton.addTarget(
      self,
      action: #selector(notificationsTapped),
      for: .touchUpInside)

    addTransactionButton.addTarget(
      self,
      action: #selector(handleTapAddButton),
      for: .touchUpInside)

    setupImageGesture()
    setupRefreshControl()
  }

  private func setupAddButtonGlassEffect() {
    if #available(iOS 26.0, *) {
      let glassEffect = UIGlassEffect()
      glassEffect.isInteractive = true
      let glassView = UIVisualEffectView(effect: glassEffect)
      glassView.translatesAutoresizingMaskIntoConstraints = false

      addButtonGlassContainer.insertSubview(glassView, at: 0)

      NSLayoutConstraint.activate([
        glassView.topAnchor.constraint(equalTo: addButtonGlassContainer.topAnchor),
        glassView.leadingAnchor.constraint(equalTo: addButtonGlassContainer.leadingAnchor),
        glassView.trailingAnchor.constraint(equalTo: addButtonGlassContainer.trailingAnchor),
        glassView.bottomAnchor.constraint(equalTo: addButtonGlassContainer.bottomAnchor),
      ])
    }
  }

  private func setupRefreshControl() {
    let refreshControl = UIRefreshControl()
    refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
    refreshControl.tintColor = Colors.mainMagenta
    monthCarousel.refreshControl = refreshControl
  }

  @objc private func handleRefresh() {
    delegate?.dashboardViewDidRequestRefresh(self)
  }

  func endRefreshing() {
    monthCarousel.refreshControl?.endRefreshing()
  }

  private func setupLayout() {
    NSLayoutConstraint.activate([
      headerContainerView.topAnchor.constraint(equalTo: topAnchor),
      headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

      headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
      headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
      headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

      avatar.leadingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
      avatar.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),

      welcomeTitleLabel.topAnchor.constraint(equalTo: avatar.topAnchor),
      welcomeTitleLabel.leadingAnchor.constraint(
        equalTo: avatar.trailingAnchor, constant: Metrics.spacing3),

      welcomeSubtitleLabel.topAnchor.constraint(
        equalTo: welcomeTitleLabel.bottomAnchor, constant: Metrics.spacing1),
      welcomeSubtitleLabel.leadingAnchor.constraint(equalTo: welcomeTitleLabel.leadingAnchor),

      settingsButton.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
      settingsButton.trailingAnchor.constraint(
        equalTo: headerItemsView.layoutMarginsGuide.trailingAnchor),
      settingsButton.heightAnchor.constraint(equalToConstant: Metrics.logoutButtonSize),
      settingsButton.widthAnchor.constraint(equalToConstant: Metrics.logoutButtonSize),

      notificationButton.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
      notificationButton.trailingAnchor.constraint(
        equalTo: settingsButton.leadingAnchor, constant: -Metrics.spacing3),
      notificationButton.heightAnchor.constraint(equalToConstant: Metrics.logoutButtonSize),
      notificationButton.widthAnchor.constraint(equalToConstant: Metrics.logoutButtonSize),

      notificationBadge.topAnchor.constraint(equalTo: notificationButton.topAnchor, constant: -2),
      notificationBadge.trailingAnchor.constraint(equalTo: notificationButton.trailingAnchor, constant: 4),
      notificationBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
      notificationBadge.heightAnchor.constraint(equalToConstant: 18),

      notificationBadgeLabel.centerXAnchor.constraint(equalTo: notificationBadge.centerXAnchor),
      notificationBadgeLabel.centerYAnchor.constraint(equalTo: notificationBadge.centerYAnchor),
      notificationBadgeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: notificationBadge.leadingAnchor, constant: 4),
      notificationBadgeLabel.trailingAnchor.constraint(lessThanOrEqualTo: notificationBadge.trailingAnchor, constant: -4),

      monthSelectorView.topAnchor.constraint(
        equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing5),
      monthSelectorView.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Metrics.spacing4),
      monthSelectorView.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -Metrics.spacing4),

      monthCarousel.topAnchor.constraint(equalTo: monthSelectorView.bottomAnchor),
      monthCarousel.leadingAnchor.constraint(equalTo: leadingAnchor),
      monthCarousel.trailingAnchor.constraint(equalTo: trailingAnchor),
      monthCarousel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.spacing4),

      monthSelectorShimmerView.topAnchor.constraint(
        equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing5),
      monthSelectorShimmerView.leadingAnchor.constraint(
        equalTo: monthSelectorView.leadingAnchor, constant: Metrics.spacing4),
      monthSelectorShimmerView.trailingAnchor.constraint(
        equalTo: monthSelectorView.trailingAnchor, constant: -Metrics.spacing4),
      monthSelectorShimmerView.heightAnchor.constraint(equalToConstant: Metrics.spacing8),

      monthCardShimmerView.topAnchor.constraint(
        equalTo: monthSelectorView.bottomAnchor, constant: Metrics.spacing5),
      monthCardShimmerView.leadingAnchor.constraint(
        equalTo: monthSelectorView.leadingAnchor, constant: Metrics.spacing4),
      monthCardShimmerView.trailingAnchor.constraint(
        equalTo: monthSelectorView.trailingAnchor, constant: -Metrics.spacing4),
      monthCardShimmerView.heightAnchor.constraint(equalToConstant: Metrics.monthCardShimmerHeight),

      transactionsTableShimmerView.topAnchor.constraint(
        equalTo: monthCardShimmerView.bottomAnchor, constant: Metrics.spacing4),
      transactionsTableShimmerView.leadingAnchor.constraint(
        equalTo: monthSelectorView.leadingAnchor, constant: Metrics.spacing4),
      transactionsTableShimmerView.trailingAnchor.constraint(
        equalTo: monthSelectorView.trailingAnchor, constant: -Metrics.spacing4),
      transactionsTableShimmerView.bottomAnchor.constraint(
        equalTo: bottomAnchor, constant: -Metrics.spacing4),

      addButtonGlassContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
      addButtonGlassContainer.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
      addButtonGlassContainer.heightAnchor.constraint(equalToConstant: Metrics.addButtonSize),
      addButtonGlassContainer.widthAnchor.constraint(equalToConstant: Metrics.addButtonSize),

      addTransactionButton.topAnchor.constraint(equalTo: addButtonGlassContainer.topAnchor),
      addTransactionButton.leadingAnchor.constraint(equalTo: addButtonGlassContainer.leadingAnchor),
      addTransactionButton.trailingAnchor.constraint(equalTo: addButtonGlassContainer.trailingAnchor),
      addTransactionButton.bottomAnchor.constraint(equalTo: addButtonGlassContainer.bottomAnchor),
    ])

    // Set up the month carousel height constraint
    monthCarouselHeightConstraint = monthCarousel.heightAnchor.constraint(equalToConstant: 500)
    monthCarouselHeightConstraint?.isActive = true
  }

  func hideShimmerViewsAndShowOriginals() {
    UIView.animate(
      withDuration: 0.3,
      animations: {
        self.monthSelectorShimmerView.alpha = 0
        self.monthCardShimmerView.alpha = 0
        self.transactionsTableShimmerView.alpha = 0

        self.monthSelectorView.alpha = 1
        self.monthCarousel.alpha = 1
      },
      completion: { _ in
        self.monthSelectorShimmerView.removeFromSuperview()
        self.monthCardShimmerView.removeFromSuperview()
        self.transactionsTableShimmerView.removeFromSuperview()

        self.bringSubviewToFront(self.addButtonGlassContainer)

        self.setNeedsLayout()
        self.layoutIfNeeded()
      })
  }

  @objc private func notificationsTapped() {
    delegate?.didTapNotifications()
  }

  @objc private func settingsTapped() {
    delegate?.didTapSettings()
  }

  /// Updates the notification badge visibility and count
  func updateNotificationBadge(count: Int) {
    notificationBadge.isHidden = count == 0
    notificationBadgeLabel.text = count > 99 ? "99+" : "\(count)"
  }

  private func setupImageGesture() {
    let tapGestureRecognizer = UITapGestureRecognizer(
      target: self, action: #selector(handleProfileImageTap))
    avatar.addGestureRecognizer(tapGestureRecognizer)
  }

  @objc
  private func handleProfileImageTap() {
    delegate?.didTapProfileImage()
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    let cornerRadius = addButtonGlassContainer.bounds.height / 2
    addButtonGlassContainer.layer.cornerRadius = cornerRadius
    addButtonGlassContainer.clipsToBounds = true
    notificationBadge.layer.cornerRadius = notificationBadge.bounds.height / 2

    // Only apply shadow for pre-iOS 26
    if #unavailable(iOS 26.0) {
      addTransactionButton.layer.cornerRadius = cornerRadius
      addTransactionButton.layer.shadowPath =
        UIBezierPath(
          roundedRect: addTransactionButton.bounds,
          cornerRadius: cornerRadius
        ).cgPath
    }
  }

  @objc
  private func handleTapAddButton() {
    delegate?.didTapAddTransaction()
  }
}
