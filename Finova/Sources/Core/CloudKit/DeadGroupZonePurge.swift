//
//  DeadGroupZonePurge.swift
//  Finova
//
//  User-invoked maintenance — "Delete unused group zones" in Sync Settings. NOT one-shot, and not
//  safe to delete: it is a shipped action, not a migration. (It began life as a DEBUG-only launch
//  hook that ran once; nothing that deletes cloud data should fire unprompted, so it moved behind an
//  explicit confirmation.)
//
//  Background: `softDeleteGroup` only ever set `is_deleted = 1` locally; nothing deleted the
//  group's `Group-<id>` CloudKit zone. Zones from deleted groups therefore accumulated in the
//  private database. A device that had never seen those groups locally would rediscover the zones
//  and insert each one as a LIVE group (the soft-delete guard in `processIncomingBudgetGroup` only
//  fires when a local row already exists), then pull transactions out of every dead zone.
//
//  `BudgetGroupService.deleteGroup` now deletes the zone as part of deleting a group, so new orphans
//  are not created. This stays available for zones orphaned before that landed, and for the case
//  where zone deletion fails at delete time and leaves one behind.
//
//  Note a zone can legitimately be ABSENT for a soft-deleted group: if `createCloudKitShare` never
//  completed, no zone was created. On the reporter's device 9 soft-deleted groups had only 1 zone
//  between them. That is not an error, and the purge simply finds nothing to do for the other 8.
//

import CloudKit
import Foundation

enum DeadGroupZonePurge {

    /// Zones that must NEVER be deleted, whatever the rest of the logic concludes.
    /// `FinovaPrivateZone` holds every personal record; `_defaultZone` is system-owned.
    private static let protectedZoneNames: Set<String> = ["FinovaPrivateZone", "_defaultZone"]

    private static let hasRunKey = "hasPurgedDeadGroupZones_v1"

    /// Enumerates the private database, reports exactly what it is about to destroy (including a
    /// per-zone record count), deletes only the zones that pass every guard, then re-enumerates to
    /// confirm the result. Runs at most once per install.
    ///
    /// Guards, all of which must pass for a zone to be deleted:
    ///   1. The zone exists in CloudKit and is named `Group-<id>`.
    ///   2. A local `BudgetGroups` row exists for that id — an unknown zone is never touched.
    ///   3. That row has `is_deleted = 1` (the group was deleted on this device).
    ///   4. That row is owned by the current user — we must not delete someone else's zone.
    ///   5. The zone name is not in `protectedZoneNames`.
    /// Runs the purge because the user asked, whether or not it has run before.
    ///
    /// The one-shot flag exists so an automatic launch hook could not repeat a destructive CloudKit
    /// operation. It should not stand in the way of someone asking deliberately — and once consumed
    /// there was no way to ask again short of reinstalling.
    static func runNow() {
        UserDefaults.standard.removeObject(forKey: hasRunKey)
        runOnceIfNeeded()
    }

