//
//  DaySliderTooltip.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/05/25.
//

import Foundation
import UIKit

class DaySliderTooltip: UIView {

  // MARK: - Properties
  private var currentDay: Int = 1

  // MARK: - UI Components
  private let containerView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let backgroundView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let dayLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray100
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let arrowView: UIView = {
    let view = UIView()
    view.backgroundColor = .clear  // Remove background color to show the arrow shape
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  // MARK: - Initialization
  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()

    // Start hidden
    alpha = 0.0
    transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Setup
  private func setupView() {
    addSubview(containerView)
    containerView.addSubview(backgroundView)
    containerView.addSubview(arrowView)
    backgroundView.addSubview(dayLabel)

    setupConstraints()
    setupLiquidGlassEffect()
    setupArrowShape()
  }

  private func setupConstraints() {
    // Container view constraints
    NSLayoutConstraint.activate([
      containerView.topAnchor.constraint(equalTo: topAnchor),
      containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
      containerView.heightAnchor.constraint(equalToConstant: 24),
    ])

    // Background view constraints
    NSLayoutConstraint.activate([
      backgroundView.topAnchor.constraint(equalTo: containerView.topAnchor),
      backgroundView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      backgroundView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
    ])

    // Day label constraints
    NSLayoutConstraint.activate([
      dayLabel.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
      dayLabel.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
      dayLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: backgroundView.leadingAnchor, constant: 8),
      dayLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: backgroundView.trailingAnchor, constant: -8),
    ])

    // Arrow view constraints
    NSLayoutConstraint.activate([
      arrowView.topAnchor.constraint(equalTo: containerView.bottomAnchor),
      arrowView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
      arrowView.widthAnchor.constraint(equalToConstant: 12),  // Increased width for more prominent arrow
      arrowView.heightAnchor.constraint(equalToConstant: 6),  // Increased height for more prominent arrow
      arrowView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  private func setupLiquidGlassEffect() {
    // Check iOS version for liquid glass support
    if #available(iOS 15.0, *) {
      setupModernLiquidGlassEffect()
    } else {
      setupFallbackEffect()
    }
  }

  @available(iOS 15.0, *)
  private func setupModernLiquidGlassEffect() {
    // Modern liquid glass effect using UIVisualEffectView
    let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
    let blurView = UIVisualEffectView(effect: blurEffect)
    blurView.translatesAutoresizingMaskIntoConstraints = false

    // Add vibrancy effect
    let vibrancyEffect = UIVibrancyEffect(blurEffect: blurEffect, style: .secondaryLabel)
    let vibrancyView = UIVisualEffectView(effect: vibrancyEffect)
    vibrancyView.translatesAutoresizingMaskIntoConstraints = false

    backgroundView.addSubview(blurView)
    blurView.contentView.addSubview(vibrancyView)

    NSLayoutConstraint.activate([
      blurView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
      blurView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
      blurView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
      blurView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

      vibrancyView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor),
      vibrancyView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
      vibrancyView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
      vibrancyView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor),
    ])

    // Move day label to vibrancy view
    dayLabel.removeFromSuperview()
    vibrancyView.contentView.addSubview(dayLabel)

