//
//  AllocationTagStore.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import Foundation

// MARK: - Protocol

/// Persistence seam for the tag book.
///
/// The v1 implementation is a per-uid `UserDefaults` blob, which is device-local. The protocol exists
/// so the cloud-backed replacement - one settings `CKRecord` carrying the whole book, resolved
/// last-writer-wins on `updatedAt` - is a drop-in that no UI has to know about. Do not let callers
/// depend on anything below beyond these two methods.
protocol AllocationTagStoring: AnyObject {
    func load() -> AllocationTagBook
    /// A no-op when the loaded book could not be trusted; see `UserDefaultsAllocationTagStore`.
    func save(_ book: AllocationTagBook)
}

// MARK: - UserDefaults implementation

final class UserDefaultsAllocationTagStore: AllocationTagStoring {

    /// Versioned in the key as well as the payload. The key version lets a future incompatible format
    /// live alongside this one and be ignored without shipping a decoder for it; `schemaVersion`
    /// inside the payload covers additive migrations under the same key.
    private static let keyPrefix = "allocationTagBook_v1_"

    private let defaults: UserDefaults
    private let uidProvider: () -> String?

    /// Set when a stored book could not be trusted. While true, `save` refuses to write.
    ///
    /// A decode failure must never become data loss: the bytes we could not parse may be a newer
    /// format, or the victim of a bug we are about to fix. Overwriting them with `.empty` would
    /// silently destroy every tag the user made.
    private(set) var isReadOnly = false

    /// Both dependencies are injected because the tests must not touch `UserDefaults.standard` - the
    /// rest of the app hardcodes it, and a test run would otherwise mutate the developer's own state.
    init(
        defaults: UserDefaults = .standard,
        uidProvider: @escaping () -> String? = { UIDUserDefaultsManager.shared.currentUserUID }
    ) {
        self.defaults = defaults
        self.uidProvider = uidProvider
    }

    func load() -> AllocationTagBook {
        // No uid means no signed-in user. Deliberately does not fall back to an unkeyed slot: tags
        // are per-account, and a shared slot would leak one account's grouping into another's.
        guard let key = storageKey() else { return .empty }
        guard let data = defaults.data(forKey: key) else {
            isReadOnly = false
            return .empty
        }

        do {
            let decoded = try JSONDecoder().decode(AllocationTagBook.self, from: data)
            if decoded.schemaVersion > AllocationTagBook.currentSchemaVersion {
                // Only reachable by installing an older build over a newer one. Show what we can
                // understand, but never write our older shape back over it.
                logWarning(
                    "[AllocationTags] Book schemaVersion \(decoded.schemaVersion) is newer than "
                        + "\(AllocationTagBook.currentSchemaVersion); treating as read-only")
                isReadOnly = true
            } else {
                isReadOnly = false
            }
            return decoded.sanitized()
        } catch {
            logError("[AllocationTags] Failed to decode tag book: \(error). Keeping stored bytes.")
            isReadOnly = true
            return .empty
        }
    }

    func save(_ book: AllocationTagBook) {
        guard !isReadOnly else {
            logWarning("[AllocationTags] Refusing to write over a book that could not be read")
            return
        }
        guard let key = storageKey() else {
            logError("[AllocationTags] Cannot save tag book: no current user UID")
            return
        }

        var toStore = book.sanitized()
        toStore.updatedAt = Date()

        do {
            defaults.set(try JSONEncoder().encode(toStore), forKey: key)
        } catch {
            logError("[AllocationTags] Failed to encode tag book: \(error)")
        }
    }

    /// Exposed for the sign-out path only. Not part of `AllocationTagStoring`: deleting a user's
    /// groupings is a decision the account lifecycle makes, not something tag callers should reach for.
    func removeBook(forUid uid: String) {
        defaults.removeObject(forKey: Self.keyPrefix + uid)
    }

    private func storageKey() -> String? {
        guard let uid = uidProvider(), !uid.isEmpty else { return nil }
        return Self.keyPrefix + uid
    }
}
