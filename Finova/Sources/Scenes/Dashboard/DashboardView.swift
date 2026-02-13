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

  let accountContextLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textSM.font
    label.textColor = Colors.mainMagenta
    label.text = "dashboard.context.label".localized
    label.textAlignment = .left
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let accountContextChevron: UIImageView = {
    let imageView = UIImageView()
    let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
    imageView.image = UIImage(systemName: "chevron.right", withConfiguration: config)
    imageView.tintColor = Colors.mainMagenta
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false
    return imageView
  }()

  private let profileTapArea: UIView = {
    let view = UIView()
    view.backgroundColor = .clear
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let profileTapButton: UIButton = {
    let btn = UIButton(type: .custom)
    btn.backgroundColor = .clear
    btn.translatesAutoresizingMaskIntoConstraints = false
    return btn
  }()

  private let contextTapArea: UIView = {
    let view = UIView()
    view.backgroundColor = .clear
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
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
    headerItemsView.addSubview(profileTapArea)
    profileTapArea.addSubview(avatar)
    profileTapArea.addSubview(welcomeTitleLabel)
    headerItemsView.addSubview(contextTapArea)
    contextTapArea.addSubview(accountContextLabel)
    contextTapArea.addSubview(accountContextChevron)
    headerItemsView.addSubview(notificationButton)
    headerItemsView.addSubview(notificationBadge)
    notificationBadge.addSubview(notificationBadgeLabel)
    headerItemsView.addSubview(profileTapButton)

    addSubview(monthSelectorShimmerView)
    addSubview(monthCardShimmerView)
    addSubview(transactionsTableShimmerView)

    addSubview(monthSelectorView)
    addSubview(monthCarousel)

    addSubview(addButtonGlassContainer)
    addButtonGlassContainer.addSubview(addTransactionButton)
    setupAddButtonGlassEffect()

    bringSubviewToFront(addButtonGlassContainer)

    notificationButton.addTarget(
      self,
      action: #selector(notificationsTapped),
      for: .touchUpInside)

    addTransactionButton.addTarget(
      self,
      action: #selector(handleTapAddButton),
      for: .touchUpInside)

    setupProfileTapGesture()
    setupContextTapGesture()
    setupRefreshControl()
  }

  private func setupAddButtonGlassEffect() {
    if #available(iOS 26.0, *) {
      let glassEffect = UIGlassEffect(style: .clear)
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

      profileTapArea.leadingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
      profileTapArea.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
      profileTapArea.trailingAnchor.constraint(lessThanOrEqualTo: notificationButton.leadingAnchor, constant: -Metrics.spacing3),

      avatar.leadingAnchor.constraint(equalTo: profileTapArea.leadingAnchor),
      avatar.topAnchor.constraint(equalTo: profileTapArea.topAnchor),
      avatar.bottomAnchor.constraint(equalTo: profileTapArea.bottomAnchor),

      // Clear button overlay on welcome area — topmost in z-order, guaranteed to receive taps
      profileTapButton.topAnchor.constraint(equalTo: profileTapArea.topAnchor),
      profileTapButton.leadingAnchor.constraint(equalTo: profileTapArea.leadingAnchor),
      profileTapButton.trailingAnchor.constraint(equalTo: profileTapArea.trailingAnchor),
      profileTapButton.bottomAnchor.constraint(equalTo: profileTapArea.bottomAnchor),

      welcomeTitleLabel.topAnchor.constraint(equalTo: avatar.topAnchor),
      welcomeTitleLabel.leadingAnchor.constraint(
        equalTo: avatar.trailingAnchor, constant: Metrics.spacing3),

      contextTapArea.topAnchor.constraint(
        equalTo: welcomeTitleLabel.bottomAnchor, constant: Metrics.spacing1),
      contextTapArea.leadingAnchor.constraint(equalTo: welcomeTitleLabel.leadingAnchor),

      accountContextLabel.topAnchor.constraint(equalTo: contextTapArea.topAnchor),
      accountContextLabel.leadingAnchor.constraint(equalTo: contextTapArea.leadingAnchor),
      accountContextLabel.bottomAnchor.constraint(equalTo: contextTapArea.bottomAnchor),

      accountContextChevron.centerYAnchor.constraint(equalTo: accountContextLabel.centerYAnchor),
      accountContextChevron.leadingAnchor.constraint(equalTo: accountContextLabel.trailingAnchor, constant: Metrics.spacing1),
      accountContextChevron.widthAnchor.constraint(equalToConstant: 10),
      accountContextChevron.heightAnchor.constraint(equalToConstant: 10),
      accountContextChevron.trailingAnchor.constraint(equalTo: contextTapArea.trailingAnchor),

      notificationButton.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
      notificationButton.trailingAnchor.constraint(
        equalTo: headerItemsView.layoutMarginsGuide.trailingAnchor),
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
        equalTo: monthSelectorView.leadingAnchor),
      monthSelectorShimmerView.trailingAnchor.constraint(
        equalTo: monthSelectorView.trailingAnchor),
      monthSelectorShimmerView.heightAnchor.constraint(equalToConstant: Metrics.spacing8),

      monthCardShimmerView.topAnchor.constraint(
        equalTo: monthSelectorView.bottomAnchor, constant: Metrics.spacing5),
      monthCardShimmerView.leadingAnchor.constraint(
        equalTo: monthSelectorView.leadingAnchor),
      monthCardShimmerView.trailingAnchor.constraint(
        equalTo: monthSelectorView.trailingAnchor),
      monthCardShimmerView.heightAnchor.constraint(equalToConstant: Metrics.monthCardShimmerHeight),

      transactionsTableShimmerView.topAnchor.constraint(
        equalTo: monthCardShimmerView.bottomAnchor, constant: Metrics.spacing4),
      transactionsTableShimmerView.leadingAnchor.constraint(
        equalTo: monthSelectorView.leadingAnchor),
      transactionsTableShimmerView.trailingAnchor.constraint(
        equalTo: monthSelectorView.trailingAnchor),
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

    // Set up the month carousel height constraint with lower priority
    // since we also have top and bottom constraints
    monthCarouselHeightConstraint = monthCarousel.heightAnchor.constraint(equalToConstant: 500)
    monthCarouselHeightConstraint?.priority = .defaultHigh
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

  /// Updates the notification badge visibility and count
  func updateNotificationBadge(count: Int) {
    notificationBadge.isHidden = count == 0
    notificationBadgeLabel.text = count > 99 ? "99+" : "\(count)"
  }

  private func setupProfileTapGesture() {
    profileTapButton.addTarget(self, action: #selector(handleProfileTap), for: .touchUpInside)
  }

  private func setupContextTapGesture() {
    let tapGesture = UITapGestureRecognizer(
      target: self, action: #selector(handleContextTap))
    contextTapArea.addGestureRecognizer(tapGesture)
  }

  @objc private func handleContextTap() {
    if currentHasGroups {
      delegate?.didTapContextSwitch()
    } else {
      delegate?.didTapProfile()
    }
  }

  private var currentHasGroups: Bool = false

  func configureContextChip(currentContext: DataContext, hasGroups: Bool) {
    currentHasGroups = hasGroups

    if hasGroups {
      accountContextChevron.image = UIImage(
        systemName: "chevron.down",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
    } else {
      accountContextChevron.image = UIImage(
        systemName: "chevron.right",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
    }

    switch currentContext {
    case .personal:
      accountContextLabel.text = hasGroups
        ? "dashboard.context.personal".localized
        : "dashboard.context.label".localized
    case .group(let group):
      accountContextLabel.text = group.name
    }
  }

  @objc
  private func handleProfileTap() {
    delegate?.didTapProfile()
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
