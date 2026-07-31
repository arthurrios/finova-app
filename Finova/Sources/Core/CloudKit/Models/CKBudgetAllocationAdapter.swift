//
//  CKBudgetAllocationAdapter.swift
//  Finova
//

import CloudKit

extension BudgetAllocationModel: CKRecordConvertible {
    static var recordType: String { "BudgetAllocation" }

    var ckRecordID: CKRecord.ID? {
        guard let id = id else { return nil }
        return CKRecord.ID(
            recordName: "allocation-\(id)",
            zoneID: CloudKitManager.privateZoneID
        )
    }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        return toCKRecord(in: zoneID, storedRecordName: nil)
    }

    /// - Parameter db: the database this row belongs to. Explicit for the same reason as
    ///   `CKTransactionAdapter`: the adapter reads this row's identity columns, and defaulting to
    ///   `.shared` would read the wrong database whenever the caller is operating on another one.
    func toCKRecord(
        in zoneID: CKRecordZone.ID,
        storedRecordName: String?,
        db: DBHelper = .shared
    ) -> CKRecord {
        let recordName: String
        if let storedName = storedRecordName {
            recordName = storedName
        } else {
            // Phase 3A: Use UUID-based names for new records to avoid cross-device ID collisions
            recordName = "allocation-\(UUID().uuidString)"
        }
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["localId"] = (id ?? 0) as CKRecordValue
        record["monthDate"] = monthDate as CKRecordValue
        record["categoryKey"] = categoryKey as CKRecordValue
        record["allocatedAmount"] = allocatedAmount as CKRecordValue
        record["isRecurring"] = (isRecurring ? 1 : 0) as CKRecordValue
        record["parentAllocationId"] = parentAllocationId as CKRecordValue?
        record["userId"] = (UIDUserDefaultsManager.shared.currentUserUID ?? "") as CKRecordValue
        record["sharedGroupId"] = sharedGroupId as CKRecordValue?
        // Real last-edit time, never `Date()` — see CKTransactionAdapter for why stamping the push
        // time silently reverted the other device's newer edit.
        record["updatedAt"] = (updatedAt ?? record.creationDate ?? Date()) as CKRecordValue
        record["createdByUid"] = createdByUid as CKRecordValue?

        // Stable identity, and the only cross-device link a recurring allocation instance has to
        // its parent. `parentAllocationId` is a LOCAL autoincrement integer and had no remapping at
        // all on the receiving side — it was written straight through, so an instance either dangled
        // or silently pointed at an unrelated allocation.
        if let allocId = id, let ids = db.uuidIdentity(table: "BudgetAllocations", localId: allocId) {
            record["uuid"] = ids.uuid as CKRecordValue
            record["parentAllocationUuid"] = ids.parentUuid as CKRecordValue?
            // 2 = this device derives identities for the rows it GENERATES (recurring instances,
            // installment children, statements), so a receiver can match them exactly by uuid
            // and must NOT fall back to matching on title + amount + month.
            record["schemaVersion"] = 2 as CKRecordValue
        }
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> BudgetAllocationModel? {
        guard let monthDate = record["monthDate"] as? Int,
              let categoryKey = record["categoryKey"] as? String,
              let allocatedAmount = record["allocatedAmount"] as? Int
        else { return nil }

        let updatedAt = (record["updatedAt"] as? Date) ?? record.modificationDate ?? Date()

        return BudgetAllocationModel(
            id: record["localId"] as? Int,
            monthDate: monthDate,
            categoryKey: categoryKey,
            allocatedAmount: allocatedAmount,
            isRecurring: (record["isRecurring"] as? Int) == 1,
            parentAllocationId: record["parentAllocationId"] as? Int,
            sharedGroupId: record["sharedGroupId"] as? String,
            updatedAt: updatedAt,
            createdByUid: record["createdByUid"] as? String
        )
    }
}
