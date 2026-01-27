//
//  DayRangeSlider.swift
//  FinanceApp
//
//  Created by Arthur Rios on 26/01/26.
//

import Foundation
import UIKit

protocol DayRangeSliderDelegate: AnyObject {
  func dayRangeSlider(_ slider: DayRangeSlider, didChangeStartDay startDay: Int, endDay: Int)
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

  private let startThumbView: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray100
    view.layer.cornerRadius = 12
    view.layer.shadowColor = Colors.gray700.cgColor
    view.layer.shadowOffset = CGSize(width: 0, height: 2)
    view.layer.shadowRadius = 4
    view.layer.shadowOpacity = 0.3
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let endThumbView: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray100
    view.layer.cornerRadius = 12
    view.layer.shadowColor = Colors.gray700.cgColor
    view.layer.shadowOffset = CGSize(width: 0, height: 2)
    view.layer.shadowRadius = 4
    view.layer.shadowOpacity = 0.3
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let startTooltipView: DaySliderTooltip = {
    let tooltip = DaySliderTooltip()
    tooltip.setDarkerAppearance()
    tooltip.translatesAutoresizingMaskIntoConstraints = false
    return tooltip
  }()

  private let endTooltipView: DaySliderTooltip = {
    let tooltip = DaySliderTooltip()
    tooltip.setDarkerAppearance()
    tooltip.translatesAutoresizingMaskIntoConstraints = false
    return tooltip
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
    addSubview(dayIndicatorsContainer)
    addSubview(startThumbView)
    addSubview(endThumbView)
    addSubview(startTooltipView)
    addSubview(endTooltipView)

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

    // Tooltip constraints
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

    // Ensure startDay <= endDay
    if self.startDay > self.endDay {
      self.startDay = self.endDay
    }

    // Setup day indicators will be called in layoutSubviews
    setNeedsLayout()
    layoutIfNeeded()

    // Update positions and tooltips
    updateSliderPositions()
    updateTooltips()
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
      updateStartDay(day, animated: false)

    case .changed:
      updateStartDay(day, animated: false)

    case .ended, .cancelled:
      startTooltipView.hide()
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
      updateEndDay(day, animated: false)

    case .changed:
      updateEndDay(day, animated: false)

    case .ended, .cancelled:
      endTooltipView.hide()
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
      updateStartDay(day, animated: true)
      notifyDelegate()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        self.startTooltipView.hide()
      }
    } else {
      // Update end day
      endTooltipView.show()
      updateEndDay(day, animated: true)
      notifyDelegate()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        self.endTooltipView.hide()
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
    let clampedDay = max(1, min(day, endDay))  // Can't exceed end day
    startDay = clampedDay
    updateSliderPositions(animated: animated)
    updateTooltips()
  }

  private func updateEndDay(_ day: Int, animated: Bool) {
    let clampedDay = max(startDay, min(day, totalDaysInMonth))  // Can't go below start day
    endDay = clampedDay
    updateSliderPositions(animated: animated)
    updateTooltips()
  }

  private func updateSliderPositions(animated: Bool = false) {
    let startPosition = positionFromDay(startDay)
    let endPosition = positionFromDay(endDay)
    let progressWidth = endPosition - startPosition

    if animated {
      UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
        self.startThumbCenterConstraint?.constant = startPosition
        self.endThumbCenterConstraint?.constant = endPosition
        self.progressLeadingConstraint?.constant = startPosition
        self.progressWidthConstraint?.constant = progressWidth
        self.startTooltipCenterConstraint?.constant = 0
        self.endTooltipCenterConstraint?.constant = 0
        self.layoutIfNeeded()
      }
    } else {
      startThumbCenterConstraint?.constant = startPosition
      endThumbCenterConstraint?.constant = endPosition
      progressLeadingConstraint?.constant = startPosition
      progressWidthConstraint?.constant = progressWidth
      startTooltipCenterConstraint?.constant = 0
      endTooltipCenterConstraint?.constant = 0
    }
  }

  private func updateTooltips() {
    startTooltipView.updateDay(startDay)
    endTooltipView.updateDay(endDay)
  }

  private func notifyDelegate() {
    delegate?.dayRangeSlider(self, didChangeStartDay: startDay, endDay: endDay)
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
  }

  // MARK: - Public Methods
  func getStartDay() -> Int {
    return startDay
  }

  func getEndDay() -> Int {
    return endDay
  }
}
