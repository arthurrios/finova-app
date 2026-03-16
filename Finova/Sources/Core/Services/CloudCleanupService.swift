//
//  CloudCleanupService.swift
//  Finova
//
//  Created by Arthur Rios on 16/03/26.
//

import CloudKit
import Foundation

// MARK: - Types

struct CloudCleanupProgress {
    let phase: Phase
    let currentRecordType: String
    let currentIndex: Int
    let totalTypes: Int

    enum Phase {
        case scanning
        case deleting
    }
}

struct CloudCleanupScanResult {
    let breakdown: [(recordType: String, cloud: Int, local: Int, orphans: Int)]
    let orphanIDs: [CKRecord.ID]

    var totalCloud: Int { breakdown.reduce(0) { $0 + $1.cloud } }
    var totalLocal: Int { breakdown.reduce(0) { $0 + $1.local } }
    var totalOrphans: Int { orphanIDs.count }
}

struct CloudCleanupDeletionResult {
    let totalDeleted: Int
    let totalErrors: Int
}

enum CloudCleanupError: Error {
    case noGroup
    case fetchFailed(Error)
}

// MARK: - Delegate

protocol CloudCleanupServiceDelegate: AnyObject {
    func cloudCleanupDidUpdateProgress(_ progress: CloudCleanupProgress)
    func cloudCleanupDidCompleteScan(_ result: CloudCleanupScanResult)
    func cloudCleanupDidCompleteDeletion(_ result: CloudCleanupDeletionResult)
    func cloudCleanupDidFail(_ error: CloudCleanupError)
}

// MARK: - Service

final class CloudCleanupService {
    weak var delegate: CloudCleanupServiceDelegate?

    private let db = DBHelper.shared
    private let cloudKitManager = CloudKitManager.shared

    private var cachedScanResult: CloudCleanupScanResult?

    private let recordTypes: [(ckType: String, table: String, displayName: String)] = [
        ("Transaction", "Transactions", "Transactions"),
        ("Budget", "Budgets", "Budgets"),
        ("CreditCard", "CreditCards", "Credit Cards"),
        ("CreditCardStatement", "CreditCardStatements", "Statements"),
        ("BudgetAllocation", "BudgetAllocations", "Allocations"),
    ]

    /// Set of CK record type names we track, for filtering during zone fetch
    private lazy var trackedCKTypes: Set<String> = {
        Set(recordTypes.map { $0.ckType })
    }()

    // MARK: - Public API

    func startScan() {
        guard let destination = resolveDestination() else {
            delegate?.cloudCleanupDidFail(.noGroup)
            return
        }

        scanZone(destination: destination)
    }

    func confirmDeletion() {
        guard let result = cachedScanResult, !result.orphanIDs.isEmpty else { return }

        guard let destination = resolveDestination() else {
            delegate?.cloudCleanupDidFail(.noGroup)
            return
        }

        let batchSize = 400
        let batches = stride(from: 0, to: result.orphanIDs.count, by: batchSize).map {
            Array(result.orphanIDs[$0..<min($0 + batchSize, result.orphanIDs.count)])
        }

        var totalDeleted = 0
        var totalErrors = 0

        func runBatch(index: Int) {
            guard index < batches.count else {
                logWarning("[CloudCleanup] Finished: \(totalDeleted) deleted, \(totalErrors) errors")
                let deletionResult = CloudCleanupDeletionResult(
                    totalDeleted: totalDeleted, totalErrors: totalErrors
                )
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.cloudCleanupDidCompleteDeletion(deletionResult)
                }
                return
            }

            let progress = CloudCleanupProgress(
                phase: .deleting,
                currentRecordType: "",
                currentIndex: totalDeleted,
                totalTypes: result.orphanIDs.count
            )
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.cloudCleanupDidUpdateProgress(progress)
            }

