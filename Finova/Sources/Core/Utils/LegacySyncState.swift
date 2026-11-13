//
//  LegacySyncState.swift
//  Finova
//
//  This build has no iCloud sync, but a device may have run an earlier 1.6.0 build that did. Those
//  builds kept a few passes off until the device had pulled everything from iCloud, because a
//  half-pulled database is missing rows and tombstones: a repair or a generator run on it decides
//  on partial data, and a later build that syncs again would upload the result.
//
//  So the same passes stay off here on exactly the devices where the sync build kept them off, and
//  run everywhere else. A device that never synced (every App Store install, which never had sync)
//  holds its whole ledger locally, so nothing is waiting to arrive and every pass runs.
//
//  Read-only on purpose: this build never writes any of these keys, so a later build that syncs
//  finds them as the sync build left them.
//

import Foundation

enum LegacySyncState {
    /// The sync build's "this device has completed a verified full pull" flag.
    static var isHydrated: Bool {
        UserDefaults.standard.bool(forKey: "syncFullPullVerified_v2")
    }

    /// Whether sync was switched on in an earlier build. Never set by this build.
    static var wasSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: "syncEnabled")
    }

    /// The sync build's "this device pushed its ledger first" flag. Devices without it only linked
    /// card purchases to statements that already existed, because the statements would arrive from
    /// iCloud.
    static var completedInitialPush: Bool {
        UserDefaults.standard.bool(forKey: "hasCompletedInitialCloudPush_v1")
    }

    /// True when this device never synced: sync was never switched on and no CloudKit change token
    /// was ever stored. Computed once per launch — this build cannot change the answer.
    static let neverSynced: Bool = {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "syncEnabled") else { return false }
        return !defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("ck_changeToken_") }
    }()

    /// Passes the sync build ran only once hydrated: series materialization (transactions and
    /// allocations), the duplicate sweep, the spending-month repair, and the balance start decision.
    static var canRunHydratedOnlyPasses: Bool {
        neverSynced || isHydrated
    }

    /// Repairs the sync build ran when hydrated OR with sync switched off. A device that never
    /// synced has sync off, so it is covered.
    static var canRunLocalRepairs: Bool {
        isHydrated || !wasSyncEnabled
    }

    /// Whether a card purchase may create the statement it belongs to, rather than only link to one
    /// that already exists.
    static var mayCreateStatements: Bool {
        neverSynced || completedInitialPush
    }
}
