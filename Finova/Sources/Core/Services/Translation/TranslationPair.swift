//
//  TranslationPair.swift
//  Finova
//

import Foundation
import UIKit

// MARK: - Identity

/// A source→target language pairing.
///
/// Replaces the `"\(source)>\(target)"` string this feature used to pass around and re-`split` at
/// four call sites. Two things were wrong with that: `"auto"` sat in the same namespace as real
/// BCP-47 codes, so a language actually called that would have been indistinguishable from "we don't
/// know"; and a target containing `>` mis-parsed silently.
///
/// Both codes are bare language codes - `TagLanguageDetector.normalized` on the way in. Regions are
/// meaningful for the display cache (pt-BR and pt-PT are different answers) but not for asking the
/// framework what a phrase means.
struct TranslationPair: Hashable, CustomStringConvertible {
    let source: String
    let target: String

    var description: String { "\(source)>\(target)" }
}

/// A specific tag, under a specific name, for a specific target.
///
/// The name is part of the identity on purpose: a rename is a different question, so it should not
/// inherit the previous answer. Replaces `"\(tagId)|\(name)|\(target)"`, which could not be filtered
/// by target without `hasSuffix("|\(target)")` - and that mis-matches any tag whose *name* ends in
/// `|pt`.
struct TagFingerprint: Hashable {
    let tagId: String
    let name: String
    let target: String
}

// MARK: - Outcomes

/// Why a translate attempt ended.
///
/// The distinction between these is load-bearing. The previous design collapsed every non-success
/// into `[]`, so "the user backgrounded the app", "the framework has no model for this pair" and
/// "this is a proper noun it declined to translate" were indistinguishable - and all three
/// blacklisted the tags for the rest of the process.
enum TagTranslationOutcome: Equatable {
    /// May be partial: a response is absent for any tag the framework declined. Those are per-tag
    /// refusals, and only those tags are blacklisted.
    case translated([TagTranslationResult])
    /// The languages are not on the device. The ONLY outcome that may offer a download.
    case notInstalled
    /// This device cannot do this pair, now or later. Stable enough to stop asking.
    case unsupported
    /// Backgrounded, or the caller's task was cancelled. Blacklist nothing - this says nothing about
    /// whether the work would have succeeded.
    case cancelled
    /// Transient. Worth another attempt, but not an unbounded number of them.
    case failed
}

enum TagLanguageDownloadOutcome: Equatable {
    /// The system accepted the request and began downloading. NOT "the download finished" -
    /// `prepareTranslation()` returns when it starts.
    case started
    /// The user declined or dismissed Apple's sheet. A legitimate choice, not an error.
    case cancelled
    case unsupported
    case failed
}

// MARK: - Presentation seam

/// The screen Apple's download sheet is presented from.
///
/// Injected rather than discovered. The previous design walked the window's controller hierarchy to
/// guess a presenter and then string-matched the class name to rule out the splash - which broke as
/// soon as the walk stopped at the `UINavigationController` wrapping it. A download only ever starts
/// from a Settings tap, so the screen that owns the tap can simply hand itself over.
///
/// A protocol rather than `UIViewController` so tests can assert which presenter was used without
/// standing up a view hierarchy.
@MainActor
protocol TranslationSheetPresenting: AnyObject {
    var presentedViewController: UIViewController? { get }
    func present(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)?)
}

extension UIViewController: TranslationSheetPresenting {}
