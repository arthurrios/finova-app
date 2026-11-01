//
//  CoachMarkOverlay.swift
//  Finova
//

import UIKit

/// Where the bubble goes. Pure, so small screens and the keyboard can be tested with numbers.
enum CoachMarkLayout {
    static let gap = Metrics.spacing3
    static let margin = Metrics.spacing4
    static let maxBubbleWidth: CGFloat = 400

    /// `nil` means the bubble should hide: the keyboard is up and no spot leaves the form usable. It
    /// reappears when the keyboard goes down.
    static func bubbleFrame(
        size: CGSize, hole: CGRect?, bounds: CGRect, safeArea: UIEdgeInsets, keyboardTop: CGFloat?,
        mayCoverHole: Bool = true
    ) -> CGRect? {
        let x = (bounds.width - size.width) / 2
        let top = bounds.minY + safeArea.top + margin
        let bottom = (keyboardTop ?? (bounds.maxY - safeArea.bottom)) - margin

        guard let hole else {
            let centeredY = top + max(0, (bottom - top - size.height) / 2)
            return CGRect(x: x, y: centeredY, width: size.width, height: size.height)
        }

        let roomBelow = bottom - (hole.maxY + gap)
        let roomAbove = (hole.minY - gap) - top

        if roomBelow >= size.height {
            return CGRect(x: x, y: hole.maxY + gap, width: size.width, height: size.height)
        }
        if roomAbove >= size.height {
            return CGRect(x: x, y: hole.minY - gap - size.height, width: size.width, height: size.height)
        }
        // A hole taller than the free space, such as a full sheet. Over the sheet's header is the
        // least harmful place, but not while the user is typing into it.
        return keyboardTop == nil && mayCoverHole
            ? CGRect(x: x, y: top, width: size.width, height: size.height)
            : nil
    }
}

/// The card with the message and the way out.
final class CoachMarkBubbleView: UIView {
    var onNext: (() -> Void)?
    var onSkip: (() -> Void)?
    var onSkipAll: (() -> Void)?

    private let captionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Colors.mainMagenta
        label.numberOfLines = 0
        return label
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Colors.gray700
        label.numberOfLines = 0
        return label
    }()

    private lazy var skipAllButton = makeButton(color: Colors.gray500, action: #selector(skipAllTapped))
    private lazy var skipButton = makeButton(color: Colors.gray500, action: #selector(skipTapped))
    private lazy var nextButton = makeButton(color: Colors.mainMagenta, action: #selector(nextTapped))

    private let buttonSpacer: UIView = {
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return spacer
    }()

    private lazy var buttonStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [skipAllButton, skipButton, buttonSpacer, nextButton])
        stack.axis = .horizontal
        stack.spacing = Metrics.spacing4
        stack.alignment = .center
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray100
        layer.cornerRadius = CornerRadius.extraLarge
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)

        let stack = UIStackView(arrangedSubviews: [captionLabel, messageLabel, buttonStack])
        stack.axis = .vertical
        stack.spacing = Metrics.spacing2
        stack.setCustomSpacing(Metrics.spacing3, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.spacing4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.spacing2),
        ])

        // Past this the card would not fit next to the thing it points at. The words wrap freely up
        // to here, and the buttons drop onto their own lines below.
        maximumContentSizeCategory = .accessibilityMedium
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeButton(color: UIColor, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.titleLabel?.font = Fonts.titleXS.font
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .left
        button.setTitleColor(color, for: .normal)
        button.contentHorizontalAlignment = .leading
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    struct Content: Equatable {
        var caption: String
        var message: String
        var nextTitle: String?
        /// nil on a guide's last note, where Done is already the way out.
        var skipTitle: String?
        var skipAllTitle: String?
    }

    func configure(_ content: Content) {
        captionLabel.text = content.caption
        messageLabel.text = content.message
        nextButton.setTitle(content.nextTitle, for: .normal)
        nextButton.isHidden = content.nextTitle == nil
        skipButton.setTitle(content.skipTitle, for: .normal)
        skipButton.isHidden = content.skipTitle == nil
        skipAllButton.setTitle(content.skipAllTitle, for: .normal)
        skipAllButton.isHidden = content.skipAllTitle == nil
        buttonStack.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            ? .vertical : .horizontal
        buttonStack.alignment = buttonStack.axis == .vertical ? .leading : .center
        buttonStack.spacing = buttonStack.axis == .vertical ? 0 : Metrics.spacing4
        buttonSpacer.isHidden = buttonStack.axis == .vertical
    }

    func fittingSize(width: CGFloat) -> CGSize {
        // Without this the labels wrap for their old width, and the card is measured too tall.
        let textWidth = width - 2 * Metrics.spacing4
        captionLabel.preferredMaxLayoutWidth = textWidth
        messageLabel.preferredMaxLayoutWidth = textWidth
        let size = systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        return CGSize(width: width, height: ceil(size.height))
    }

    @objc private func nextTapped() { onNext?() }
    @objc private func skipTapped() { onSkip?() }
    @objc private func skipAllTapped() { onSkipAll?() }
}

/// The dim layer, the hole, and the rule for who gets a touch.
final class CoachMarkOverlayView: UIView {
    let bubble = CoachMarkBubbleView()
    /// Called on a tap on the dim layer. It never does anything but put a keyboard away.
    var onDimTapped: (() -> Void)?

    private let dimLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()

