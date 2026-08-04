//
//  AllocationTagBookSync.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import CloudKit
import Foundation

/// Syncs the allocation tag book as a single CloudKit record, on its own path.
///
/// Deliberately **not** routed through `SyncEngine.pushBatches`. That engine is built around
/// table-to-recordType pairs: it gathers rows with `sync_status = 'pending'`, remaps autoincrement ids
/// across devices, keeps per-row `ck_system_fields`, and calls `clearSyncedLocalData()` before applying
/// a pull. The tag book is one blob in `UserDefaults` with none of those needs, and threading it through
/// would mean touching the eighteen hard-coded table-name lists in `DBHelper` plus the recordType
/// switches in a 4,300-line engine - for a record that has no rows.
///
/// Isolation is also the safety property that matters most here. `pushBatches` stops every remaining
/// save batch on a schema error, so one bad field halts syncing for everything. A failure on this path
/// stops tags travelling and nothing else.
///
/// **Conflict resolution is last-writer-wins on `updatedAt`, over the whole book.** That is a real
/// limitation, not an oversight: two devices that each add a tag while offline will keep only the book
/// that was written later, losing the other's tag. Merging per tag would fix additions but resurrect
/// deletions, because a blob carries no tombstones - a tag deleted on one device is simply absent, which
/// is indistinguishable from a tag the other device has not seen yet. Whole-book LWW is the honest
/// behaviour for a preference-shaped payload; per-tag merging needs per-tag timestamps and tombstones,
/// which is the point at which this should become a real synced entity instead.
final class AllocationTagBookSync {

    static let recordType = "AllocationTagBook"

    private let store: AllocationTagStoring
    private let operations: CloudKitOperationsProvider
    private let uidProvider: () -> String?
    private let zoneID: CKRecordZone.ID
    /// Applies an adopted book. Injected so tests can observe adoption without standing up the service.
    private let onAdopt: (AllocationTagBook) -> Void
    /// Whether the record type exists in the production schema.
    ///
    /// Injected rather than read from `CloudKitSchemaFlags` at each use, so the push and pull paths are
    /// testable while the shipping flag is still off. Reading the constant directly would leave the whole
    /// syncer unexercised until someone flipped it - which is the worst moment to discover it is wrong.
    private let isSchemaDeployed: Bool

    /// Set while a push is in flight, so a burst of tag edits collapses into one save rather than
    /// racing several against the same change tag and losing all but one to `serverRecordChanged`.
    private var isPushing = false
    private var needsAnotherPush = false

    init(
        store: AllocationTagStoring,
        operations: CloudKitOperationsProvider,
        uidProvider: @escaping () -> String? = { UIDUserDefaultsManager.shared.currentUserUID },
        zoneID: CKRecordZone.ID = CloudKitManager.privateZoneID,
        isSchemaDeployed: Bool = CloudKitSchemaFlags.allocationTagBookDeployed,
        onAdopt: ((AllocationTagBook) -> Void)? = nil
    ) {
        self.store = store
        self.operations = operations
        self.uidProvider = uidProvider
        self.zoneID = zoneID
        self.isSchemaDeployed = isSchemaDeployed
        self.onAdopt = onAdopt ?? { AllocationTagService.shared.adoptFromCloud($0) }
    }

    // MARK: - Record identity

    /// Includes the uid even though the private database is already per-iCloud-account: one account can
    /// sign into the app with more than one Firebase user, and a fixed name would hand them a shared
    /// book. Names are scoped to the zone, so this is unique without being guessable across zones.
    private func recordName(for uid: String) -> String {
        "allocationTagBook-\(uid)"
    }

    // MARK: - Push