    NSLayoutConstraint.activate([
      dayLabel.centerXAnchor.constraint(equalTo: vibrancyView.contentView.centerXAnchor),
      dayLabel.centerYAnchor.constraint(equalTo: vibrancyView.contentView.centerYAnchor),
      dayLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: vibrancyView.contentView.leadingAnchor, constant: 8),
      dayLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: vibrancyView.contentView.trailingAnchor, constant: -8),
    ])

    // Add subtle border
    backgroundView.layer.borderWidth = 0.5
    backgroundView.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
    backgroundView.layer.cornerRadius = 8
    backgroundView.layer.masksToBounds = true

    // Update arrow color for modern effect
    if let arrowLayer = arrowView.layer.sublayers?.first as? CAShapeLayer {
      arrowLayer.fillColor = UIColor.white.withAlphaComponent(0.4).cgColor
      arrowLayer.strokeColor = UIColor.white.withAlphaComponent(0.3).cgColor
    }
  }

  private func setupFallbackEffect() {
    // Fallback for older iOS versions
    backgroundView.backgroundColor = Colors.gray600.withAlphaComponent(0.9)
    backgroundView.layer.cornerRadius = 8
    backgroundView.layer.masksToBounds = true

    // Add subtle shadow
    backgroundView.layer.shadowColor = Colors.gray700.cgColor
    backgroundView.layer.shadowOffset = CGSize(width: 0, height: 2)
    backgroundView.layer.shadowRadius = 4
    backgroundView.layer.shadowOpacity = 0.3

    // Update arrow color for fallback
    if let arrowLayer = arrowView.layer.sublayers?.first as? CAShapeLayer {
      arrowLayer.fillColor = Colors.gray600.cgColor
      arrowLayer.strokeColor = Colors.gray600.cgColor
    }
  }
  
  // MARK: - Customization
  func setDarkerAppearance() {
    // Remove existing blur views
    backgroundView.subviews.forEach { $0.removeFromSuperview() }
    dayLabel.removeFromSuperview()
    
    // Use darker, less transparent background
    backgroundView.backgroundColor = Colors.gray700.withAlphaComponent(0.95)
    backgroundView.layer.cornerRadius = 8
    backgroundView.layer.masksToBounds = true
    
    // Add shadow for depth
    backgroundView.layer.shadowColor = Colors.gray700.cgColor
    backgroundView.layer.shadowOffset = CGSize(width: 0, height: 2)
    backgroundView.layer.shadowRadius = 4
    backgroundView.layer.shadowOpacity = 0.5
    
    // Add border
    backgroundView.layer.borderWidth = 0.5
    backgroundView.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
    
    // Add day label back
    backgroundView.addSubview(dayLabel)
    NSLayoutConstraint.activate([
      dayLabel.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
      dayLabel.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
      dayLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: backgroundView.leadingAnchor, constant: 8),
      dayLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: backgroundView.trailingAnchor, constant: -8),
    ])
    
    // Update arrow color
    if let arrowLayer = arrowView.layer.sublayers?.first as? CAShapeLayer {
      arrowLayer.fillColor = Colors.gray700.cgColor
      arrowLayer.strokeColor = Colors.gray700.cgColor
    }
  }

  private func setupArrowShape() {
    // Create arrow shape using CAShapeLayer
    let arrowLayer = CAShapeLayer()
    let arrowPath = UIBezierPath()

    // Create a more prominent arrow pointing down
    let arrowWidth: CGFloat = 12
    let arrowHeight: CGFloat = 6

    // Arrow pointing down with more defined shape
    arrowPath.move(to: CGPoint(x: arrowWidth / 2, y: arrowHeight))  // Bottom center point (arrow tip)
    arrowPath.addLine(to: CGPoint(x: 0, y: 0))  // Top left
    arrowPath.addLine(to: CGPoint(x: arrowWidth, y: 0))  // Top right
    arrowPath.close()

    arrowLayer.path = arrowPath.cgPath
    arrowLayer.fillColor = Colors.gray600.cgColor
    arrowLayer.strokeColor = Colors.gray600.cgColor
    arrowLayer.lineWidth = 0.5
    arrowView.layer.addSublayer(arrowLayer)
  }

  // MARK: - Public Methods
  func updateDay(_ day: Int) {
    currentDay = day
    dayLabel.text = "\(day)"
  }

  func show() {
    // Animate the tooltip appearance with liquid glass effect
    UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
      self.alpha = 1.0
      self.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
    }
  }

  func hide() {
    UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseIn, .allowUserInteraction]) {
      self.alpha = 0.0
      self.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    // Update arrow layer frame
    if let arrowLayer = arrowView.layer.sublayers?.first as? CAShapeLayer {
      arrowLayer.frame = arrowView.bounds
    }
  }
}
