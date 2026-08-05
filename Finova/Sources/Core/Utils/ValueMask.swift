//
//  ValueMask.swift
//  Finova
//
//  Created by Arthur Rios on 05/08/26.
//

import Foundation
import UIKit

/// Masking for monetary values when the user has hidden them.
///
/// This deliberately sits *beside* `CurrencyUtils` rather than inside it. `Int.currencyString`
/// also feeds push-notification bodies (`TransactionNotificationManager` and friends) and
/// destructive-action confirmation alerts. If the formatter itself consulted the visibility
/// store, turning on privacy mode would silently bullet out lock-screen notifications and the
/// "delete this transaction for R$ 120,00?" prompt. So masking is an explicitly-named layer that
/// wraps the formatter, and call sites opt in.
enum ValueMask {
    /// The one canonical mask. Six bullets — previously this literal was duplicated at six sites
    /// in two different lengths, so the tag chips masked to a visibly shorter string than the
    /// cards beside them.
    static let placeholder = "••••••"

    static var isActive: Bool {
        ValueVisibilityStore.shared.isHidden
    }

    /// What VoiceOver reads in place of an amount. Reading out literal bullets is useless, and
    /// reading the real number would defeat the feature entirely.
    static var accessibilityLabel: String {
        "hideValues.a11y.valueHidden".localized
    }
}

extension Int {
    /// The `hidden` parameter defaults to the live store; it is explicit so tests and snapshots
    /// can render the masked branch without mutating global state.
    func maskedCurrencyString(hidden: Bool = ValueMask.isActive) -> String {
        hidden ? ValueMask.placeholder : currencyString
    }

    func maskedCompactCurrencyString(hidden: Bool = ValueMask.isActive) -> String {
        hidden ? ValueMask.placeholder : compactCurrencyString
    }

    /// Compact, negatives carrying an explicit `-`. Replaces `BudgetCard.signedCompactString`;
    /// the `abs` avoids the double minus `compactCurrencyString` would otherwise produce.
    ///
    /// When masked the sign goes with the digits: a red `-••••••` would leak that the user is
    /// over budget, which is part of what they asked to hide.
    func maskedSignedCompactString(hidden: Bool = ValueMask.isActive) -> String {
        if hidden { return ValueMask.placeholder }
        return self < 0 ? "-" + abs(self).compactCurrencyString : compactCurrencyString
    }

    /// The masked attributed string carries only the body font across its whole range: there is no
    /// currency symbol in "••••••", so applying the smaller `symbolFont` to part of the bullets
    /// would read as a rendering glitch. The font matches the unmasked string so baselines and row
    /// heights don't shift when the user toggles.
    func maskedCurrencyAttributedString(
        symbolFont: UIFont? = nil,
        font: Fonts? = nil,
        hidden: Bool = ValueMask.isActive
    ) -> NSAttributedString {
        guard hidden else {
            return currencyAttributedString(symbolFont: symbolFont, font: font)
        }
        let bodyFont = font?.font ?? UIFont.preferredFont(forTextStyle: .body)
        return NSAttributedString(
            string: ValueMask.placeholder,
            attributes: [.font: bodyFont]
        )
    }
}

extension String {
    /// For amounts a view model has already formatted — `BudgetAllocationDetailsViewModel`
    /// exposes `formattedAllocated` / `formattedUsed` / `formattedRemaining`. Masking at the view
    /// keeps the visibility store out of the view models.
    func maskedIfHidden(_ hidden: Bool = ValueMask.isActive) -> String {
        hidden ? ValueMask.placeholder : self
    }
}
