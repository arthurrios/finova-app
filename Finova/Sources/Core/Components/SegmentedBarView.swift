//
//  SegmentedBarView.swift
//  Finova
//
//  Created by Arthur Rios on 03/08/26.
//

import UIKit

/// A thin proportional bar made of side-by-side coloured segments.
///
/// Deliberately layer-based with no internal Auto Layout, mirroring `RoundedProgressBar`: it is
/// used inside `BudgetCard`, whose height must stay fixed, so nothing in here may ever contribute
/// an intrinsic content size.
final class SegmentedBarView: UIView {

    struct Segment {
        let share: CGFloat
        let color: UIColor

        init(share: CGFloat, color: UIColor) {
            self.share = share
            self.color = color
        }
    }

    // MARK: - Properties

    private var segments: [Segment] = []
    private var segmentLayers: [CALayer] = []

    /// Shown behind the segments, and on its own when there is nothing to plot.
    var trackTintColor: UIColor = Colors.gray600 {
        didSet { trackLayer.backgroundColor = trackTintColor.cgColor }
    }

    var cornerRadius: CGFloat = 2.0 {
        didSet {
            trackLayer.cornerRadius = cornerRadius
            layer.cornerRadius = cornerRadius
        }
    }

    /// Gap between segments, in points.
    var segmentSpacing: CGFloat = 1.0 {
        didSet { setNeedsLayout() }
    }

    private let trackLayer = CALayer()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    private func setupLayers() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true

        trackLayer.backgroundColor = trackTintColor.cgColor
        trackLayer.cornerRadius = cornerRadius
        layer.addSublayer(trackLayer)
    }

    // MARK: - Configuration

    /// Replaces the segments. Shares are expected to sum to 1; anything left over shows as track.
    func setSegments(_ segments: [Segment]) {
        self.segments = segments.filter { $0.share > 0 }

        segmentLayers.forEach { $0.removeFromSuperlayer() }
        segmentLayers = self.segments.map { segment in
            let segmentLayer = CALayer()
            segmentLayer.backgroundColor = segment.color.cgColor
            segmentLayer.cornerRadius = cornerRadius
            layer.addSublayer(segmentLayer)
            return segmentLayer
        }

        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        trackLayer.frame = bounds

        guard !segmentLayers.isEmpty else { return }

        // Spacing is carved out of the drawable width so the segments never overflow the bar.
        let totalSpacing = segmentSpacing * CGFloat(segmentLayers.count - 1)
        let drawableWidth = max(0, bounds.width - totalSpacing)

        var originX: CGFloat = 0
        for (index, segmentLayer) in segmentLayers.enumerated() {
            let width = drawableWidth * segments[index].share
            segmentLayer.frame = CGRect(x: originX, y: 0, width: width, height: bounds.height)
            originX += width + segmentSpacing
        }
    }
}
