//
//  CircularProgressView.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import UIKit

final class CircularProgressView: UIView {

    // MARK: - Properties

    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()

    var trackColor: UIColor = Colors.gray300 {
        didSet { trackLayer.strokeColor = trackColor.cgColor }
    }

    var progressColor: UIColor = Colors.mainMagenta {
        didSet { progressLayer.strokeColor = progressColor.cgColor }
    }

    var lineWidth: CGFloat = 12 {
        didSet {
            trackLayer.lineWidth = lineWidth
            progressLayer.lineWidth = lineWidth
            setNeedsLayout()
        }
    }

    private(set) var progress: CGFloat = 0

    // MARK: - UI Components

    private lazy var centerStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Metrics.spacing1
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var percentageLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleLG
        label.textColor = Colors.gray700
        label.textAlignment = .center
        return label
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textAlignment = .center
        return label
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
        setupCenterContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupLayers() {
        // Track layer (background circle)
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = trackColor.cgColor
        trackLayer.lineWidth = lineWidth
        trackLayer.lineCap = .round
        layer.addSublayer(trackLayer)

        // Progress layer (foreground arc)
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = progressColor.cgColor
        progressLayer.lineWidth = lineWidth
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        layer.addSublayer(progressLayer)
    }

    private func setupCenterContent() {
        addSubview(centerStackView)
        centerStackView.addArrangedSubview(percentageLabel)
        centerStackView.addArrangedSubview(statusLabel)

        NSLayoutConstraint.activate([
            centerStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerStackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = (min(bounds.width, bounds.height) - lineWidth) / 2

        // Start from top (-90 degrees)
        let startAngle: CGFloat = -.pi / 2
        let endAngle: CGFloat = startAngle + 2 * .pi

        let circularPath = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )

        trackLayer.path = circularPath.cgPath
        progressLayer.path = circularPath.cgPath
    }

    // MARK: - Public Methods

    func setProgress(_ progress: CGFloat, animated: Bool = true) {
        // Clamp progress to 0...1 for display, but store actual value
        let clampedProgress = min(max(progress, 0), 1)
        self.progress = progress

        if animated {
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.duration = 0.5
            animation.fromValue = progressLayer.strokeEnd
            animation.toValue = clampedProgress
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            progressLayer.add(animation, forKey: "progressAnimation")
        }

        progressLayer.strokeEnd = clampedProgress
    }

    func configure(percentage: Int, status: AllocationStatus) {
        percentageLabel.text = "\(percentage)%"
        percentageLabel.applyStyle()
        statusLabel.text = status.localizedLabel
        statusLabel.textColor = status.color
        progressColor = status.color

        // Set progress (percentage / 100)
        let progressValue = CGFloat(percentage) / 100.0
        setProgress(progressValue)
    }

    /// Configure for unallocated mode - shows spent amount instead of percentage
    func configureForUnallocated(spentAmount: Int) {
        // Show spent amount in compact format
        percentageLabel.text = spentAmount.currencyString
        percentageLabel.fontStyle = Fonts.titleSM  // Slightly smaller to fit currency
        percentageLabel.applyStyle()
        statusLabel.text = "allocation.details.unallocated.spent".localized
        statusLabel.textColor = Colors.gray500

        // Use gray color for unallocated state
        progressColor = Colors.gray400

        // Show full ring to indicate "all spending is untracked"
        setProgress(1.0)
    }
}
