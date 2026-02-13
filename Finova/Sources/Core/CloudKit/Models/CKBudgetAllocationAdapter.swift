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

    func toCKRecord(in zoneID: CKRecordZone.ID, storedRecordName: String?) -> CKRecord {
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
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> BudgetAllocationModel? {
        guard let monthDate = record["monthDate"] as? Int,
              let categoryKey = record["categoryKey"] as? String,
              let allocatedAmount = record["allocatedAmount"] as? Int
        else { return nil }

        return BudgetAllocationModel(
            id: record["localId"] as? Int,
            monthDate: monthDate,
            categoryKey: categoryKey,
            allocatedAmount: allocatedAmount,
            isRecurring: (record["isRecurring"] as? Int) == 1,
            parentAllocationId: record["parentAllocationId"] as? Int,
            sharedGroupId: record["sharedGroupId"] as? String
        )
    }
}
