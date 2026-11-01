//
//  CoachMarkState.swift
//  Finova
//

import Foundation

/// Per-user memory of the guides. Deliberately thin: whether a setup is done comes from the ledger
/// (`CoachMarkFacts`), and this only holds what the ledger cannot say.
struct CoachMarkState: Codable, Equatable {
    /// Decided once, the first time this user reaches the dashboard: true only if they had no data
    /// at all. A false here is what keeps an existing user from ever being interrupted, and it must
    /// never be recomputed, or the first budget a new user saves would end their own guide chain.
    var isEnrolled: Bool?
    /// Skip all. Stops automatic guides for good; Settings still works.
    var isAutoDisabled = false
    var completed: Set<CoachMarkGuideID> = []
    var skipped: Set<CoachMarkGuideID> = []
    var autoStarts: [CoachMarkGuideID: Int] = [:]
}

/// Stored per Firebase uid, so two accounts on one phone never share progress, and signing out and
/// back in finds it where it was. The defaults are injected so tests never touch the real ones.
struct CoachMarkStateStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for uid: String) -> String { "coachMarks.state.\(uid)" }

    func load(uid: String) -> CoachMarkState {
        guard let data = defaults.data(forKey: key(for: uid)),
              let state = try? JSONDecoder().decode(CoachMarkState.self, from: data)
        else { return CoachMarkState() }
        return state
    }

    func save(_ state: CoachMarkState, uid: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key(for: uid))
    }

    func clear(uid: String) {
        defaults.removeObject(forKey: key(for: uid))
    }
}

/// The rules for what starts by itself. Pure, so the promises made to the user are unit tests.
enum CoachMarkGating {
    /// A guide the user keeps walking away from stops offering itself. Settings still has it.
    static let maxAutoStarts = 3

    /// Runs once per user. Returns the state with the enrollment decision made.
    static func enrolling(_ state: CoachMarkState, facts: CoachMarkFacts) -> CoachMarkState {
        guard state.isEnrolled == nil else { return state }
        var enrolled = state
        enrolled.isEnrolled = !facts.hasAnyData
        return enrolled
    }

    /// True when no fact can change the answer, so the ledger need not be read at all.
    static func isPermanentlyQuiet(_ state: CoachMarkState) -> Bool {
        state.isEnrolled == false || state.isAutoDisabled
    }

    static func isSetupDone(_ guide: CoachMarkGuideID, facts: CoachMarkFacts) -> Bool {
        switch guide {
        case .firstBudget: return facts.hasAnyBudget
        case .allocations: return facts.hasAnyAllocation
        case .salaryAndExpenses: return facts.hasRecurringTransaction
        case .firstTransaction: return facts.hasAnyTransaction
        case .creditCard: return facts.hasCreditCard
        case .budgetHistory, .dashboardTour: return false
        }
    }

    /// The next guide to run by itself, or nil. An enrollment decision must already be made.
    static func nextAutomaticGuide(
        state: CoachMarkState, facts: CoachMarkFacts
    ) -> CoachMarkGuideID? {
        guard state.isEnrolled == true, !state.isAutoDisabled else { return nil }

        return CoachMarkGuideID.automaticChain.first { guide in
            guard !isSetupDone(guide, facts: facts),
                  !state.completed.contains(guide),
                  !state.skipped.contains(guide),
                  (state.autoStarts[guide] ?? 0) < maxAutoStarts
            else { return false }
            // Allocations split a budget. With no budget the guide would point at nothing useful.
            return guide != .allocations || facts.hasAnyBudget
        }
    }
}
