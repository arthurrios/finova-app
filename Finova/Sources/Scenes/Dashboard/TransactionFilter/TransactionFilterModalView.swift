//
//  TransactionFilterModalView.swift
//  FinanceApp
//
//  Created by Arthur Rios on 26/01/26.
//

import Foundation
import UIKit

protocol TransactionFilterModalViewDelegate: AnyObject {
  func didTapClose()
  func didTapApply(filters: TransactionFilters)
  func didTapClear()
}

class TransactionFilterModalView: UIView {
  weak var delegate: TransactionFilterModalViewDelegate?
  
  private var selectedCategories: Set<TransactionCategory> = []
  private var selectedTypes: Set<TransactionType> = []
  private var selectedModes: Set<TransactionMode> = []
  
  // MARK: - UI Components
  
  private lazy var headerStackView = UIStackView(
    axis: .horizontal, alignment: .center, arrangedSubviews: [headerTitleLabel, closeIconButton])
  
  private let headerTitleLabel: UILabel = {
    let label = UILabel()
    label.fontStyle = Fonts.titleXS
    label.textColor = Colors.gray700
    label.text = "filter.title".localized
    label.applyStyle()
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()
  
  private let closeIconButton: UIButton = {
    let button = UIButton(type: .custom)
    button.setImage(UIImage(named: "x"), for: .normal)
    button.tintColor = Colors.gray500
    button.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: 20),
      button.heightAnchor.constraint(equalToConstant: 20),
    ])

    return button
  }()
  
  private let scrollView: UIScrollView = {
    let scrollView = UIScrollView()
    scrollView.showsVerticalScrollIndicator = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    return scrollView
  }()
  
  private let contentStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.axis = .vertical
    stackView.spacing = Metrics.spacing5
    stackView.layoutMargins = UIEdgeInsets(
      top: Metrics.spacing3, left: Metrics.spacing8, bottom: Metrics.spacing5, right: Metrics.spacing8)
    stackView.isLayoutMarginsRelativeArrangement = true
    stackView.translatesAutoresizingMaskIntoConstraints = false
    return stackView
  }()
  
  // Type Section
  private lazy var typeSectionView = createSectionView(title: "filter.type.title".localized)
  private lazy var typeChipsContainer: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()
  
  // Mode Section
  private lazy var modeSectionView = createSectionView(title: "filter.mode.title".localized)
  private lazy var modeChipsContainer: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()
  
  // Category Section
  private lazy var categorySectionView = createSectionView(title: "filter.category.title".localized)
  private lazy var categoryChipsContainer: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()
  
  // Buttons
  private let buttonStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.axis = .horizontal
    stackView.spacing = Metrics.spacing3
    stackView.distribution = .fillEqually
    stackView.layoutMargins = UIEdgeInsets(
      top: Metrics.spacing4, left: Metrics.spacing8, bottom: Metrics.spacing6, right: Metrics.spacing8)
    stackView.isLayoutMarginsRelativeArrangement = true
    stackView.translatesAutoresizingMaskIntoConstraints = false
    return stackView
  }()
  
  private let footerShadowLayer: CAGradientLayer = {
    let layer = CAGradientLayer()
    layer.colors = [
      UIColor.black.withAlphaComponent(0.0).cgColor,
      UIColor.black.withAlphaComponent(0.1).cgColor
    ]
    layer.startPoint = CGPoint(x: 0.5, y: 0.0)
    layer.endPoint = CGPoint(x: 0.5, y: 1.0)
    return layer
  }()
  
  private lazy var clearButton: Button = {
    let button = Button(variant: .outlined, label: "filter.clear".localized)
    button.addTarget(self, action: #selector(clearButtonTapped), for: .touchUpInside)
    return button
  }()
  
  private lazy var applyButton: Button = {
    let button = Button(variant: .base, label: "filter.apply".localized)
    button.addTarget(self, action: #selector(applyButtonTapped), for: .touchUpInside)
    return button
  }()
  
  // MARK: - Chip Storage
  private var typeChips: [TransactionType: UIButton] = [:]
  private var modeChips: [TransactionMode: UIButton] = [:]
  private var categoryChips: [TransactionCategory: UIButton] = [:]
  
  // MARK: - Initialization
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    setupViews()
    setupChips()
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    updateFooterShadow()
  }
  
  private func updateFooterShadow() {
    let shadowHeight: CGFloat = 20
    footerShadowLayer.frame = CGRect(
      x: 0,
      y: buttonStackView.frame.minY - shadowHeight,
      width: bounds.width,
      height: shadowHeight
    )
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  // MARK: - Setup
  
  private func setupViews() {
    backgroundColor = Colors.gray100
    layer.cornerRadius = CornerRadius.bottomSheet
    layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    
    addSubview(headerStackView)
    
    addSubview(scrollView)
    scrollView.addSubview(contentStackView)
    
    contentStackView.addArrangedSubview(typeSectionView)
    contentStackView.addArrangedSubview(modeSectionView)
    contentStackView.addArrangedSubview(categorySectionView)
    
    addSubview(buttonStackView)
    buttonStackView.addArrangedSubview(clearButton)
    buttonStackView.addArrangedSubview(applyButton)
    
    // Add shadow layer to footer
    layer.insertSublayer(footerShadowLayer, at: 0)
    
    closeIconButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
    
    setupConstraints()
  }
  
  private func setupConstraints() {
    NSLayoutConstraint.activate([
      headerStackView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: Metrics.spacing10),
      headerStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing8),
      headerStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing8),
      
      scrollView.topAnchor.constraint(equalTo: headerStackView.bottomAnchor, constant: Metrics.spacing7),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: buttonStackView.topAnchor),
      
      contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
      contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
      contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
      contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
      
      buttonStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
      buttonStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
      buttonStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
    ])
  }
  
  private func createSectionView(title: String) -> UIStackView {
    let stackView = UIStackView()
    stackView.axis = .vertical
    stackView.spacing = Metrics.spacing3
    stackView.translatesAutoresizingMaskIntoConstraints = false
    
    let titleLabel = UILabel()
    titleLabel.font = Fonts.title2XS.font
    titleLabel.textColor = Colors.gray600
    titleLabel.text = title
    
    stackView.addArrangedSubview(titleLabel)
    
    return stackView
  }
  
  private func setupChips() {
    // Type chips
    let typeFlowLayout = FlowLayoutView()
    typeFlowLayout.spacing = Metrics.spacing2
    typeFlowLayout.translatesAutoresizingMaskIntoConstraints = false
    
    for type in TransactionType.allCases {
      let chip = createChip(title: type == .income ? "addTransactionModal.income".localized : "addTransactionModal.expense".localized)
      chip.addTarget(self, action: #selector(typeChipTapped(_:)), for: .touchUpInside)
      typeChips[type] = chip
      typeFlowLayout.addArrangedSubview(chip)
    }
    typeSectionView.addArrangedSubview(typeFlowLayout)
    
    // Mode chips
    let modeFlowLayout = FlowLayoutView()
    modeFlowLayout.spacing = Metrics.spacing2
    modeFlowLayout.translatesAutoresizingMaskIntoConstraints = false
    
    for mode in TransactionMode.allCases {
      let chip = createChip(title: mode.title)
      chip.addTarget(self, action: #selector(modeChipTapped(_:)), for: .touchUpInside)
      modeChips[mode] = chip
      modeFlowLayout.addArrangedSubview(chip)
    }
    modeSectionView.addArrangedSubview(modeFlowLayout)
    
    // Category chips
    let categoryFlowLayout = FlowLayoutView()
    categoryFlowLayout.spacing = Metrics.spacing2
    categoryFlowLayout.translatesAutoresizingMaskIntoConstraints = false
    
    for category in TransactionCategory.allCases {
      let chip = createChip(title: category.description)
      chip.addTarget(self, action: #selector(categoryChipTapped(_:)), for: .touchUpInside)
      categoryChips[category] = chip
      categoryFlowLayout.addArrangedSubview(chip)
    }
    categorySectionView.addArrangedSubview(categoryFlowLayout)
  }
  
  private func createChip(title: String) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = Fonts.textXS.font
    button.setTitleColor(Colors.gray600, for: .normal)
    button.backgroundColor = Colors.gray200
    button.layer.cornerRadius = 16
    button.layer.borderWidth = 1
    button.layer.borderColor = Colors.gray300.cgColor
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }
  
  private func updateChipAppearance(_ chip: UIButton, isSelected: Bool) {
    if isSelected {
      chip.backgroundColor = Colors.mainMagenta
      chip.setTitleColor(Colors.gray100, for: .normal)
      chip.layer.borderWidth = 0
    } else {
      chip.backgroundColor = Colors.gray200
      chip.setTitleColor(Colors.gray600, for: .normal)
      chip.layer.borderWidth = 1
      chip.layer.borderColor = Colors.gray300.cgColor
    }
  }
  
  // MARK: - Actions
  
  @objc private func closeButtonTapped() {
    delegate?.didTapClose()
  }
  
  @objc private func clearButtonTapped() {
    selectedCategories.removeAll()
    selectedTypes.removeAll()
    selectedModes.removeAll()
    
    typeChips.values.forEach { updateChipAppearance($0, isSelected: false) }
    modeChips.values.forEach { updateChipAppearance($0, isSelected: false) }
    categoryChips.values.forEach { updateChipAppearance($0, isSelected: false) }
    
    delegate?.didTapClear()
  }
  
  @objc private func applyButtonTapped() {
    let filters = TransactionFilters(
      categories: selectedCategories,
      types: selectedTypes,
      modes: selectedModes
    )
    delegate?.didTapApply(filters: filters)
  }
  
  @objc private func typeChipTapped(_ sender: UIButton) {
    guard let type = typeChips.first(where: { $0.value == sender })?.key else { return }
    
    if selectedTypes.contains(type) {
      selectedTypes.remove(type)
      updateChipAppearance(sender, isSelected: false)
    } else {
      selectedTypes.insert(type)
      updateChipAppearance(sender, isSelected: true)
    }
  }
  
  @objc private func modeChipTapped(_ sender: UIButton) {
    guard let mode = modeChips.first(where: { $0.value == sender })?.key else { return }
    
    if selectedModes.contains(mode) {
      selectedModes.remove(mode)
      updateChipAppearance(sender, isSelected: false)
    } else {
      selectedModes.insert(mode)
      updateChipAppearance(sender, isSelected: true)
    }
  }
  
  @objc private func categoryChipTapped(_ sender: UIButton) {
    guard let category = categoryChips.first(where: { $0.value == sender })?.key else { return }
    
    if selectedCategories.contains(category) {
      selectedCategories.remove(category)
      updateChipAppearance(sender, isSelected: false)
    } else {
      selectedCategories.insert(category)
      updateChipAppearance(sender, isSelected: true)
    }
  }
  
  // MARK: - Configuration
  
  func configure(with filters: TransactionFilters) {
    selectedCategories = filters.categories
    selectedTypes = filters.types
    selectedModes = filters.modes
    
    // Update chip appearances
    for (type, chip) in typeChips {
      updateChipAppearance(chip, isSelected: selectedTypes.contains(type))
    }
    
    for (mode, chip) in modeChips {
      updateChipAppearance(chip, isSelected: selectedModes.contains(mode))
    }
    
    for (category, chip) in categoryChips {
      updateChipAppearance(chip, isSelected: selectedCategories.contains(category))
    }
  }
}

// MARK: - Flow Layout View (for wrapping chips)
class FlowLayoutView: UIView {
  var spacing: CGFloat = 8
  private var arrangedSubviews: [UIView] = []
  
  func addArrangedSubview(_ view: UIView) {
    arrangedSubviews.append(view)
    addSubview(view)
    setNeedsLayout()
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    
    var currentX: CGFloat = 0
    var currentY: CGFloat = 0
    var rowHeight: CGFloat = 0
    
    for view in arrangedSubviews {
      view.sizeToFit()
      let viewSize = view.intrinsicContentSize
      
      if currentX + viewSize.width > bounds.width && currentX > 0 {
        currentX = 0
        currentY += rowHeight + spacing
        rowHeight = 0
      }
      
      view.frame = CGRect(x: currentX, y: currentY, width: viewSize.width, height: viewSize.height)
      currentX += viewSize.width + spacing
      rowHeight = max(rowHeight, viewSize.height)
    }
    
    invalidateIntrinsicContentSize()
  }
  
  override var intrinsicContentSize: CGSize {
    var maxY: CGFloat = 0
    for view in arrangedSubviews {
      maxY = max(maxY, view.frame.maxY)
    }
    return CGSize(width: UIView.noIntrinsicMetric, height: maxY)
  }
}

