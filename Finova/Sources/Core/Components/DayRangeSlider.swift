//
//  DayRangeSlider.swift
//  FinanceApp
//
//  Created by Arthur Rios on 26/01/26.
//

import Foundation
import UIKit

protocol DayRangeSliderDelegate: AnyObject {
  func dayRangeSlider(
    _ slider: DayRangeSlider, didChangeStartDay startDay: Int, endDay: Int, isInverted: Bool)
}

class DayRangeSlider: UIView {

  // MARK: - Properties
  weak var delegate: DayRangeSliderDelegate?

  private var startDay: Int = 1
  private var endDay: Int = 31
  private var totalDaysInMonth: Int = 31

  private var activeThumb: UIView?

  // MARK: - UI Components
  private let trackView: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray600
    view.layer.cornerRadius = 2
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let progressView: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.mainMagenta
    view.layer.cornerRadius = 2
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var startThumbView: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray100
    view.layer.cornerRadius = 12
    view.layer.shadowColor = Colors.gray700.cgColor
    view.layer.shadowOffset = CGSize(width: 0, height: 2)
    view.layer.shadowRadius = 4
    view.layer.shadowOpacity = 0.3
    view.translatesAutoresizingMaskIntoConstraints = false

    // Add chevron icon - always points right
    let iconImageView = UIImageView()
    iconImageView.image = UIImage(named: "chevronRight")
    iconImageView.tintColor = Colors.gray700
    iconImageView.contentMode = .scaleAspectFit
    iconImageView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(iconImageView)

    NSLayoutConstraint.activate([
      iconImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      iconImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      iconImageView.widthAnchor.constraint(equalToConstant: 12),
      iconImageView.heightAnchor.constraint(equalToConstant: 12),
    ])