    static func runOnceIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: hasRunKey) else {
            logInfo("[Purge] Already ran on this install — skipping")
            return
        }
        guard AuthenticationManager.shared.currentUser != nil else {
            logWarning("[Purge] No signed-in user yet — will retry on a later launch")
            return
        }

        logWarning("[Purge] ===== DEAD GROUP ZONE PURGE — START =====")

        enumeratePrivateZones { cloudZoneNames in
            guard !cloudZoneNames.isEmpty else {
                logError("[Purge] Zone enumeration returned nothing — aborting (not marking as run)")
                return
            }
            logWarning("[Purge] CloudKit private zones (\(cloudZoneNames.count)): \(cloudZoneNames.sorted())")

            // Every local group row, soft-deleted ones included.
            let localRows = DBHelper.shared.fetchBudgetGroupRows(
                "SELECT id, name, owner_id, owner_name, owner_email, currency, ck_record_id, ck_share_url, ck_zone_owner, created_at, updated_at, is_deleted FROM BudgetGroups"
            )
            logWarning("[Purge] Local group rows: \(localRows.count) (\(localRows.filter { $0.isDeleted }.count) soft-deleted)")

            var toDelete: [String] = []
            var kept: [String] = []

            for zoneName in cloudZoneNames.sorted() {
                if protectedZoneNames.contains(zoneName) {
                    kept.append("\(zoneName) — protected")
                    continue
                }
                guard zoneName.hasPrefix("Group-") else {
                    kept.append("\(zoneName) — not a group zone")
                    continue
                }
                let groupId = String(zoneName.dropFirst("Group-".count))
                guard let row = localRows.first(where: { $0.id == groupId }) else {
                    kept.append("\(zoneName) — NO local row (unknown group, never touch)")
                    continue
                }
                guard row.isDeleted else {
                    kept.append("\(zoneName) — group '\(row.name)' is LIVE")
                    continue
                }
                guard row.isOwner else {
                    kept.append("\(zoneName) — group '\(row.name)' not owned by current user")
                    continue
                }
                toDelete.append(zoneName)
            }

            logWarning("[Purge] --- KEEPING \(kept.count) zone(s) ---")
            for line in kept { logWarning("[Purge]   KEEP   \(line)") }
            logWarning("[Purge] --- DELETING \(toDelete.count) zone(s) ---")
            for name in toDelete { logWarning("[Purge]   DELETE \(name)") }

            guard !toDelete.isEmpty else {
                logWarning("[Purge] Nothing to delete — marking as run")
                UserDefaults.standard.set(true, forKey: hasRunKey)
                logWarning("[Purge] ===== DEAD GROUP ZONE PURGE — DONE (no-op) =====")
                return
            }

            // Count what each doomed zone holds, so the log records exactly what was destroyed.
            countRecords(inZones: toDelete) { counts in
                var grandTotal = 0
                for name in toDelete {
                    let summary = counts[name] ?? [:]
                    let total = summary.values.reduce(0, +)
                    grandTotal += total
                    let breakdown = summary.isEmpty
                        ? "empty"
                        : summary.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                    logWarning("[Purge]   \(name): \(total) record(s) — \(breakdown)")
                }
                logWarning("[Purge] Total records about to be destroyed: \(grandTotal)")

                deleteZones(named: toDelete)
            }
        }
    }

    // MARK: - Steps

    private static func enumeratePrivateZones(completion: @escaping ([String]) -> Void) {
        var names: [String] = []
        let op = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
        op.perRecordZoneResultBlock = { zoneID, result in
            if case .success = result { names.append(zoneID.zoneName) }
        }
        op.fetchRecordZonesResultBlock = { result in
            if case .failure(let error) = result {
                logError("[Purge] Zone enumeration failed: \(error.localizedDescription)")
                completion([])
                return
            }
            completion(names)
        }
        op.qualityOfService = .userInitiated
        CloudKitManager.shared.privateDatabase.add(op)
    }

    /// Counts records per type in each zone WITHOUT feeding them through the sync pipeline —
    /// importing dead-group records is exactly what this purge exists to prevent.
    private static func countRecords(
        inZones zoneNames: [String],
        completion: @escaping ([String: [String: Int]]) -> Void
    ) {
        let zoneIDs = zoneNames.map { CKRecordZone.ID(zoneName: $0, ownerName: CKCurrentUserDefaultName) }
        var counts: [String: [String: Int]] = [:]
        let lock = NSLock()

        var configs: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [:]
        for id in zoneIDs {
            let cfg = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            cfg.previousServerChangeToken = nil     // full scan
            configs[id] = cfg
        }

        let op = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs, configurationsByRecordZoneID: configs)
        op.recordWasChangedBlock = { recordID, result in
            guard case .success(let record) = result else { return }
            lock.lock()
            counts[recordID.zoneID.zoneName, default: [:]][record.recordType, default: 0] += 1
            lock.unlock()
        }
        op.fetchRecordZoneChangesResultBlock = { result in
            if case .failure(let error) = result {
                logWarning("[Purge] Record count scan incomplete (non-fatal): \(error.localizedDescription)")
            }
            completion(counts)
        }
        op.qualityOfService = .userInitiated
        CloudKitManager.shared.privateDatabase.add(op)
    }

    private static func deleteZones(named zoneNames: [String]) {
        // Final assertion: the protected zones must never reach the delete list.
        for name in zoneNames where protectedZoneNames.contains(name) {
            logError("[Purge] ABORT — protected zone '\(name)' reached the delete list")
            return
        }

        let zoneIDs = zoneNames.map { CKRecordZone.ID(zoneName: $0, ownerName: CKCurrentUserDefaultName) }
        let op = CKModifyRecordZonesOperation(recordZonesToSave: nil, recordZoneIDsToDelete: zoneIDs)
        op.modifyRecordZonesResultBlock = { result in
            switch result {
            case .success:
                logWarning("[Purge] ✅ Deleted \(zoneIDs.count) zone(s)")
                UserDefaults.standard.set(true, forKey: hasRunKey)
                // Drop their change tokens so nothing keeps referring to zones that no longer exist.
                for name in zoneNames {
                    SyncStateManager.shared.saveChangeToken(nil, for: name, database: "private")
                }
                verifyAfterDelete(expectedGone: Set(zoneNames))
            case .failure(let error):
                // Not marked as run, so the next launch retries.
                logError("[Purge] ❌ Delete failed — will retry next launch: \(error.localizedDescription)")
                logWarning("[Purge] ===== DEAD GROUP ZONE PURGE — FAILED =====")
            }
        }
        op.qualityOfService = .userInitiated
        CloudKitManager.shared.privateDatabase.add(op)
    }

    private static func verifyAfterDelete(expectedGone: Set<String>) {
        enumeratePrivateZones { remaining in
            let remainingSet = Set(remaining)
            logWarning("[Purge] Zones remaining (\(remaining.count)): \(remaining.sorted())")

            let stillPresent = expectedGone.intersection(remainingSet)
            if stillPresent.isEmpty {
                logWarning("[Purge] ✅ VERIFIED — all \(expectedGone.count) dead zone(s) gone")
            } else {
                logError("[Purge] ⚠️ Still present after delete: \(stillPresent.sorted())")
            }

            for name in protectedZoneNames where !remainingSet.contains(name) {
                logError("[Purge] ⚠️⚠️ PROTECTED ZONE '\(name)' IS MISSING — investigate immediately")
            }
            logWarning("[Purge] ===== DEAD GROUP ZONE PURGE — DONE =====")
        }
    }
}
