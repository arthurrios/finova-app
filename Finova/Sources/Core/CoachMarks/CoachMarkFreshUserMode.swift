//
//  CoachMarkFreshUserMode.swift
//  Finova
//

#if DEMO
import Foundation

/// Finova Demo only: launch with `-coachMarksFreshUser YES` to get a first-time user, for proving and
/// recording the guides. The demo seed is skipped (`DemoSeedGenerator.needsSeed`), so uninstall first
/// to start from an empty ledger.
enum CoachMarkFreshUserMode {
    private static let argumentKey = "coachMarksFreshUser"
    private static let appliedKey = "coachMarks.freshUserApplied"

    /// `-coachMarksReplayGuide <rawValue>` opens straight into one guide, as its Settings row would.
    static var replayGuide: CoachMarkGuideID? {
        UserDefaults.standard.string(forKey: "coachMarksReplayGuide").flatMap(CoachMarkGuideID.init)
    }

    static var isActive: Bool {
        UserDefaults.standard.bool(forKey: argumentKey)
    }

    /// Once per install, so quitting and reopening with the same flag still shows what a real user
    /// would see, which is no repeat.
    static func applyIfNeeded(uid: String, store: CoachMarkStateStore) {
        guard isActive, !UserDefaults.standard.bool(forKey: appliedKey) else { return }
        UserDefaults.standard.set(true, forKey: appliedKey)
        store.clear(uid: uid)
    }
}
#endif
