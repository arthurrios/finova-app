//
//  AuthProviding.swift
//  Finova
//
//  The seam between the sync engine and Firebase Auth.
//
//  `SyncEngine` guards every entry point on "is somebody signed in?", and that question resolved
//  straight to `Auth.auth().currentUser` — a live Firebase session no unit test can create. So the
//  guard always failed under test, and every SyncEngineTest could only observe the not-signed-in
//  path. It also meant the Transparent Mode projection fan-out, which lives past that guard inside
//  `pushLocalChanges`, had no way to be exercised at all.
//

import Foundation

protocol AuthProviding {
    /// The signed-in user's uid, or nil.
    var currentUserId: String? { get }
}

extension AuthProviding {
    var isAuthenticated: Bool { currentUserId != nil }
}

/// Production: the real Firebase session.
struct FirebaseAuthProvider: AuthProviding {
    var currentUserId: String? { AuthenticationManager.shared.currentUser?.uid }
}

/// Tests: a session that is whatever the test says it is.
struct StubAuthProvider: AuthProviding {
    var currentUserId: String?

    init(currentUserId: String?) { self.currentUserId = currentUserId }
}
