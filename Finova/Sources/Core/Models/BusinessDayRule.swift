//
//  BusinessDayRule.swift
//  Finova
//

import Foundation

/// What to do when a transaction's date lands on a day the banks are shut.
///
/// Stored per transaction rather than read from a global setting at generation time, so a recurring
/// series keeps the rule it was created with. A setting consulted lazily would silently rewrite the
/// meaning of every existing series the moment the user changed it.
///
/// The rule shifts the *date* only. The month a row belongs to is always derived from the unadjusted
/// date - see `OccurrenceDateCalculator`.
enum BusinessDayRule: String, CaseIterable, Codable {

    /// Use the date exactly as picked. The default, and what every row created before this feature did.
    case exact

    /// Roll forward to the next business day. Salary and receivables.
    case nextBusinessDay

    /// Roll back to the previous business day. Debits that must clear before a deadline.
    case previousBusinessDay

    /// The single place an unknown or absent stored value collapses to a known one.
    ///
    /// `nil` is every row written before the column existed. An unrecognised string is a row written by
    /// a *newer* build that added a case - reading it as `.exact` is the honest answer, because we
    /// cannot apply a rule we do not implement, and it keeps the stored date (already adjusted by the
    /// newer client) intact.
    static func fromStored(_ raw: String?) -> BusinessDayRule {
        guard let raw, let rule = BusinessDayRule(rawValue: raw) else { return .exact }
        return rule
    }

    var title: String {
        "businessDayRule.\(rawValue).title".localized
    }

    /// Whether this rule can move a date at all. Lets callers skip the walk and the UI hide its hint.
    var shiftsDates: Bool {
        self != .exact
    }
}
