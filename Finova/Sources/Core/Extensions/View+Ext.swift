//
//  View+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 08/05/25.
//

import Foundation
import UIKit

extension UIView {
    func pinToEdges(
        of superview: UIView,
        top: CGFloat? = nil,
        leading: CGFloat? = nil,
        bottom: CGFloat? = nil,
        trailing: CGFloat? = nil
    ) {
        translatesAutoresizingMaskIntoConstraints = false
        if let top = top {
            topAnchor.constraint(equalTo: superview.topAnchor, constant: top).isActive = true
        }
        if let leading = leading {
            leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: leading).isActive = true
        }
        if let bottom = bottom {
            bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: -bottom).isActive = true
        }
        if let trailing = trailing {
            trailingAnchor.constraint(equalTo: superview.trailingAnchor, constant: -trailing).isActive =
            true
        }
    }
    
    func pinToSuperview(with insets: UIEdgeInsets = .zero) {
        guard let superview = self.superview else {
            logError("pinToSuperview() called on view \(self) without superview")
            assertionFailure("pinToSuperview(): no superview for \(self)")
            return
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: superview.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: superview.trailingAnchor, constant: -insets.right),
            bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: -insets.bottom)
        ])
    }
    
    /// Applies the clear-glass treatment used by the 36x36 circular header buttons on iOS 26+.
    ///
    /// Every screen's `backButtonGlassContainer` grew its own byte-identical copy of this; the
    /// hide-values button reuses it rather than adding a seventh.
    func applyClearGlass(cornerRadius: CGFloat) {
        guard #available(iOS 26.0, *) else { return }
        let glassEffect = UIGlassEffect(style: .clear)
        glassEffect.isInteractive = true
        let glassView = UIVisualEffectView(effect: glassEffect)
        glassView.translatesAutoresizingMaskIntoConstraints = false
        // Note for callers: an interactive `UIGlassEffect` claims touches, and clearing
        // `isUserInteractionEnabled` on the effect view does not stop it. That is harmless when a
        // separate control sits above the glass, as it does on every back button here — but a
        // control that applies the glass to *itself* must override `hitTest`. See
        // `HideValuesButton`.
        insertSubview(glassView, at: 0)
        glassView.pinToSuperview()
        layer.cornerRadius = cornerRadius
        clipsToBounds = true
    }

    func superview<T: UIView>(of type: T.Type) -> T? {
        return next as? T ?? superview?.superview(of: T.self)
    }
    
    func findViewController() -> UIViewController? {
        if let nextResponder = self.next as? UIViewController {
            return nextResponder
        } else if let nextResponder = self.next as? UIView {
            return nextResponder.findViewController()
        } else {
            return nil
        }
    }
}
