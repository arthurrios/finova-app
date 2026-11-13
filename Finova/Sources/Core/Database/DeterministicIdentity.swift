//
//  DeterministicIdentity.swift
//  Finova
//
//  Identity for rows the app GENERATES rather than the user creating: recurring instances,
//  installment children, and credit-card statements.
//
//  Stage 1 gave stored rows a stable uuid, derived from their CloudKit record name. That works
//  because the name already existed — one device minted it, pushed it, and every other device
//  derived the same uuid from it. Generated rows have no such anchor. They are materialised lazily,
//  on whichever device happens to open the month first, and the insert trigger gives each one a
//  RANDOM v4 uuid. Two devices that both render March before either syncs therefore mint two
//  different identities for the same logical row, and the receiving device cannot tell they are the
//  same thing.
//
//  That is precisely why `ConflictResolver` still carries content-based matchers — "recurring
//  instance by parent + month", "title + amount + month", "creditCardId + closingDate". Content
//  matching is the worst available conflict-resolution strategy: two genuinely distinct coffees for
//  the same amount in the same month get merged into one, and one coffee generated on two devices
//  becomes two. No ordering rule can repair a wrong match — you resolve the conflict correctly, on
//  the wrong pair of records.
//
//  A UUIDv5 over (parent identity + bucket) removes the guesswork. Both devices compute the SAME
//  uuid from data they already hold, with no coordination and no network, exactly as
//  derive-don't-mint did for stored rows.
//
//  IMPORTANT: apply these only to NEWLY generated rows. Recomputing the uuid of a row that has
//  already been pushed is a re-key, and because CKRecord names are immutable a re-key means delete
//  plus create — which a device on an older build would receive as a deletion and faithfully apply.
//  `DBHelper.assignDeterministicUuid` enforces this by refusing any row that has a `ck_record_id`.
//

import CryptoKit
import Foundation

enum DeterministicIdentity {

    /// Fixed namespace for this app's derived identifiers. It must never change: every derived uuid
    /// in every user's database and in CloudKit is a function of it.
    private static let namespace = UUID(uuidString: "6E9C1B7A-4F3D-4A21-9E62-8D5C0A17B3F4")!

    /// RFC 4122 §4.3 name-based UUID, SHA-1 variant. Returns the canonical uppercase form so derived
    /// values are indistinguishable from `UUID().uuidString` and from the insert trigger's output.
    static func v5(_ name: String) -> String {
        var hasher = Insecure.SHA1()
        withUnsafeBytes(of: namespace.uuid) { hasher.update(bufferPointer: $0) }
        hasher.update(data: Data(name.utf8))
        var bytes = Array(hasher.finalize().prefix(16))

        bytes[6] = (bytes[6] & 0x0F) | 0x50  // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // RFC 4122 variant

        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        let groups = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { range in
            String(hex[hex.index(hex.startIndex, offsetBy: range.lowerBound)
                       ..< hex.index(hex.startIndex, offsetBy: range.upperBound)])
        }
        return groups.joined(separator: "-")
    }

    // MARK: - Generated rows
    //
    // Each key is (what kind of thing) + (its parent's stable identity) + (the bucket that makes it
    // unique within that parent). The prefixes keep the keyspaces apart, so a transaction instance
    // and an allocation instance for the same month can never collide.

    /// One recurring transaction instance per (series, month).
    static func recurringInstance(parentUuid: String, monthDate: Int) -> String {
        v5("txinstance|\(parentUuid)|\(monthDate)")
    }

    /// One installment child per (parent purchase, installment number). Numbered rather than
    /// month-bucketed because a series can be re-dated, and #3 stays #3.
    static func installment(parentUuid: String, installmentNumber: Int) -> String {
        v5("installment|\(parentUuid)|\(installmentNumber)")
    }

    /// One allocation instance per (series, month).
    static func allocationInstance(parentUuid: String, monthDate: Int) -> String {
        v5("allocinstance|\(parentUuid)|\(monthDate)")
    }

    /// One statement per (card, month) — which is also an invariant the app already enforces with a
    /// repair pass. Deriving the identity this way makes it true by construction instead.
    static func statement(cardUuid: String, statementMonth: Int) -> String {
        v5("statement|\(cardUuid)|\(statementMonth)")
    }
}
