//
//  DaySlider.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/05/25.
//

import Foundation
import UIKit

protocol DaySliderDelegate: AnyObject {
  func daySlider(_ slider: DaySlider, didSelectDay day: Int)
  func daySlider(_ slider: DaySlider, didReachCurrentDay day: Int)
  func daySlider(_ slider: DaySlider, didChangeDay day: Int)  // Real-time updates during sliding
}

class DaySlider: UIView {

  // MARK: - Properties
  weak var delegate: DaySliderDelegate?

  private var currentDay: Int = 1
  private var totalDaysInMonth: Int = 31
  private var currentMonthDay: Int = 1

  private var lastHapticDay: Int = -1
  private var lastCurrentDayHaptic: Int = -1
  private var lastUpdateDay: Int = -1

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

  private let thumbView: UIView = {
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

  private let tooltipView: DaySliderTooltip = {
    let tooltip = DaySliderTooltip()
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
  private var progressWidthConstraint: NSLayoutConstraint?
  private var thumbCenterConstraint: NSLayoutConstraint?
  private var tooltipCenterConstraint: NSLayoutConstraint?

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
    addSubview(thumbView)
    addSubview(tooltipView)

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
    progressWidthConstraint = progressView.widthAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      progressView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor),
      progressView.centerYAnchor.constraint(equalTo: trackView.centerYAnchor),
      progressView.heightAnchor.constraint(equalTo: trackView.heightAnchor),
      progressWidthConstraint!,
    ])

    // Thumb view constraints
    thumbCenterConstraint = thumbView.centerXAnchor.constraint(equalTo: leadingAnchor)
    NSLayoutConstraint.activate([
      thumbView.centerYAnchor.constraint(equalTo: trackView.centerYAnchor),
      thumbView.widthAnchor.constraint(equalToConstant: 24),
      thumbView.heightAnchor.constraint(equalToConstant: 24),
      thumbCenterConstraint!,
    ])

    // Day indicators container constraints
    NSLayoutConstraint.activate([
      dayIndicatorsContainer.leadingAnchor.constraint(equalTo: trackView.leadingAnchor),
      dayIndicatorsContainer.trailingAnchor.constraint(equalTo: trackView.trailingAnchor),
      dayIndicatorsContainer.centerYAnchor.constraint(equalTo: trackView.centerYAnchor),
      dayIndicatorsContainer.heightAnchor.constraint(equalToConstant: 4),
    ])

    // Tooltip constraints
    tooltipCenterConstraint = tooltipView.centerXAnchor.constraint(equalTo: thumbView.centerXAnchor)
    NSLayoutConstraint.activate([
      tooltipView.bottomAnchor.constraint(equalTo: thumbView.topAnchor, constant: -8),
      tooltipCenterConstraint!,
    ])
  }

  private func setupGestureRecognizers() {
    let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
    addGestureRecognizer(panGesture)

    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
    addGestureRecognizer(tapGesture)
  }

  // MARK: - Configuration
  func configure(currentDay: Int, totalDaysInMonth: Int, currentMonthDay: Int) {
    logDebug(
      "DaySlider: configure called with currentDay=\(currentDay), totalDaysInMonth=\(totalDaysInMonth), currentMonthDay=\(currentMonthDay)"
    )
    self.currentDay = currentDay
    self.totalDaysInMonth = totalDaysInMonth
    self.currentMonthDay = currentMonthDay

    // Temporarily disable interaction during setup
    isUserInteractionEnabled = false

    setupDayIndicators()
    updateSliderPosition()
    updateTooltip()

    // Interaction will be re-enabled when day indicators are ready
    logDebug("DaySlider: configure completed, dayIndicatorViews.count=\(dayIndicatorViews.count)")
  }

  // MARK: - Gesture Handlers
  @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
    // Safety check to prevent crashes during setup
    guard dayIndicatorViews.count > 0 else { return }

    let location = gesture.location(in: self)
    let day = dayFromPosition(location.x)

    switch gesture.state {
    case .began:
      // Show tooltip when starting to slide
      tooltipView.show()
      updateSliderToDay(day, animated: false)
      triggerHapticFeedback(for: day)
      lastUpdateDay = day  // Reset tracking for new gesture

    case .changed:
      updateSliderToDay(day, animated: false)
      triggerHapticFeedback(for: day)
      // Only update if the day actually changed to avoid unnecessary calculations
      if day != lastUpdateDay {
        lastUpdateDay = day
        delegate?.daySlider(self, didChangeDay: day)  // Real-time updates during sliding
      }

    case .ended, .cancelled:
      // Hide tooltip when finished sliding
      tooltipView.hide()
      // Snap to nearest valid day
      let snappedDay = snapToValidDay(day)
      updateSliderToDay(snappedDay, animated: true)
      delegate?.daySlider(self, didSelectDay: snappedDay)

    default:
      break
    }
  }

  @objc private func handleTapGesture(_ gesture: UITapGestureRecognizer) {
    // Safety check to prevent crashes during setup
    guard dayIndicatorViews.count > 0 else { return }

    let location = gesture.location(in: self)
    let day = dayFromPosition(location.x)
    let snappedDay = snapToValidDay(day)

    // Show tooltip briefly for tap
    tooltipView.show()
    updateSliderToDay(snappedDay, animated: true)
    triggerHapticFeedback(for: snappedDay)
    delegate?.daySlider(self, didSelectDay: snappedDay)

    // Hide tooltip after a short delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.tooltipView.hide()
    }
  }

  // MARK: - Helper Methods
  private func dayFromPosition(_ xPosition: CGFloat) -> Int {
    let trackWidth = bounds.width
    let clampedX = max(0, min(xPosition, trackWidth))
    let progress = clampedX / trackWidth
    let day = Int(round(progress * CGFloat(totalDaysInMonth - 1))) + 1
    return max(1, min(day, totalDaysInMonth))
  }

  private func positionFromDay(_ day: Int) -> CGFloat {
    let progress = CGFloat(day - 1) / CGFloat(totalDaysInMonth - 1)
    return progress * bounds.width
  }

  private func snapToValidDay(_ day: Int) -> Int {
    // Snap to current day if within reasonable range (only for current month)
    if currentMonthDay > 0 && abs(day - currentMonthDay) <= 2 {
      return currentMonthDay
    }

    // Snap to last day if close to end
    if day >= totalDaysInMonth - 1 {
      return totalDaysInMonth
    }

    return max(1, min(day, totalDaysInMonth))
  }

  private func updateSliderToDay(_ day: Int, animated: Bool) {
    currentDay = day
    updateSliderPosition(animated: animated)
    updateTooltip()
    updateDayIndicators()
  }

  private func updateSliderPosition(animated: Bool = false) {
    let position = positionFromDay(currentDay)
    let progressWidth = position

    if animated {
      // Use a slightly longer duration for smoother foreground refresh animation
      UIView.animate(
        withDuration: 0.4, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]
      ) {
        self.thumbCenterConstraint?.constant = position
        self.progressWidthConstraint?.constant = progressWidth
        self.tooltipCenterConstraint?.constant = 0
        self.layoutIfNeeded()
      }
    } else {
      thumbCenterConstraint?.constant = position
      progressWidthConstraint?.constant = progressWidth
      tooltipCenterConstraint?.constant = 0
    }
  }

  private func updateTooltip() {
    tooltipView.updateDay(currentDay)
  }

  private func setupDayIndicators() {
    // Clear existing indicators
    dayIndicatorViews.forEach { $0.removeFromSuperview() }
    dayIndicatorViews.removeAll()
    dayIndicatorHeightConstraints.removeAll()

    // Create indicators for each day
    for day in 1...totalDaysInMonth {
      let indicator = createDayIndicator(for: day)
      dayIndicatorsContainer.addSubview(indicator)
      dayIndicatorViews.append(indicator)

      // Set constraints after adding to view hierarchy
      let width: CGFloat = 2
      // Set correct height from the start based on whether this is the current day of month
      let height: CGFloat = (day == currentMonthDay && currentMonthDay > 0) ? 16 : 1
      let heightConstraint = indicator.heightAnchor.constraint(equalToConstant: height)
      dayIndicatorHeightConstraints.append(heightConstraint)

      NSLayoutConstraint.activate([
        indicator.widthAnchor.constraint(equalToConstant: width),
        heightConstraint,
        indicator.centerYAnchor.constraint(equalTo: dayIndicatorsContainer.centerYAnchor),
      ])

      // Hide indicators initially to prevent flash
      indicator.alpha = 0
    }

    // Defer the positioning and showing to avoid flash
    DispatchQueue.main.async {
      self.updateDayIndicators()
      // Show indicators after positioning is complete
      UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
        self.dayIndicatorViews.forEach { $0.alpha = 1 }
      } completion: { _ in
        // Re-enable interaction now that everything is ready
        self.isUserInteractionEnabled = true
      }
    }
  }

  private func createDayIndicator(for day: Int) -> UIView {
    let indicator = UIView()
    indicator.layer.cornerRadius = 1
    indicator.translatesAutoresizingMaskIntoConstraints = false

    // Set correct appearance from the start
    if day == currentDay {
      indicator.backgroundColor = Colors.mainMagenta
      indicator.alpha = 1.0
      indicator.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
    } else if day == currentMonthDay && currentMonthDay > 0 {
      // Only show current day indicator for current month (currentMonthDay > 0)
      indicator.backgroundColor = Colors.gray100
      indicator.alpha = 1.0
      indicator.transform = .identity
    } else {
      indicator.backgroundColor = Colors.gray400
      indicator.alpha = 0.6
      indicator.transform = .identity
    }

    return indicator
  }

  private func updateDayIndicators() {
    for (index, indicator) in dayIndicatorViews.enumerated() {
      let day = index + 1
      let position = positionFromDay(day)

      // Update position
      indicator.center.x = position

      // Heights and appearance are already set correctly during setup
      // Only update visual appearance if the current day has changed (for real-time updates during sliding)
      if day == currentDay {
        indicator.backgroundColor = Colors.mainMagenta
        indicator.alpha = 1.0
        indicator.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
      } else if day == currentMonthDay && currentMonthDay > 0 {
        // Only show current day indicator for current month (currentMonthDay > 0)
        indicator.backgroundColor = Colors.gray100
        indicator.alpha = 1.0
        indicator.transform = .identity
      } else {
        indicator.backgroundColor = Colors.gray400
        indicator.alpha = 0.6
        indicator.transform = .identity
      }
    }
  }

  private func triggerHapticFeedback(for day: Int) {
    // Regular haptic feedback for each day
    if day != lastHapticDay {
      let impactFeedback = UIImpactFeedbackGenerator(style: .light)
      impactFeedback.impactOccurred()
      lastHapticDay = day
    }

    // Stronger haptic feedback for current day (only for current month)
    if currentMonthDay > 0 && day == currentMonthDay && day != lastCurrentDayHaptic {
      let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
      impactFeedback.impactOccurred()
      lastCurrentDayHaptic = day
      delegate?.daySlider(self, didReachCurrentDay: day)
    }
  }

  // MARK: - Public Methods
  func setDay(_ day: Int, animated: Bool = true) {
    let clampedDay = max(1, min(day, totalDaysInMonth))
    let previousDay = currentDay
    updateSliderToDay(clampedDay, animated: animated)

    // Add subtle haptic feedback for foreground refresh animation
    if animated && previousDay != clampedDay {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
      }
    }
  }

  /// Animates the slider to the current day with a subtle bounce effect for foreground refresh
  func animateForegroundRefresh() {
    let currentDay = self.currentDay
    logDebug("DaySlider: Animating foreground refresh to day \(currentDay)")

    // Create a subtle bounce animation by temporarily moving slightly and then back
    let bounceOffset: CGFloat = 10
    let originalPosition = positionFromDay(currentDay)

    // First, animate to a slightly offset position
    UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut]) {
      self.thumbCenterConstraint?.constant = originalPosition + bounceOffset
      self.layoutIfNeeded()
    } completion: { _ in
      // Then animate back to the correct position
      UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut]) {
        self.thumbCenterConstraint?.constant = originalPosition
        self.progressWidthConstraint?.constant = originalPosition
        self.layoutIfNeeded()
      } completion: { _ in
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
      }
    }
  }

  /// Checks if day indicators are already set up
  func hasDayIndicators() -> Bool {
    return dayIndicatorViews.count > 0
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateSliderPosition()
    updateDayIndicators()
    thumbView.layer.shadowPath = UIBezierPath(
      roundedRect: thumbView.bounds,
      cornerRadius: thumbView.layer.cornerRadius
    ).cgPath
  }
}