    startThumbIcon = iconImageView
    return view
  }()

  private lazy var endThumbView: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray100
    view.layer.cornerRadius = 12
    view.layer.shadowColor = Colors.gray700.cgColor
    view.layer.shadowOffset = CGSize(width: 0, height: 2)
    view.layer.shadowRadius = 4
    view.layer.shadowOpacity = 0.3
    view.translatesAutoresizingMaskIntoConstraints = false

    // Add chevron icon - always points left
    let iconImageView = UIImageView()
    iconImageView.image = UIImage(named: "chevronLeft")
    iconImageView.tintColor = Colors.gray700
    iconImageView.contentMode = .scaleAspectFit
    iconImageView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(iconImageView)

    NSLayoutConstraint.activate([
      iconImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      iconImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      iconImageView.widthAnchor.constraint(equalToConstant: 12),
      iconImageView.heightAnchor.constraint(equalToConstant: 12),
    ])

    endThumbIcon = iconImageView
    return view
  }()

  private var startThumbIcon: UIImageView?
  private var endThumbIcon: UIImageView?

  // Second progress view for inverted range
  private let progressView2: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.mainMagenta
    view.layer.cornerRadius = 2
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private var progress2LeadingConstraint: NSLayoutConstraint?
  private var progress2WidthConstraint: NSLayoutConstraint?

  private let startTooltipView: DaySliderTooltip = {
    let tooltip = DaySliderTooltip()
    tooltip.setDarkerAppearance()
    tooltip.translatesAutoresizingMaskIntoConstraints = false
    tooltip.alpha = 0.0  // Hidden by default, shown only when dragging
    return tooltip
  }()

  private let endTooltipView: DaySliderTooltip = {
    let tooltip = DaySliderTooltip()
    tooltip.setDarkerAppearance()
    tooltip.translatesAutoresizingMaskIntoConstraints = false
    tooltip.alpha = 0.0  // Hidden by default, shown only when dragging
    return tooltip
  }()

  // Simple labels that appear when NOT dragging
  private let startDayLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray600
    label.textAlignment = .center
    label.text = "1"
    label.translatesAutoresizingMaskIntoConstraints = false
    label.alpha = 1.0  // Visible by default, hidden when dragging
    return label
  }()

  private let endDayLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray600
    label.textAlignment = .center
    label.text = "31"
    label.translatesAutoresizingMaskIntoConstraints = false
    label.alpha = 1.0  // Visible by default, hidden when dragging
    return label
  }()

  private let dayIndicatorsContainer: UIView = {
    let view = UIView()
    view.backgroundColor = .clear
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private var dayIndicatorViews: [UIView] = []
  private var dayIndicatorHeightConstraints: [NSLayoutConstraint] = []

  // MARK: - Constraints
  private var progressLeadingConstraint: NSLayoutConstraint?
  private var progressWidthConstraint: NSLayoutConstraint?
  private var startThumbCenterConstraint: NSLayoutConstraint?
  private var endThumbCenterConstraint: NSLayoutConstraint?
  private var startTooltipCenterConstraint: NSLayoutConstraint?
  private var endTooltipCenterConstraint: NSLayoutConstraint?
  private var startDayLabelCenterConstraint: NSLayoutConstraint?
  private var endDayLabelCenterConstraint: NSLayoutConstraint?

  // MARK: - Initialization
  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
    setupGestureRecognizers()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Setup
  private func setupView() {
    addSubview(trackView)
    addSubview(progressView)
    addSubview(progressView2)
    addSubview(dayIndicatorsContainer)
    addSubview(startThumbView)
    addSubview(endThumbView)
    addSubview(startTooltipView)
    addSubview(endTooltipView)
    addSubview(startDayLabel)
    addSubview(endDayLabel)

    // Enable user interaction on thumbs
    startThumbView.isUserInteractionEnabled = true
    endThumbView.isUserInteractionEnabled = true

    setupConstraints()
  }

  private func setupConstraints() {
    // Track view constraints
    NSLayoutConstraint.activate([
      trackView.leadingAnchor.constraint(equalTo: leadingAnchor),
      trackView.trailingAnchor.constraint(equalTo: trailingAnchor),
      trackView.centerYAnchor.constraint(equalTo: centerYAnchor),
      trackView.heightAnchor.constraint(equalToConstant: 4),
    ])

    // Progress view constraints
    progressLeadingConstraint = progressView.leadingAnchor.constraint(
      equalTo: trackView.leadingAnchor)
    progressWidthConstraint = progressView.widthAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      progressLeadingConstraint!,
      progressView.centerYAnchor.constraint(equalTo: trackView.centerYAnchor),
      progressView.heightAnchor.constraint(equalTo: trackView.heightAnchor),
      progressWidthConstraint!,
    ])

    // Second progress view constraints (for inverted range)
    progress2LeadingConstraint = progressView2.leadingAnchor.constraint(
      equalTo: trackView.leadingAnchor)
    progress2WidthConstraint = progressView2.widthAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      progress2LeadingConstraint!,
      progressView2.centerYAnchor.constraint(equalTo: trackView.centerYAnchor),
      progressView2.heightAnchor.constraint(equalTo: trackView.heightAnchor),
      progress2WidthConstraint!,
    ])
    progressView2.isHidden = true

    // Start thumb view constraints
    startThumbCenterConstraint = startThumbView.centerXAnchor.constraint(equalTo: leadingAnchor)
    NSLayoutConstraint.activate([
      startThumbView.centerYAnchor.constraint(equalTo: trackView.centerYAnchor),
      startThumbView.widthAnchor.constraint(equalToConstant: 24),
      startThumbView.heightAnchor.constraint(equalToConstant: 24),
      startThumbCenterConstraint!,
    ])

    // End thumb view constraints
    endThumbCenterConstraint = endThumbView.centerXAnchor.constraint(equalTo: leadingAnchor)
    NSLayoutConstraint.activate([
      endThumbView.centerYAnchor.constraint(equalTo: trackView.centerYAnchor),
      endThumbView.widthAnchor.constraint(equalToConstant: 24),
      endThumbView.heightAnchor.constraint(equalToConstant: 24),
      endThumbCenterConstraint!,
    ])

    // Day indicators container constraints
    NSLayoutConstraint.activate([
      dayIndicatorsContainer.leadingAnchor.constraint(equalTo: trackView.leadingAnchor),
      dayIndicatorsContainer.trailingAnchor.constraint(equalTo: trackView.trailingAnchor),
      dayIndicatorsContainer.centerYAnchor.constraint(equalTo: trackView.centerYAnchor),
      dayIndicatorsContainer.heightAnchor.constraint(equalToConstant: 4),
    ])

    // Tooltip constraints (shown only when dragging)
    startTooltipCenterConstraint = startTooltipView.centerXAnchor.constraint(
      equalTo: startThumbView.centerXAnchor)
    NSLayoutConstraint.activate([
      startTooltipView.bottomAnchor.constraint(equalTo: startThumbView.topAnchor, constant: -8),
      startTooltipCenterConstraint!,
    ])

    endTooltipCenterConstraint = endTooltipView.centerXAnchor.constraint(
      equalTo: endThumbView.centerXAnchor)
    NSLayoutConstraint.activate([
      endTooltipView.bottomAnchor.constraint(equalTo: endThumbView.topAnchor, constant: -8),
      endTooltipCenterConstraint!,
    ])

    // Simple day label constraints (always visible, follow thumb positions)
    startDayLabelCenterConstraint = startDayLabel.centerXAnchor.constraint(
      equalTo: startThumbView.centerXAnchor)
    NSLayoutConstraint.activate([
      startDayLabel.bottomAnchor.constraint(equalTo: startThumbView.topAnchor, constant: -4),
      startDayLabelCenterConstraint!,
    ])

    endDayLabelCenterConstraint = endDayLabel.centerXAnchor.constraint(
      equalTo: endThumbView.centerXAnchor)
    NSLayoutConstraint.activate([
      endDayLabel.bottomAnchor.constraint(equalTo: endThumbView.topAnchor, constant: -4),
      endDayLabelCenterConstraint!,
    ])
  }

  private func setupGestureRecognizers() {
    let startPanGesture = UIPanGestureRecognizer(
      target: self, action: #selector(handleStartPanGesture(_:)))
    startThumbView.addGestureRecognizer(startPanGesture)

    let endPanGesture = UIPanGestureRecognizer(
      target: self, action: #selector(handleEndPanGesture(_:)))
    endThumbView.addGestureRecognizer(endPanGesture)

    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
    addGestureRecognizer(tapGesture)
  }

  // MARK: - Configuration
  func configure(startDay: Int, endDay: Int, totalDaysInMonth: Int) {
    self.startDay = max(1, min(startDay, totalDaysInMonth))
    self.endDay = max(1, min(endDay, totalDaysInMonth))
    self.totalDaysInMonth = totalDaysInMonth

    // Allow inversion - no constraint on startDay <= endDay

    // Setup day indicators will be called in layoutSubviews
    setNeedsLayout()
    layoutIfNeeded()

    // Update positions and tooltips
    updateSliderPositions()
    updateTooltips()
    updateIcons()
  }

  private var isInverted: Bool {
    return startDay > endDay
  }

  // MARK: - Gesture Handlers
  @objc private func handleStartPanGesture(_ gesture: UIPanGestureRecognizer) {
    guard dayIndicatorViews.count > 0 else { return }
    activeThumb = startThumbView

    let location = gesture.location(in: self)
    let day = dayFromPosition(location.x)

    switch gesture.state {
    case .began:
      startTooltipView.show()
      startDayLabel.alpha = 0.0  // Hide simple label while dragging
      updateStartDay(day, animated: false)

    case .changed:
      updateStartDay(day, animated: false)

    case .ended, .cancelled:
      startTooltipView.hide()
      startDayLabel.alpha = 1.0  // Show simple label when not dragging
      let snappedDay = snapToValidDay(day)
      updateStartDay(snappedDay, animated: true)
      notifyDelegate()

    default:
      break
    }
  }

  @objc private func handleEndPanGesture(_ gesture: UIPanGestureRecognizer) {
    guard dayIndicatorViews.count > 0 else { return }
    activeThumb = endThumbView

    let location = gesture.location(in: self)
    let day = dayFromPosition(location.x)

    switch gesture.state {
    case .began:
      endTooltipView.show()
      endDayLabel.alpha = 0.0  // Hide simple label while dragging
      updateEndDay(day, animated: false)

    case .changed:
      updateEndDay(day, animated: false)

    case .ended, .cancelled:
      endTooltipView.hide()
      endDayLabel.alpha = 1.0  // Show simple label when not dragging
      let snappedDay = snapToValidDay(day)
      updateEndDay(snappedDay, animated: true)
      notifyDelegate()

    default:
      break
    }
  }

  @objc private func handleTapGesture(_ gesture: UITapGestureRecognizer) {
    guard dayIndicatorViews.count > 0 else { return }

    let location = gesture.location(in: self)
    let day = snapToValidDay(dayFromPosition(location.x))

    // Determine which thumb is closer
    let startPosition = positionFromDay(startDay)
    let endPosition = positionFromDay(endDay)
    let tapPosition = location.x

    let distanceToStart = abs(tapPosition - startPosition)
    let distanceToEnd = abs(tapPosition - endPosition)

    if distanceToStart < distanceToEnd {
      // Update start day
      startTooltipView.show()
      startDayLabel.alpha = 0.0  // Hide simple label while showing tooltip
      updateStartDay(day, animated: true)
      notifyDelegate()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        self.startTooltipView.hide()
        self.startDayLabel.alpha = 1.0  // Show simple label after tooltip hides
      }
    } else {
      // Update end day
      endTooltipView.show()
      endDayLabel.alpha = 0.0  // Hide simple label while showing tooltip
      updateEndDay(day, animated: true)
      notifyDelegate()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        self.endTooltipView.hide()
        self.endDayLabel.alpha = 1.0  // Show simple label after tooltip hides
      }
    }
  }

  // MARK: - Helper Methods
  private func dayFromPosition(_ xPosition: CGFloat) -> Int {
    let trackWidth = bounds.width
    guard trackWidth > 0 else { return 1 }

    let clampedX = max(0, min(xPosition, trackWidth))
    let progress = clampedX / trackWidth
    let day = Int(round(progress * CGFloat(totalDaysInMonth - 1))) + 1
    return max(1, min(day, totalDaysInMonth))
  }

  private func positionFromDay(_ day: Int) -> CGFloat {
    guard totalDaysInMonth > 1 else { return 0 }
    let progress = CGFloat(day - 1) / CGFloat(totalDaysInMonth - 1)
    return progress * bounds.width
  }

  private func snapToValidDay(_ day: Int) -> Int {
    return max(1, min(day, totalDaysInMonth))
  }

  private func updateStartDay(_ day: Int, animated: Bool) {
    let clampedDay = max(1, min(day, totalDaysInMonth))
    startDay = clampedDay
    updateSliderPositions(animated: animated)
    updateTooltips()
    updateIcons()
  }

  private func updateEndDay(_ day: Int, animated: Bool) {
    let clampedDay = max(1, min(day, totalDaysInMonth))
    endDay = clampedDay
    updateSliderPositions(animated: animated)
    updateTooltips()
    updateIcons()
  }

  private func updateSliderPositions(animated: Bool = false) {
    let startPosition = positionFromDay(startDay)
    let endPosition = positionFromDay(endDay)
    let trackWidth = trackView.bounds.width > 0 ? trackView.bounds.width : bounds.width

    let inverted = isInverted

    if inverted {
      // Inverted range: two segments
      // First segment: from start to end of track
      let firstSegmentWidth = trackWidth - startPosition
      // Second segment: from start of track to end
      let secondSegmentWidth = endPosition

      progressView2.isHidden = false

      if animated {
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
          self.startThumbCenterConstraint?.constant = startPosition
          self.endThumbCenterConstraint?.constant = endPosition
          self.progressLeadingConstraint?.constant = startPosition
          self.progressWidthConstraint?.constant = firstSegmentWidth
          self.progress2LeadingConstraint?.constant = 0
          self.progress2WidthConstraint?.constant = secondSegmentWidth
          self.startTooltipCenterConstraint?.constant = 0
          self.endTooltipCenterConstraint?.constant = 0
          self.layoutIfNeeded()
        }
      } else {
        startThumbCenterConstraint?.constant = startPosition
        endThumbCenterConstraint?.constant = endPosition
        progressLeadingConstraint?.constant = startPosition
        progressWidthConstraint?.constant = firstSegmentWidth
        progress2LeadingConstraint?.constant = 0
        progress2WidthConstraint?.constant = secondSegmentWidth
        startTooltipCenterConstraint?.constant = 0
        endTooltipCenterConstraint?.constant = 0
      }
    } else {
      // Normal range: single segment
      let progressWidth = endPosition - startPosition

      progressView2.isHidden = true

      if animated {
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
          self.startThumbCenterConstraint?.constant = startPosition
          self.endThumbCenterConstraint?.constant = endPosition
          self.progressLeadingConstraint?.constant = startPosition
          self.progressWidthConstraint?.constant = progressWidth
          self.progress2WidthConstraint?.constant = 0
          self.startTooltipCenterConstraint?.constant = 0
          self.endTooltipCenterConstraint?.constant = 0
          self.layoutIfNeeded()
        }
      } else {
        startThumbCenterConstraint?.constant = startPosition
        endThumbCenterConstraint?.constant = endPosition
        progressLeadingConstraint?.constant = startPosition
        progressWidthConstraint?.constant = progressWidth
        progress2WidthConstraint?.constant = 0
        startTooltipCenterConstraint?.constant = 0
        endTooltipCenterConstraint?.constant = 0
      }
    }
  }

  private func updateIcons() {
    // Icons always point in the same direction:
    // Left thumb (start) always points right (chevronRight)
    // Right thumb (end) always points left (chevronLeft)
    // This doesn't change when inverted - the direction indicates the range direction
    startThumbIcon?.image = UIImage(named: "chevronRight")
    endThumbIcon?.image = UIImage(named: "chevronLeft")
  }

  private func updateTooltips() {
    startTooltipView.updateDay(startDay)
    endTooltipView.updateDay(endDay)
    // Update simple labels (always visible)
    startDayLabel.text = "\(startDay)"
    endDayLabel.text = "\(endDay)"
  }

  private func notifyDelegate() {
    delegate?.dayRangeSlider(
      self, didChangeStartDay: startDay, endDay: endDay, isInverted: isInverted)
  }

  private func setupDayIndicators() {
    // Clear existing indicators
    dayIndicatorViews.forEach { $0.removeFromSuperview() }
    dayIndicatorViews.removeAll()
    dayIndicatorHeightConstraints.removeAll()

    guard totalDaysInMonth > 0 else { return }

    // Create indicators for each day
    for day in 1...totalDaysInMonth {
      let indicator = UIView()
      indicator.backgroundColor = Colors.gray400
      indicator.layer.cornerRadius = 1
      indicator.alpha = 0.6
      indicator.translatesAutoresizingMaskIntoConstraints = false

      dayIndicatorsContainer.addSubview(indicator)
      dayIndicatorViews.append(indicator)

      let heightConstraint = indicator.heightAnchor.constraint(equalToConstant: 2)
      dayIndicatorHeightConstraints.append(heightConstraint)

      NSLayoutConstraint.activate([
        indicator.widthAnchor.constraint(equalToConstant: 2),
        heightConstraint,
        indicator.centerYAnchor.constraint(equalTo: dayIndicatorsContainer.centerYAnchor),
      ])
    }

    // Update positions after layout
    DispatchQueue.main.async {
      self.updateDayIndicators()
    }
  }

  private func updateDayIndicators() {
    guard bounds.width > 0 else { return }

    for (index, indicator) in dayIndicatorViews.enumerated() {
      let day = index + 1
      let position = positionFromDay(day)
      indicator.center.x = position
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    // Setup day indicators on first layout or if they don't exist
    if dayIndicatorViews.isEmpty && totalDaysInMonth > 0 {
      setupDayIndicators()
    } else if !dayIndicatorViews.isEmpty {
      updateDayIndicators()
    }

    // Update slider positions after layout
    updateSliderPositions()
    updateTooltips()

    startThumbView.layer.shadowPath = UIBezierPath(
      roundedRect: startThumbView.bounds,
      cornerRadius: startThumbView.layer.cornerRadius
    ).cgPath
    endThumbView.layer.shadowPath = UIBezierPath(
      roundedRect: endThumbView.bounds,
      cornerRadius: endThumbView.layer.cornerRadius
    ).cgPath
  }

  // MARK: - Public Methods
  func getStartDay() -> Int {
    return startDay
  }

  func getEndDay() -> Int {
    return endDay
  }
}
