//
//  CKBudgetAdapter.swift
//  Finova
//

import CloudKit

extension BudgetModel: CKRecordConvertible {
    static var recordType: String { "Budget" }

    var ckRecordID: CKRecord.ID? {
        return CKRecord.ID(
            recordName: "budget-\(monthDate)",
            zoneID: CloudKitManager.privateZoneID
        )
    }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(
            recordName: "budget-\(monthDate)",
            zoneID: zoneID
        )
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["monthDate"] = monthDate as CKRecordValue
        record["amount"] = amount as CKRecordValue
        record["userId"] = (UIDUserDefaultsManager.shared.currentUserUID ?? "") as CKRecordValue
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> BudgetModel? {
        guard let monthDate = record["monthDate"] as? Int,
              let amount = record["amount"] as? Int
        else { return nil }

        return BudgetModel(monthDate: monthDate, amount: amount)
    }
}
