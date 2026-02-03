//
//  TransactionDetailsView.swift
//  Finova
//
//  Created by Arthur Rios on 05/09/25.
//

import Foundation
import UIKit

protocol TransactionDetailsViewDelegate: AnyObject {
  func didTapEdit()
  func didTapDelete()
  func didTapBack()
  func didTapDeleteInstallment(_ transaction: Transaction)
}

final class TransactionDetailsView: UIView {
  weak var delegate: TransactionDetailsViewDelegate?

  // MARK: - UI Components
  private lazy var scrollView: UIScrollView = {
    let scrollView = UIScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.showsVerticalScrollIndicator = false
    return scrollView
  }()

  private lazy var contentView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  // MARK: - Header (Same as Budgets)
  private let headerContainerView: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray100
    view.translatesAutoresizingMaskIntoConstraints = false
    view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight).isActive = true
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

  lazy var headerTextStackView = UIStackView(
    axis: .vertical, spacing: Metrics.spacing1,
    arrangedSubviews: [headerTitleLabel, headerSubtitleLabel])

  private let headerTitleLabel: UILabel = {
    let label = UILabel()
    label.fontStyle = Fonts.titleSM
    label.text = "transactionDetails.header.title".localized
    label.applyStyle()
    label.textColor = Colors.gray700
    label.textAlignment = .left
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let headerSubtitleLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textSM.font
    label.textColor = Colors.gray500
    label.text = "transactionDetails.header.subtitle".localized
    label.textAlignment = .left
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  // MARK: - Transaction Info Section
  private let transactionInfoHeaderView = CardHeader(
    headerTitle: "transactionDetails.info.header.title".localized)

  private lazy var transactionInfoContentView: UIStackView = {
    let stackView = UIStackView(
      axis: .vertical, spacing: Metrics.spacing4,
      arrangedSubviews: [
        categoryAndAmountView, transactionTitleLabel, transactionModeLabel,
      ])
    stackView.layoutMargins = UIEdgeInsets(
      top: Metrics.spacing5, left: Metrics.spacing5, bottom: Metrics.spacing5,
      right: Metrics.spacing5)
    stackView.isLayoutMarginsRelativeArrangement = true
    stackView.distribution = .fill
    stackView.backgroundColor = Colors.gray100
    stackView.layer.borderWidth = 1
    stackView.layer.borderColor = Colors.gray300.cgColor
    stackView.layer.cornerRadius = CornerRadius.extraLarge
    stackView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    stackView.clipsToBounds = true
    stackView.translatesAutoresizingMaskIntoConstraints = false
    return stackView
  }()

  private lazy var categoryAndAmountView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(iconContainerView)
    view.addSubview(titleStackView)
    view.addSubview(amountRowStackView)

    NSLayoutConstraint.activate([
      iconContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      iconContainerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

      titleStackView.leadingAnchor.constraint(
        equalTo: iconContainerView.trailingAnchor, constant: Metrics.spacing3),
      titleStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

      amountRowStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      amountRowStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      amountRowStackView.leadingAnchor.constraint(
        greaterThanOrEqualTo: titleStackView.trailingAnchor, constant: Metrics.spacing3),

      view.heightAnchor.constraint(equalToConstant: Metrics.spacing8),
    ])

    return view
  }()

  // Icon styling exactly like transaction table cells
  private let iconContainerView: UIView = {
    let view = UIView()
    view.layer.cornerRadius = CornerRadius.medium
    view.backgroundColor = Colors.gray200
    view.layer.borderColor = Colors.gray300.cgColor
    view.layer.borderWidth = 1
    view.layer.masksToBounds = true
    view.heightAnchor.constraint(equalToConstant: Metrics.spacing8).isActive = true
    view.widthAnchor.constraint(equalToConstant: Metrics.spacing8).isActive = true
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let categoryIconView: UIImageView = {
    let imageView = UIImageView()
    imageView.tintColor = Colors.mainMagenta
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false
    return imageView
  }()

  private let titleStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.axis = .vertical
    stackView.spacing = Metrics.spacing1
    stackView.translatesAutoresizingMaskIntoConstraints = false
    return stackView
  }()

  private lazy var categoryLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textSMBold.font
    label.textColor = Colors.gray700
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let amountStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.axis = .vertical
    stackView.alignment = .trailing
    stackView.spacing = 2
    stackView.translatesAutoresizingMaskIntoConstraints = false
    return stackView
  }()

  private let amountRowStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.axis = .horizontal
    stackView.alignment = .center
    stackView.spacing = Metrics.spacing1
    stackView.translatesAutoresizingMaskIntoConstraints = false
    return stackView
  }()

  private lazy var amountLabel: UILabel = {
    let label = UILabel()
    label.textAlignment = .right
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let transactionTypeIconView: UIImageView = {
    let imageView = UIImageView()
    imageView.heightAnchor.constraint(equalToConstant: 14).isActive = true
    imageView.widthAnchor.constraint(equalToConstant: 14).isActive = true
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false
    return imageView
  }()

  private lazy var installmentInfoLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray500
    label.textAlignment = .right
    label.isHidden = true
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private lazy var transactionTitleLabel: UILabel = {
    let label = UILabel()
    label.fontStyle = Fonts.titleMD
    label.textColor = Colors.gray700
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private lazy var transactionModeLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textSM.font
    label.textColor = Colors.gray500
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  // MARK: - Transaction Details Section
  private let transactionDetailsHeaderView = CardHeader(
    headerTitle: "transactionDetails.details.header.title".localized)

  private lazy var transactionDetailsContentView: UIStackView = {
    let stackView = UIStackView(axis: .vertical, spacing: Metrics.spacing4)
    stackView.layoutMargins = UIEdgeInsets(
      top: Metrics.spacing5, left: Metrics.spacing5, bottom: Metrics.spacing5,
      right: Metrics.spacing5)
    stackView.isLayoutMarginsRelativeArrangement = true
    stackView.distribution = .fill
    stackView.backgroundColor = Colors.gray100
    stackView.layer.borderWidth = 1
    stackView.layer.borderColor = Colors.gray300.cgColor
    stackView.layer.cornerRadius = CornerRadius.extraLarge
    stackView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    stackView.clipsToBounds = true
    stackView.translatesAutoresizingMaskIntoConstraints = false
    return stackView
  }()

  private var dateValueLabel: UILabel!
  private var typeValueLabel: UILabel!
  private var createdAtValueLabel: UILabel!
  private var updatedAtValueLabel: UILabel!
  private var totalValueLabel: UILabel!
  private var lastInstallmentDateLabel: UILabel!

  // MARK: - Installments Section (for installment transactions)
  private let installmentsHeaderView = CardHeader(
    headerTitle: "transactionDetails.installments.header.title".localized)

  private lazy var installmentsTableView: UITableView = {
    let tableView = UITableView()
    tableView.backgroundColor = Colors.gray100
    tableView.layer.cornerRadius = CornerRadius.extraLarge
    tableView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    tableView.layer.borderWidth = 1
    tableView.layer.borderColor = Colors.gray300.cgColor
    tableView.separatorStyle = .singleLine
    tableView.separatorInset = UIEdgeInsets.zero
    tableView.clipsToBounds = true
    tableView.separatorColor = Colors.gray300
    tableView.isScrollEnabled = false
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.register(TransactionCell.self, forCellReuseIdentifier: TransactionCell.reuseID)
    tableView.dataSource = self
    tableView.delegate = self
    return tableView
  }()

  private var installmentsTableHeightConstraint: NSLayoutConstraint?
  private var contentBottomConstraint: NSLayoutConstraint?
  private var installmentTransactions: [Transaction] = []

  // MARK: - Action Buttons (Bottom)
  private lazy var actionButtonsContainerView: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray100
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var footerBorderView: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray300
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var actionButtonsStackView: UIStackView = {
    let stackView = UIStackView(
      axis: .vertical,
      spacing: Metrics.spacing3,
      arrangedSubviews: [editButton, deleteButton]
    )
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: Metrics.spacing4, leading: Metrics.spacing4, bottom: Metrics.spacing4,
      trailing: Metrics.spacing4)
    stackView.isLayoutMarginsRelativeArrangement = true
    return stackView
  }()

  private lazy var editButton = Button(
    variant: .base,
    label: "transactionDetails.button.edit".localized
  )

  private lazy var deleteButton = Button(
    variant: .outlined,
    label: "transactionDetails.button.delete".localized
  )

  // MARK: - Initialization
  override init(frame: CGRect) {
    super.init(frame: frame)
    setupViews()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupViews() {
    backgroundColor = Colors.gray200

    // Setup hierarchy (following budgets pattern)
    addSubview(headerContainerView)
    headerContainerView.addSubview(headerItemsView)
    headerItemsView.addSubview(backButtonGlassContainer)
    backButtonGlassContainer.addSubview(backButton)
    setupBackButtonGlassEffect()
    headerItemsView.addSubview(headerTextStackView)

    addSubview(scrollView)
    scrollView.addSubview(contentView)

    // Add transaction info section
    contentView.addSubview(transactionInfoHeaderView)
    contentView.addSubview(transactionInfoContentView)

    // Setup icon container and title stack
    iconContainerView.addSubview(categoryIconView)
    titleStackView.addArrangedSubview(categoryLabel)

    // Setup amount stack with proper hierarchy to match TransactionCell exactly
    amountRowStackView.addArrangedSubview(amountStackView)
    amountRowStackView.addArrangedSubview(transactionTypeIconView)
    amountStackView.addArrangedSubview(amountLabel)
    amountStackView.addArrangedSubview(installmentInfoLabel)

    NSLayoutConstraint.activate([
      categoryIconView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
      categoryIconView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
    ])

    // Add transaction details section
    contentView.addSubview(transactionDetailsHeaderView)
    contentView.addSubview(transactionDetailsContentView)

    // Add installments section (will be hidden by default)
    contentView.addSubview(installmentsHeaderView)
    // TODO: Commented out installments table for now
    // contentView.addSubview(installmentsTableView)
    installmentsHeaderView.isHidden = true
    // installmentsTableView.isHidden = true

    // Add action buttons at bottom with gradient overlay
    addSubview(actionButtonsContainerView)
    actionButtonsContainerView.addSubview(footerBorderView)
    actionButtonsContainerView.addSubview(actionButtonsStackView)

    // Setup actions
    backButtonGlassContainer.addGestureRecognizer(
      UITapGestureRecognizer(target: self, action: #selector(didTapBack)))
    backButton.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)
    editButton.addTarget(self, action: #selector(didTapEdit), for: .touchUpInside)
    deleteButton.addTarget(self, action: #selector(didTapDelete), for: .touchUpInside)

    setupConstraints()
  }

  private func setupConstraints() {
    // Set content priorities to match TransactionCell behavior
    amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    amountLabel.setContentHuggingPriority(.required, for: .horizontal)
    amountRowStackView.setContentCompressionResistancePriority(.required, for: .horizontal)
    amountRowStackView.setContentHuggingPriority(.required, for: .horizontal)
    amountStackView.setContentCompressionResistancePriority(.required, for: .horizontal)
    amountStackView.setContentHuggingPriority(.required, for: .horizontal)
    installmentInfoLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    installmentInfoLabel.setContentHuggingPriority(.required, for: .horizontal)
    transactionTypeIconView.setContentCompressionResistancePriority(.required, for: .horizontal)
    transactionTypeIconView.setContentHuggingPriority(.required, for: .horizontal)

    NSLayoutConstraint.activate([
      // Header (same as budgets)
      headerContainerView.topAnchor.constraint(equalTo: topAnchor),
      headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

      headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
      headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
      headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

      backButtonGlassContainer.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
      backButtonGlassContainer.leadingAnchor.constraint(
        equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
      backButtonGlassContainer.widthAnchor.constraint(equalToConstant: 36),
      backButtonGlassContainer.heightAnchor.constraint(equalToConstant: 36),

      backButton.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
      backButton.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
      backButton.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
      backButton.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),

      headerTextStackView.leadingAnchor.constraint(
        equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
      headerTextStackView.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),

      // Scroll view
      scrollView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: actionButtonsContainerView.topAnchor),

      // Content view
      contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
      contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
      contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
      contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

      // Transaction info section
      transactionInfoHeaderView.topAnchor.constraint(
        equalTo: contentView.topAnchor, constant: Metrics.spacing4),
      transactionInfoHeaderView.leadingAnchor.constraint(
        equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
      transactionInfoHeaderView.trailingAnchor.constraint(
        equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),

      transactionInfoContentView.topAnchor.constraint(
        equalTo: transactionInfoHeaderView.bottomAnchor),
      transactionInfoContentView.leadingAnchor.constraint(
        equalTo: transactionInfoHeaderView.leadingAnchor),
      transactionInfoContentView.trailingAnchor.constraint(
        equalTo: transactionInfoHeaderView.trailingAnchor),

      // Transaction details section
      transactionDetailsHeaderView.topAnchor.constraint(
        equalTo: transactionInfoContentView.bottomAnchor, constant: Metrics.spacing6),
      transactionDetailsHeaderView.leadingAnchor.constraint(
        equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
      transactionDetailsHeaderView.trailingAnchor.constraint(
        equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),

      transactionDetailsContentView.topAnchor.constraint(
        equalTo: transactionDetailsHeaderView.bottomAnchor),
      transactionDetailsContentView.leadingAnchor.constraint(
        equalTo: transactionDetailsHeaderView.leadingAnchor),
      transactionDetailsContentView.trailingAnchor.constraint(
        equalTo: transactionDetailsHeaderView.trailingAnchor),

      // Installments section
      installmentsHeaderView.topAnchor.constraint(
        equalTo: transactionDetailsContentView.bottomAnchor, constant: Metrics.spacing6),
      installmentsHeaderView.leadingAnchor.constraint(
        equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
      installmentsHeaderView.trailingAnchor.constraint(
        equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),

      // TODO: Commented out installments table constraints for now
      // installmentsTableView.topAnchor.constraint(equalTo: installmentsHeaderView.bottomAnchor),
      // installmentsTableView.leadingAnchor.constraint(equalTo: installmentsHeaderView.leadingAnchor),
      // installmentsTableView.trailingAnchor.constraint(
      //   equalTo: installmentsHeaderView.trailingAnchor),
    ])

    // Set up dynamic bottom constraint
    contentBottomConstraint = transactionDetailsContentView.bottomAnchor.constraint(
      equalTo: contentView.bottomAnchor, constant: -Metrics.spacing4)
    contentBottomConstraint?.isActive = true

    // TODO: Commented out installments table height constraint for now
    // installmentsTableHeightConstraint = installmentsTableView.heightAnchor.constraint(
    //   equalToConstant: 0)

    NSLayoutConstraint.activate([
      // Action buttons container at bottom
      // Action buttons container - extend to bottom of screen
      actionButtonsContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      actionButtonsContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
      actionButtonsContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),

      // Footer border (top border like header has bottom border)
      footerBorderView.topAnchor.constraint(equalTo: actionButtonsContainerView.topAnchor),
      footerBorderView.leadingAnchor.constraint(equalTo: actionButtonsContainerView.leadingAnchor),
      footerBorderView.trailingAnchor.constraint(equalTo: actionButtonsContainerView.trailingAnchor),
      footerBorderView.heightAnchor.constraint(equalToConstant: 1),

      // Action buttons stack view - bottom respects safe area
      actionButtonsStackView.topAnchor.constraint(equalTo: footerBorderView.bottomAnchor),
      actionButtonsStackView.leadingAnchor.constraint(
        equalTo: actionButtonsContainerView.leadingAnchor),
      actionButtonsStackView.trailingAnchor.constraint(
        equalTo: actionButtonsContainerView.trailingAnchor),
      actionButtonsStackView.bottomAnchor.constraint(
        equalTo: safeAreaLayoutGuide.bottomAnchor),
    ])
  }

  private func setupBackButtonGlassEffect() {
    if #available(iOS 26.0, *) {
      let glassEffect = UIGlassEffect()
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

  private func createDetailRow(
    title: String, value: String, isDate: Bool = false, isCreatedAt: Bool = false,
    isUpdatedAt: Bool = false, isTotalValue: Bool = false, isLastInstallmentDate: Bool = false
  ) -> UIView {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let titleLabel = UILabel()
    titleLabel.text = title
    titleLabel.font = Fonts.textSM.font
    titleLabel.textColor = Colors.gray600
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    let valueLabel = UILabel()
    valueLabel.text = value
    valueLabel.font = Fonts.textSM.font
    valueLabel.textColor = Colors.gray700
    valueLabel.textAlignment = .right
    valueLabel.translatesAutoresizingMaskIntoConstraints = false

    // Store references to update later
    if isDate {
      dateValueLabel = valueLabel
    } else if isCreatedAt {
      createdAtValueLabel = valueLabel
    } else if isUpdatedAt {
      updatedAtValueLabel = valueLabel
    } else if isTotalValue {
      totalValueLabel = valueLabel
    } else if isLastInstallmentDate {
      lastInstallmentDateLabel = valueLabel
    } else {
      typeValueLabel = valueLabel
    }

    container.addSubview(titleLabel)
    container.addSubview(valueLabel)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      valueLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: Metrics.spacing3),

      container.heightAnchor.constraint(equalToConstant: 24),
    ])

    return container
  }

  private func setupTransactionDetailsContent(with viewModel: TransactionDetailsViewModel) {
    // Clear existing arranged subviews
    transactionDetailsContentView.arrangedSubviews.forEach { $0.removeFromSuperview() }

    // Add basic detail rows
    transactionDetailsContentView.addArrangedSubview(
      createDetailRow(title: "transactionDetails.label.date".localized, value: "", isDate: true))
    transactionDetailsContentView.addArrangedSubview(
      createDetailRow(title: "transactionDetails.label.type".localized, value: ""))

    // Add installment-specific rows if this is an installment transaction
    if viewModel.transaction.mode == .installments {
      transactionDetailsContentView.addArrangedSubview(
        createDetailRow(
          title: "transactionDetails.label.totalValue".localized, value: "", isTotalValue: true))
      transactionDetailsContentView.addArrangedSubview(
        createDetailRow(
          title: "transactionDetails.label.lastInstallmentDate".localized, value: "",
          isLastInstallmentDate: true))
    }

    // Add standard rows
    // Removed createdAt and updatedAt fields as requested
  }

  // MARK: - Configuration
  func configure(with viewModel: TransactionDetailsViewModel) {
    // Remove amount from header subtitle - just use default subtitle
    headerSubtitleLabel.text = "transactionDetails.header.subtitle".localized

    // Configure main info with transaction table cell styling
    let iconName = viewModel.transaction.category.iconName(for: viewModel.transaction.type)
    categoryIconView.image = UIImage(named: iconName)

    categoryLabel.text = viewModel.getCategoryDisplayName()

    // Configure amount with currency attributed string (bold) like table cells
    let symbolFont = Fonts.textXS.font
    amountLabel.attributedText = viewModel.transaction.amount.currencyAttributedString(
      symbolFont: symbolFont, font: Fonts.titleMD)
    amountLabel.accessibilityLabel = viewModel.getFormattedAmount()

    // Configure transaction type icon like table cells
    if viewModel.transaction.type == .income {
      transactionTypeIconView.image = UIImage(named: "arrowUp")
      transactionTypeIconView.tintColor = Colors.mainGreen
    } else {
      transactionTypeIconView.image = UIImage(named: "arrowDown")
      transactionTypeIconView.tintColor = Colors.mainRed
    }

    transactionTitleLabel.text = viewModel.transaction.title

    // Show mode description (just "Installment" for installments, not "Installment 1 of 2")
    switch viewModel.transaction.mode {
    case .normal:
      transactionModeLabel.text = "transaction.mode.normal".localized
    case .recurring:
      transactionModeLabel.text = "transaction.mode.recurring".localized
    case .installments:
      transactionModeLabel.text = "transaction.mode.installments".localized
    }

    // Show installment info under the amount (using same format as table cells)
    if viewModel.transaction.mode == .installments,
      let installmentNumber = viewModel.transaction.installmentNumber,
      let totalInstallments = viewModel.transaction.totalInstallments
    {
      installmentInfoLabel.text = "(\(installmentNumber)/\(totalInstallments))"
      installmentInfoLabel.isHidden = false
    } else {
      installmentInfoLabel.isHidden = true
    }

    // Setup transaction details content dynamically
    setupTransactionDetailsContent(with: viewModel)

    // Configure details
    dateValueLabel.text = viewModel.getFormattedDate()
    typeValueLabel.text =
      viewModel.transaction.type == .income
      ? "transactionDetails.type.income".localized : "transactionDetails.type.expense".localized

    // Configure installment-specific details
    if viewModel.transaction.mode == .installments {
      let relatedInstallments = viewModel.getRelatedInstallments()
      if !relatedInstallments.isEmpty {
        // Calculate total value from all installments
        let totalValue = relatedInstallments.reduce(0) { $0 + $1.amount }
        totalValueLabel.text = totalValue.currencyString

        // Get last installment date
        let lastInstallment = relatedInstallments.max { $0.date < $1.date }
        lastInstallmentDateLabel.text =
          lastInstallment.map { DateFormatter.fullDateFormatter.string(from: $0.date) } ?? "N/A"
      } else {
        totalValueLabel.text = "N/A"
        lastInstallmentDateLabel.text = "N/A"
      }
    }

    // Format created at date (assuming this represents creation timestamp)
    // Removed createdAt field as requested

    // Set updated at to current time (as placeholder - would be from actual update timestamp in real app)
    // Removed updatedAt field as requested

    // TODO: Commented out installments section for now
    // Show installments section if this is an installment transaction
    // if viewModel.transaction.mode == .installments {
    //   // Load related installments
    //   installmentTransactions = viewModel.getRelatedInstallments()

    //   if !installmentTransactions.isEmpty {
    //     installmentsHeaderView.isHidden = false
    //     installmentsTableView.isHidden = false

    //     // Update constraints to include installments section
    //     contentBottomConstraint?.isActive = false
    //     contentBottomConstraint = installmentsTableView.bottomAnchor.constraint(
    //       equalTo: contentView.bottomAnchor, constant: -Metrics.spacing4)
    //     contentBottomConstraint?.isActive = true

    //     // Calculate table height based on number of installments (including separators)
    //     let cellHeight: CGFloat = 67  // Same as transaction table
    //     let separatorHeight = CGFloat(max(0, installmentTransactions.count - 1)) * 1.0
    //     let totalHeight = CGFloat(installmentTransactions.count) * cellHeight + separatorHeight
    //     installmentsTableHeightConstraint?.constant = totalHeight
    //     installmentsTableHeightConstraint?.isActive = true

    //     // Reload table data
    //     installmentsTableView.reloadData()
    //   } else {
    //     // No related installments found, hide section
    //     installmentsHeaderView.isHidden = true
    //     installmentsTableView.isHidden = true

    //     contentBottomConstraint?.isActive = false
    //     contentBottomConstraint = transactionDetailsContentView.bottomAnchor.constraint(
    //       equalTo: contentView.bottomAnchor, constant: -Metrics.spacing4)
    //     contentBottomConstraint?.isActive = true

    //     installmentsTableHeightConstraint?.isActive = false
    //   }
    // } else {
    //   installmentsHeaderView.isHidden = true
    //   installmentsTableView.isHidden = true

    //   // Update constraints to exclude installments section
    //   contentBottomConstraint?.isActive = false
    //   contentBottomConstraint = transactionDetailsContentView.bottomAnchor.constraint(
    //     equalTo: contentView.bottomAnchor, constant: -Metrics.spacing4)
    //   contentBottomConstraint?.isActive = true

    //   installmentsTableHeightConstraint?.isActive = false
    // }

    // Always hide installments section for now
    installmentsHeaderView.isHidden = true
  }

  // MARK: - Actions
  @objc private func didTapEdit() {
    delegate?.didTapEdit()
  }

  @objc private func didTapDelete() {
    delegate?.didTapDelete()
  }

  @objc private func didTapBack() {
    delegate?.didTapBack()
  }
}

// MARK: - UITableViewDataSource & UITableViewDelegate
extension TransactionDetailsView: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return installmentTransactions.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell =
      tableView.dequeueReusableCell(withIdentifier: TransactionCell.reuseID, for: indexPath)
      as! TransactionCell

    let transaction = installmentTransactions[indexPath.row]

    let configuration = TransactionCellConfiguration(
      category: transaction.category,
      title: transaction.title,
      date: transaction.date,
      value: transaction.amount,
      transactionType: transaction.type,
      transactionMode: transaction.mode,
      installmentNumber: transaction.installmentNumber,
      totalInstallments: transaction.totalInstallments
    )

    cell.configure(with: configuration)

    // Add delete action for each installment
    cell.onDelete = { [weak self] completion in
      self?.delegate?.didTapDeleteInstallment(transaction)
      completion(false)  // Let the delegate handle the deletion
    }

    return cell
  }

  func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    return 67  // Same height as transaction table cells
  }
}
