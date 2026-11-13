//
//  CoachMarkTargetResolver.swift
//  Finova
//

import UIKit

/// Finds a step's view on the screen the user is actually looking at.
enum CoachMarkTargetResolver {

    /// The screen on top. Only this one is searched: the dashboard stays in the hierarchy behind a
    /// modal, and a target behind a modal is not something the user can reach.
    static func topViewController(from root: UIViewController?) -> UIViewController? {
        var current = root
        while true {
            if let presented = current?.presentedViewController, !presented.isBeingDismissed {
                current = presented
            } else if let navigation = current as? UINavigationController {
                current = navigation.visibleViewController ?? navigation.topViewController
                if current?.presentedViewController == nil { return current }
            } else {
                return current
            }
        }
    }

    /// The match the user can see most of. A carousel holds one copy per month, so the first match
    /// in the tree is often the card scrolled off to the side.
    static func find(_ target: CoachMarkTarget, in root: UIView, within window: UIWindow) -> UIView? {
        var best: (view: UIView, area: CGFloat)?
        walk(root) { view in
            guard view.accessibilityIdentifier == target.rawValue else { return }
            let frame = view.convert(view.bounds, to: window)
            let visible = frame.intersection(window.bounds)
            guard !visible.isNull, frame.width > 0, frame.height > 0 else { return }
            let area = visible.width * visible.height
            // Most of it has to be on screen, unless a scroll view can bring it there.
            let isMostlyVisible = area >= frame.width * frame.height * 0.5
            guard isMostlyVisible || verticalScrollAncestor(of: view) != nil else { return }
            if area > (best?.area ?? -1) { best = (view, area) }
        }
        return best?.view
    }

    /// Scrolls the target fully into view. Returns true if it moved anything, so the caller waits for
    /// the rect to settle. Vertical only: the dashboard's horizontal carousel must not change month.
    @discardableResult
    static func scrollIntoView(_ view: UIView) -> Bool {
        guard let scrollView = verticalScrollAncestor(of: view) else { return false }
        let frame = view.convert(view.bounds, to: scrollView)
        let visible = CGRect(origin: scrollView.contentOffset, size: scrollView.bounds.size)
            .inset(by: scrollView.adjustedContentInset)
        guard frame.minY < visible.minY || frame.maxY > visible.maxY else { return false }
        scrollView.scrollRectToVisible(frame.insetBy(dx: 0, dy: -Metrics.spacing4), animated: true)
        return true
    }

    private static func verticalScrollAncestor(of view: UIView) -> UIScrollView? {
        var current = view.superview
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView,
               scrollView.contentSize.height > scrollView.bounds.height + 1 {
                return scrollView
            }
            current = candidate.superview
        }
        return nil
    }

    /// Hidden or transparent subtrees are not walked: the dashboard keeps its content at alpha 0
    /// under the shimmer, and a card's other face stays in the tree while hidden.
    private static func walk(_ view: UIView, visit: (UIView) -> Void) {
        guard !view.isHidden, view.alpha > 0.01 else { return }
        visit(view)
        view.subviews.forEach { walk($0, visit: visit) }
    }
}