    /// Sends the local book up. Safe to call on every edit; bursts coalesce.
    func push(completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard isSchemaDeployed else {
            completion?(.success(()))
            return
        }
        guard let uid = uidProvider(), !uid.isEmpty else {
            completion?(.success(()))
            return
        }

        if isPushing {
            needsAnotherPush = true
            completion?(.success(()))
            return
        }
        isPushing = true

        let book = store.load()
        let record = makeRecord(book: book, uid: uid)

        // `.ifServerRecordUnchanged` rather than `.allKeys`: a blind overwrite would silently discard a
        // peer's newer book. A rejection here is the signal to compare timestamps and decide.
        operations.saveRecords(
            [record], database: .private, savePolicy: .ifServerRecordUnchanged,
            perRecordHandler: { [weak self] _, result in
                if case .success(let saved) = result {
                    self?.storeSystemFields(from: saved)
                }
            },
            completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.finishPush(completion: completion, result: .success(()))

                case .failure(let error):
                    if self.isServerRecordChanged(error) {
                        // Someone else wrote first. Pull, resolve by timestamp, and push again only if
                        // the local book is genuinely the newer one.
                        self.resolveConflictThenRetry(uid: uid, completion: completion)
                    } else {
                        logError("[AllocationTags] Book push failed: \(error)")
                        self.finishPush(completion: completion, result: .failure(error))
                    }
                }
            })
    }

    private func finishPush(
        completion: ((Result<Void, Error>) -> Void)?,
        result: Result<Void, Error>
    ) {
        isPushing = false
        if needsAnotherPush {
            needsAnotherPush = false
            push()
        }
        completion?(result)
    }

    // MARK: - Pull

    /// Fetches the book from CloudKit and adopts it when it is newer than the local one.
    ///
    /// A query rather than a change-token fetch: this is one record whose name we can compute, and it
    /// does not belong to the zone-change stream the engine consumes for tables.
    func pull(completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard isSchemaDeployed else {
            completion?(.success(()))
            return
        }
        guard let uid = uidProvider(), !uid.isEmpty else {
            completion?(.success(()))
            return
        }

        fetchRemote(uid: uid) { [weak self] result in
            switch result {
            case .success(let remote):
                if let remote {
                    self?.adoptIfNewer(remote)
                }
                completion?(.success(()))
            case .failure(let error):
                logError("[AllocationTags] Book pull failed: \(error)")
                completion?(.failure(error))
            }
        }
    }

    private func fetchRemote(
        uid: String,
        completion: @escaping (Result<CKRecord?, Error>) -> Void
    ) {
        let wanted = recordName(for: uid)
        var found: CKRecord?

        operations.queryRecords(
            recordType: Self.recordType,
            zoneID: zoneID,
            database: .private,
            recordHandler: { record in
                // Filtered by name rather than by predicate: `userId` needs to be a queryable index in
                // the schema for a predicate to work, and an unindexed field fails the whole query.
                if record.recordID.recordName == wanted { found = record }
            },
            completion: { result in
                switch result {
                case .success: completion(.success(found))
                case .failure(let error):
                    // An absent record type reads as an error before the first device has ever written
                    // one. Nothing to adopt is not a failure.
                    if Self.isUnknownRecordType(error) {
                        completion(.success(nil))
                    } else {
                        completion(.failure(error))
                    }
                }
            })
    }

    /// - Returns: whether the remote book replaced the local one.
    @discardableResult
    private func adoptIfNewer(_ record: CKRecord) -> Bool {
        // Keep the change tag either way: the next push needs it whether or not we take the payload.
        storeSystemFields(from: record)

        guard let remote = decode(record) else { return false }
        let local = store.load()

        // Strictly newer, so an equal timestamp leaves local alone. Two books stamped the same instant
        // are almost certainly the same book echoing back from our own push.
        guard remote.updatedAt > local.updatedAt else { return false }

        // Through the service, not `store.adopt` directly: the service caches the decoded book for the
        // dashboard's rebuild paths, so writing behind it would leave the card showing the old tags until
        // something else happened to invalidate.
        onAdopt(remote)
        logInfo("[AllocationTags] Adopted a newer tag book from CloudKit")
        return true
    }

    // MARK: - Conflict

    private func resolveConflictThenRetry(
        uid: String,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        fetchRemote(uid: uid) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finishPush(completion: completion, result: .failure(error))

            case .success(let remote):
                guard let remote else {
                    // Rejected as changed but nothing is there: our stored change tag is stale. Drop it
                    // and let the next push create the record fresh.
                    self.store.cloudSystemFields = nil
                    self.finishPush(completion: completion, result: .success(()))
                    return
                }

                if self.adoptIfNewer(remote) {
                    // Theirs won; there is nothing of ours left to send.
                    self.finishPush(completion: completion, result: .success(()))
                } else {
                    // Ours is newer. Retry once, now carrying the server's current change tag.
                    self.isPushing = false
                    self.needsAnotherPush = false
                    self.pushOverwriting(uid: uid, base: remote, completion: completion)
                }
            }
        }
    }

    /// The single retry. Uses the just-fetched record as the base so the change tag is current, and does
    /// not recurse: a second rejection means another device is writing in a loop, and giving up leaves
    /// the local book intact to be pushed on the next sync.
    private func pushOverwriting(
        uid: String,
        base: CKRecord,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        isPushing = true
        let book = store.load()
        apply(book: book, uid: uid, to: base)

        operations.saveRecords(
            [base], database: .private, savePolicy: .ifServerRecordUnchanged,
            perRecordHandler: { [weak self] _, result in
                if case .success(let saved) = result { self?.storeSystemFields(from: saved) }
            },
            completion: { [weak self] result in
                if case .failure(let error) = result {
                    logWarning("[AllocationTags] Book push lost a second race; leaving it for the next sync: \(error)")
                }
                self?.finishPush(completion: completion, result: .success(()))
            })
    }

    // MARK: - Record mapping

    private func makeRecord(book: AllocationTagBook, uid: String) -> CKRecord {
        let fresh = CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: recordName(for: uid), zoneID: zoneID))
        // The archived record carries the server's change tag, which is what makes
        // `.ifServerRecordUnchanged` mean anything. Same unarchive shape as
        // `SyncEngine.buildCKRecord`, including discarding an archive whose zone has moved.
        let record = archivedRecord() ?? fresh
        apply(book: book, uid: uid, to: record)
        return record
    }

    private func archivedRecord() -> CKRecord? {
        guard let data = store.cloudSystemFields,
            let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data)
        else { return nil }
        unarchiver.requiresSecureCoding = true
        guard let archived = CKRecord(coder: unarchiver) else { return nil }
        unarchiver.finishDecoding()

        guard archived.recordID.zoneID == zoneID else {
            logWarning("[AllocationTags] Stored change tag belongs to another zone; ignoring it")
            return nil
        }
        return archived
    }

    private func apply(book: AllocationTagBook, uid: String, to record: CKRecord) {
        record["payload"] = (try? JSONEncoder().encode(book)) as CKRecordValue?
        record["updatedAt"] = book.updatedAt as CKRecordValue
        record["userId"] = uid as CKRecordValue
    }

    private func decode(_ record: CKRecord) -> AllocationTagBook? {
        guard let payload = record["payload"] as? Data else { return nil }
        do {
            var book = try JSONDecoder().decode(AllocationTagBook.self, from: payload)
            // Trust the record's own field over the payload's: the field is what both sides compare.
            if let stamped = record["updatedAt"] as? Date { book.updatedAt = stamped }
            return book
        } catch {
            logError("[AllocationTags] Could not decode the cloud tag book: \(error)")
            return nil
        }
    }

    private func storeSystemFields(from record: CKRecord) {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        store.cloudSystemFields = archiver.encodedData
    }

    // MARK: - Error shapes

    private func isServerRecordChanged(_ error: Error) -> Bool {
        if let ckError = error as? CKError {
            if ckError.code == .serverRecordChanged { return true }
            // A batch failure reports the real reason per record.
            if let partial = ckError.partialErrorsByItemID?.values {
                return partial.contains { ($0 as? CKError)?.code == .serverRecordChanged }
            }
        }
        return false
    }

    private static func isUnknownRecordType(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        // CloudKit reports a never-written type as an invalid-arguments query failure.
        return ckError.code == .unknownItem || ckError.code == .invalidArguments
    }
}
