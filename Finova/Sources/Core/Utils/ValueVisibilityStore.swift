//
//  ValueVisibilityStore.swift
//  Finova
//
//  Created by Arthur Rios on 05/08/26.
//

import Foundation

/// The single owner of the "hide values" flag.
///
/// Before this existed the flag lived in four places at once — UserDefaults, a private
/// `isValuesHidden` mirror inside each card, and a `userInfo` payload travelling along a
/// delegate → closure → notification chain that only the dashboard could start. The mirrors
/// went stale and the chain couldn't reach anything that wasn't a visible carousel cell, which
/// is why the setting appeared to "lose reference" when navigating.
///
/// The rule now: nobody caches the flag. Every render pulls it from here, and every writer
/// goes through `setHidden`.
final class ValueVisibilityStore {
    static let shared = ValueVisibilityStore()

    private init() {}

    /// Deliberately not backed by an in-memory mirror. `UserDefaults.standard.bool` is already an
    /// in-memory read, and a second copy is exactly what used to drift out of sync.
    var isHidden: Bool {
        UserDefaultsManager.getHideValues()
    }

    /// The only writer. Persists first, then broadcasts. A write that doesn't change the value
    /// broadcasts nothing, so a double-tap can't cause two table reloads.
    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        UserDefaultsManager.setHideValues(hidden)
        NotificationCenter.default.post(name: .valueVisibilityDidChange, object: self)
    }

    func toggle() {
        setHidden(!isHidden)
    }

    /// Observes changes and hands back a token that deregisters itself when it deallocates.
    ///
    /// Callers store the token in a property; when the observing view dies, so does the
    /// observation. This exists because the hand-rolled `addObserver` calls it replaces were
    /// missing their `deinit` in two of three views, leaving stale observers behind.
    ///
    /// The handler is delivered on the main queue — every one of them touches UIKit — and
    /// receives the current value purely for convenience. The notification itself carries no
    /// payload; `isHidden` remains the only source of truth.
    func observe(_ handler: @escaping (Bool) -> Void) -> ValueVisibilityObservation {
        let token = NotificationCenter.default.addObserver(
            forName: .valueVisibilityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            handler(self?.isHidden ?? false)
        }
        return ValueVisibilityObservation(token: token)
    }
}

/// Owns a `NotificationCenter` registration for as long as it is retained.
final class ValueVisibilityObservation {
    private let token: NSObjectProtocol

    fileprivate init(token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}
