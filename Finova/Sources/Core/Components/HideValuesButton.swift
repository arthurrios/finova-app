//
//  HideValuesButton.swift
//  Finova
//
//  Created by Arthur Rios on 05/08/26.
//

import UIKit

/// The eye toggle that hides and reveals monetary values.
///
/// One component for every surface. It replaces two hand-rolled `UIView` + `UITapGestureRecognizer`
/// toggles on the dashboard cards — which needed `ensureToggleGestureRecognizer()` to survive
/// being re-parented between two containers — and is dropped straight into the inner-screen
/// headers.
///
/// The button owns nothing but its own appearance. It writes to `ValueVisibilityStore` on tap and
/// derives its icon from that store, so it is correct regardless of creation order, cell reuse, or
/// whether the surrounding view has been configured yet.
final class HideValuesButton: UIButton {

    enum Style {
        /// The dark gradient month cards: a bare 36x36 tappable icon, no glass.
        case onCard
        /// The light `Colors.gray100` screen headers: matches the circular glass back button
        /// sitting on the opposite side of the same header.
        case onHeader
    }

    /// Optional hook for callers that need to do extra work on toggle, such as reloading a table.
    /// The store write happens either way, so most call sites leave this nil.
    var onToggle: ((Bool) -> Void)?

    private let style: Style
    private var observation: ValueVisibilityObservation?

    private lazy var iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = false
        return imageView
    }()

    // MARK: - Initialization

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        setupUI()
        // Held for the button's lifetime; the token deregisters itself on deinit.
        observation = ValueVisibilityStore.shared.observe { [weak self] _ in
            self?.updateIcon()
        }
        updateIcon()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        accessibilityIdentifier = "hideValuesButton"
        accessibilityTraits = .button

        addSubview(iconView)

        NSLayoutConstraint.activate([
            // 36x36 lives on the button itself rather than a wrapper, so it can stand in for the
            // old toggle container that other views constrain against.
            widthAnchor.constraint(equalToConstant: Metrics.hideValuesButtonSize),
            heightAnchor.constraint(equalToConstant: Metrics.hideValuesButtonSize),

            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.hideValuesIconSize),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.hideValuesIconSize),
        ])

        switch style {
        case .onCard:
            iconView.tintColor = Colors.gray100
        case .onHeader:
            applyClearGlass(cornerRadius: Metrics.hideValuesButtonSize / 2)
            if #available(iOS 26.0, *) {
                iconView.tintColor = Colors.gray700
            } else {
                iconView.tintColor = Colors.gray500
            }
        }

        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    // MARK: - Actions

    @objc
    private func handleTap() {
        ValueVisibilityStore.shared.toggle()
        // The store has already broadcast, so `updateIcon` has run via the observation.
        onToggle?(ValueVisibilityStore.shared.isHidden)
    }

    // MARK: - Appearance

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Covers the case where the flag changed while this button was off-screen or its cell was
        // sitting in the reuse pool, so no notification reached it.
        updateIcon()
    }

    private func updateIcon() {
        let isHidden = ValueVisibilityStore.shared.isHidden
        // Inverted on purpose: the icon shows the action, not the state. While values are hidden
        // the open eye offers "reveal".
        let iconName = isHidden ? "eye" : "eye-closed"
        iconView.image = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate)
        accessibilityLabel =
            (isHidden ? "hideValues.a11y.show" : "hideValues.a11y.hide").localized
    }
}