    /// In window coordinates, padded. nil is a centred card.
    private(set) var hole: CGRect?
    private(set) var isHoleTouchable = false
    /// A sheet step: no ring and no dim, only the card. The touch rule does not change.
    private(set) var isPlain = false
    var isDimVisible: Bool { !isPlain }
    var isRingVisible: Bool { !ringLayer.isHidden }
    private var keyboardTop: CGFloat?
    private var cornerRadius: CGFloat = 0

    /// False while hidden, so a mark on its way out can never eat a touch.
    var isActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        dimLayer.fillColor = UIColor.black.withAlphaComponent(0.62).cgColor
        dimLayer.fillRule = .evenOdd
        layer.addSublayer(dimLayer)

        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.strokeColor = Colors.mainMagenta.cgColor
        ringLayer.lineWidth = 2
        layer.addSublayer(ringLayer)

        addSubview(bubble)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dimTapped)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The whole touch rule. Returning nil here lets the touch fall through to the app's own window,
    /// where normal hit testing runs, so the target behaves exactly as it does with no overlay. That
    /// includes the interactive glass controls, which only work through a real hit test.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isActive else { return nil }
        if !bubble.isHidden, bubble.frame.contains(point) {
            return bubble.hitTest(convert(point, to: bubble), with: event) ?? bubble
        }
        if isHoleTouchable, let hole, hole.contains(point) { return nil }
        return self
    }

    /// Updates the hole. `animated` is for moving between targets; following a target that moves by
    /// itself is not animated, because it is already moving.
    func show(
        hole newHole: CGRect?, touchable: Bool, keyboardTop: CGFloat?, animated: Bool,
        plain: Bool = false
    ) {
        let padded = newHole?.insetBy(dx: -Metrics.spacing1 - 2, dy: -Metrics.spacing1 - 2)
        let isRound = padded.map { abs($0.width - $0.height) < 8 } ?? false

        hole = padded
        isHoleTouchable = touchable
        isPlain = plain
        self.keyboardTop = keyboardTop
        cornerRadius = isRound ? (padded?.height ?? 0) / 2 : CornerRadius.extraLarge

        let dimPath = path(hole: padded)
        let ringPath = padded.map {
            UIBezierPath(roundedRect: $0, cornerRadius: cornerRadius).cgPath
        }
        let shouldAnimate = animated && !UIAccessibility.isReduceMotionEnabled

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if shouldAnimate {
            animatePath(of: dimLayer, to: dimPath)
            if let ringPath { animatePath(of: ringLayer, to: ringPath) }
            if dimLayer.opacity != (plain ? 0 : 1) { animateDimOpacity(to: plain ? 0 : 1) }
        }
        dimLayer.path = dimPath
        dimLayer.opacity = plain ? 0 : 1
        ringLayer.path = ringPath
        ringLayer.isHidden = padded == nil || plain
        CATransaction.commit()

        layoutBubble(animated: shouldAnimate)
    }

    /// Between two steps: the old message goes at once, and nothing is touchable until the next lands.
    func prepareForNextStep() {
        isHoleTouchable = false
        ringLayer.isHidden = true
        UIView.animate(withDuration: 0.15) { self.bubble.alpha = 0 }
    }

    private func path(hole: CGRect?) -> CGPath {
        let path = UIBezierPath(rect: bounds)
        // A zero-size hole rather than none: the two paths must have the same shape to animate.
        let rect = hole ?? CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
        path.append(UIBezierPath(roundedRect: rect, cornerRadius: hole == nil ? 0 : cornerRadius))
        return path.cgPath
    }

    private func animatePath(of layer: CAShapeLayer, to path: CGPath) {
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = layer.presentation()?.path ?? layer.path
        animation.toValue = path
        animation.duration = 0.35
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "path")
    }

    private func animateDimOpacity(to value: Float) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = dimLayer.presentation()?.opacity ?? dimLayer.opacity
        animation.toValue = value
        animation.duration = 0.35
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dimLayer.add(animation, forKey: "opacity")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dimLayer.frame = bounds
        ringLayer.frame = bounds
        dimLayer.path = path(hole: hole)
        layoutBubble(animated: false)
    }

    func layoutBubble(animated: Bool) {
        let width = min(
            bounds.width - 2 * CoachMarkLayout.margin - safeAreaInsets.left - safeAreaInsets.right,
            CoachMarkLayout.maxBubbleWidth)
        guard width > 0 else { return }

        let size = bubble.fittingSize(width: width)
        let frame = CoachMarkLayout.bubbleFrame(
            size: size, hole: hole, bounds: bounds, safeArea: safeAreaInsets, keyboardTop: keyboardTop,
            mayCoverHole: !isPlain)

        bubble.isHidden = frame == nil
        guard let frame, frame != bubble.frame else { return }
        let apply = { self.bubble.frame = frame }
        if animated, bubble.frame != .zero {
            UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut], animations: apply)
        } else {
            apply()
        }
    }

    @objc private func dimTapped() {
        onDimTapped?()
    }
}

/// Holds the overlay above the app. Its own window, because a view inside the app's window would sit
/// under a presented sheet, and each sheet is a step that has to be reachable. It is never made key,
/// so the text field the user is typing in keeps the keyboard.
final class CoachMarkOverlayWindow: UIWindow {
    let overlay = CoachMarkOverlayView()

    private final class RootViewController: UIViewController {
        var overlay: CoachMarkOverlayView?
        override func loadView() { view = overlay }
        override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    }

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = .normal + 1
        backgroundColor = .clear
        let root = RootViewController()
        root.overlay = overlay
        rootViewController = root
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `UIWindow` answers with itself when its content declines, which would keep the touch here.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }

    /// A tap on the bubble must not take key status, and with it the keyboard, from the app's window.
    override var canBecomeKey: Bool { false }
}
