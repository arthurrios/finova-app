//
//  CategorySpendHistory.swift
//  Finova
//
//  Created by Arthur Rios on 07/08/26.
//

import Foundation

/// How much of one category's allocation the user has actually spent, across closed months.
///
/// Reports a **range**, not an average, and that is the whole design. An average hides divergence:
/// eight months of 20/90/15/85/30/95/25/80 percent average to about half, with a confident-looking
/// sample size behind it, and half is precisely the figure not to plan against. A range shows the
/// divergence instead, so a reader seeing `5-140%` needs no warning that it is not plannable.
///
/// Deliberately **not** wired into any money figure. `AllocationBalanceProjection` still assumes the
/// whole plan will be spent, which is the conservative bound and the only one that never over-promises
/// - the app schedules negative-balance warnings elsewhere, and a projection that revised the balance
/// upward would work against them. This type informs; it does not forecast.
///
/// Like `AllocationBalanceProjection` it holds no repository, no service and no `Date()`: the caller
/// supplies the per-month ratios and this only describes them.
struct CategorySpendHistory: Equatable {

    /// Closed months looked at. Bounded by what the dashboard can even reach - the carousel spans
    /// `-12...24`, so twelve is the whole of the past it exposes.
    static let sampleWindow = 12

    /// Below this, a range is two points and a gap; there is nothing to characterise. Four out of a
    /// possible twelve is a real floor without being unreachable.
    static let minimumSamples = 4

    /// Where a range stops being actionable. `50-90%` is borderline useful, `20-95%` is not.
    static let maximumSpread = 0.40

    /// Months in the window where this category had a non-zero allocation. A month with spending but
    /// no allocation is not in here: "fraction of plan used" has no meaning without a plan, and
    /// scoring it zero would punish a category the user simply had not budgeted yet.
    let sampleCount: Int

    /// Lowest and highest fraction of that month's own allocation spent, across the samples.
    ///
    /// **Unclamped.** The clamp that used to bound this at 1.0 existed to protect a money figure, and
    /// this no longer feeds one - so `1.40` survives, because "you usually go past this budget" is
    /// exactly what an overspender needs to read.
    let lowestRatio: Double
    let highestRatio: Double

    var spread: Double { highestRatio - lowestRatio }

    /// What the screen says. Three cases, so nothing is ever silently withheld - a category whose
    /// months disagree gets told so, rather than dropping off the screen with no explanation.
    enum Verdict: Equatable {
        case notEnoughHistory
        case consistent(low: Double, high: Double, months: Int)
        case varied(low: Double, high: Double, months: Int)
    }

    /// The single place the two thresholds are applied, so the copy and any future caller cannot
    /// disagree about what "enough" and "too varied" mean.
    var verdict: Verdict {
        guard sampleCount >= Self.minimumSamples else { return .notEnoughHistory }
        return spread <= Self.maximumSpread
            ? .consistent(low: lowestRatio, high: highestRatio, months: sampleCount)
            : .varied(low: lowestRatio, high: highestRatio, months: sampleCount)
    }

    /// The range as whole percents.
    ///
    /// Rounding lives here rather than in a formatter because the two ends can round together - 0.552
    /// and 0.558 are both 56 - and `56-56%` reads as a bug. A caller that finds `low == high` should
    /// render a single value.
    var percentRange: (low: Int, high: Int) {
        (low: Int((lowestRatio * 100).rounded()), high: Int((highestRatio * 100).rounded()))
    }

    /// No usable history. Distinct from "zero percent spent", which is a real and meaningful sample.
    static let none = CategorySpendHistory(ratiosByMonth: [:])

    /// - Parameter ratiosByMonth: `used / allocated` per closed month anchor. Keyed by month rather
    ///   than passed as a bare array so one month cannot contribute twice, which would inflate
    ///   `sampleCount` and with it the reader's confidence.
    init(ratiosByMonth: [Int: Double]) {
        let ratios = ratiosByMonth.values
        self.sampleCount = ratios.count
        self.lowestRatio = ratios.min() ?? 0
        self.highestRatio = ratios.max() ?? 0
    }
}