            let batch = batches[index]
            let modifyOp = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: batch)
            modifyOp.modifyRecordsResultBlock = { opResult in
                switch opResult {
                case .success:
                    totalDeleted += batch.count
                    logWarning("[CloudCleanup] Batch \(index + 1)/\(batches.count): deleted \(batch.count)")
                case .failure(let error):
                    totalErrors += batch.count
                    logWarning("[CloudCleanup] Batch \(index + 1)/\(batches.count) error: \(error)")
                }
                runBatch(index: index + 1)
            }
            destination.database.add(modifyOp)
        }

        runBatch(index: 0)
    }

    func cancelCleanup() {
        cachedScanResult = nil
    }

    // MARK: - Private — Destination Resolution

    private struct Destination {
        let zoneID: CKRecordZone.ID
        let database: CKDatabase
    }

    private func resolveDestination() -> Destination? {
        // Mirror mode owner → group zone in private DB
        if MirrorModeManager.shared.isEnabled,
           let groupId = MirrorModeManager.shared.linkedGroupId
        {
            let zoneID = CKRecordZone.ID(
                zoneName: "Group-\(groupId)", ownerName: CKCurrentUserDefaultName
            )
            return Destination(zoneID: zoneID, database: cloudKitManager.privateDatabase)
        }

        // Check for a budget group
        let groups = BudgetGroupRepository().fetchAllGroups()
        if let group = groups.first {
            if group.isOwner {
                let zoneID = CKRecordZone.ID(
                    zoneName: "Group-\(group.id)", ownerName: CKCurrentUserDefaultName
                )
                return Destination(zoneID: zoneID, database: cloudKitManager.privateDatabase)
            } else {
                let ownerName = group.ckZoneOwner ?? CKCurrentUserDefaultName
                let zoneID = CKRecordZone.ID(
                    zoneName: "Group-\(group.id)", ownerName: ownerName
                )
                return Destination(zoneID: zoneID, database: cloudKitManager.sharedDatabase)
            }
        }

        // No group — same-account sync uses FinovaPrivateZone
        return Destination(
            zoneID: CloudKitManager.privateZoneID,
            database: cloudKitManager.privateDatabase
        )
    }

    // MARK: - Private — Zone Scan (fetchZoneChanges with nil token)

    /// Fetches ALL records in the zone using CKFetchRecordZoneChangesOperation
    /// (no queryable index required), then groups by record type and compares with local DB.
    private func scanZone(destination: Destination) {
        let progress = CloudCleanupProgress(
            phase: .scanning,
            currentRecordType: "",
            currentIndex: 0,
            totalTypes: recordTypes.count
        )
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.cloudCleanupDidUpdateProgress(progress)
        }

        // Collect cloud record IDs grouped by CK record type
        var cloudIDsByType: [String: [CKRecord.ID]] = [:]
        for info in recordTypes {
            cloudIDsByType[info.ckType] = []
        }

        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = nil // nil = full fetch from beginning

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [destination.zoneID],
            configurationsByRecordZoneID: [destination.zoneID: config]
        )

        operation.recordWasChangedBlock = { [weak self] _, result in
            switch result {
            case .success(let record):
                let recordType = record.recordType
                if self?.trackedCKTypes.contains(recordType) == true {
                    cloudIDsByType[recordType, default: []].append(record.recordID)
                }
            case .failure(let error):
                logWarning("[CloudCleanup] Record fetch error: \(error)")
            }
        }

        operation.recordZoneChangeTokensUpdatedBlock = { _, _, _ in
            // Not needed — we don't persist the token
        }

        operation.recordZoneFetchResultBlock = { [weak self] _, result in
            switch result {
            case .success:
                logWarning("[CloudCleanup] Zone fetch complete")
            case .failure(let error):
                logWarning("[CloudCleanup] Zone fetch failed: \(error)")
                DispatchQueue.main.async {
                    self?.delegate?.cloudCleanupDidFail(.fetchFailed(error))
                }
            }
        }

        operation.fetchRecordZoneChangesResultBlock = { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.processZoneScanResults(cloudIDsByType: cloudIDsByType)
            case .failure(let error):
                logWarning("[CloudCleanup] Overall fetch failed: \(error)")
                DispatchQueue.main.async {
                    self.delegate?.cloudCleanupDidFail(.fetchFailed(error))
                }
            }
        }

        logWarning("[CloudCleanup] Starting zone scan for \(destination.zoneID.zoneName)")
        destination.database.add(operation)
    }

    private func processZoneScanResults(cloudIDsByType: [String: [CKRecord.ID]]) {
        var breakdown: [(recordType: String, cloud: Int, local: Int, orphans: Int)] = []
        var allOrphanIDs: [CKRecord.ID] = []

        for info in recordTypes {
            let cloudIDs = cloudIDsByType[info.ckType] ?? []
            let localNames = Set(db.fetchAllCKRecordNamesIncludingDeleted(table: info.table))
            let orphans = cloudIDs.filter { !localNames.contains($0.recordName) }

            breakdown.append((
                recordType: info.displayName,
                cloud: cloudIDs.count,
                local: localNames.count,
                orphans: orphans.count
            ))
            allOrphanIDs.append(contentsOf: orphans)

            logWarning("[CloudCleanup] \(info.ckType): cloud=\(cloudIDs.count), local=\(localNames.count), orphans=\(orphans.count)")
        }

        let result = CloudCleanupScanResult(
            breakdown: breakdown, orphanIDs: allOrphanIDs
        )
        cachedScanResult = result
        logWarning("[CloudCleanup] Scan complete: \(result.totalCloud) cloud, \(result.totalLocal) local, \(result.totalOrphans) orphans")

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.cloudCleanupDidCompleteScan(result)
        }
    }
}
