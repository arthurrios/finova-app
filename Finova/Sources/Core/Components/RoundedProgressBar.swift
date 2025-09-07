//
//  RoundedProgressBar.swift
//  FinanceApp
//
//  Created by Arthur Rios on 10/05/25.
//

import UIKit

/// A custom progress bar with reliable rounded corners that works across all Xcode versions
class RoundedProgressBar: UIView {

  // MARK: - Properties

  private let trackLayer = CALayer()
  private let progressLayer = CALayer()

  var progress: Float = 0.0 {
    didSet {
      updateProgress()
    }
  }

  var trackTintColor: UIColor = Colors.gray600 {
    didSet {
      trackLayer.backgroundColor = trackTintColor.cgColor
    }
  }

  var progressTintColor: UIColor = Colors.mainMagenta {
    didSet {
      progressLayer.backgroundColor = progressTintColor.cgColor
    }
  }

  var cornerRadius: CGFloat = 4.0 {
    didSet {
      trackLayer.cornerRadius = cornerRadius
      progressLayer.cornerRadius = cornerRadius
    }
  }

  // MARK: - Initialization

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupLayers()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupLayers()
  }

  // MARK: - Setup

  private func setupLayers() {
    // Setup track layer
    trackLayer.backgroundColor = trackTintColor.cgColor
    trackLayer.cornerRadius = cornerRadius
    layer.addSublayer(trackLayer)

    // Setup progress layer
    progressLayer.backgroundColor = progressTintColor.cgColor
    progressLayer.cornerRadius = cornerRadius
    layer.addSublayer(progressLayer)
  }

  // MARK: - Layout

  override func layoutSubviews() {
    super.layoutSubviews()

    // Update track layer frame
    trackLayer.frame = bounds

    // Update progress layer frame
    let progressWidth = bounds.width * CGFloat(progress)
    progressLayer.frame = CGRect(
      x: 0,
      y: 0,
      width: progressWidth,
      height: bounds.height
    )
  }

  // MARK: - Progress Updates

  func setProgress(_ progress: Float, animated: Bool) {
    let clampedProgress = max(0, min(1, progress))

    if animated {
      animateProgress(to: clampedProgress)
    } else {
      self.progress = clampedProgress
    }
  }

  private func updateProgress() {
    let progressWidth = bounds.width * CGFloat(progress)
    progressLayer.frame = CGRect(
      x: 0,
      y: 0,
      width: progressWidth,
      height: bounds.height
    )
  }

  private func animateProgress(to targetProgress: Float) {
    let startProgress = progress
    let progressDifference = targetProgress - startProgress

    // Create animation for the progress layer
    let animation = CABasicAnimation(keyPath: "bounds.size.width")
    animation.fromValue = bounds.width * CGFloat(startProgress)
    animation.toValue = bounds.width * CGFloat(targetProgress)
    animation.duration = 0.3
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    animation.fillMode = .forwards
    animation.isRemovedOnCompletion = false

    // Apply animation
    progressLayer.add(animation, forKey: "progressAnimation")

    // Update the actual progress value
    progress = targetProgress
  }

  // MARK: - Color Updates

  func updateColors(trackColor: UIColor, progressColor: UIColor) {
    trackTintColor = trackColor
    progressTintColor = progressColor
  }
}
