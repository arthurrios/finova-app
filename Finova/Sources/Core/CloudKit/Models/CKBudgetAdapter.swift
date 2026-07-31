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

    /// A budget's CloudKit name, which must be unique per SCOPE and not merely per month.
    ///
    /// The personal form is deliberately unchanged. Every budget already in CloudKit is stored as
    /// `budget-<monthDate>`, and CKRecord names are immutable — a different name means delete +
    /// create, which a device on an older build would receive as a deletion and faithfully apply.
    ///
    /// Group budgets get the group appended. CloudKit itself does not need this (names are unique
    /// per zone, and the two live in different zones), but the local `ck_record_id` UNIQUE index is
    /// zone-blind: with one name for both scopes, whichever row stored it second was rejected, left
    /// with a NULL `ck_record_id`, and could never be matched by `markAsSynced` — so it was pushed
    /// again on every sync cycle, forever.
    ///
    /// Scoping the local index instead would be worse: ~20 sites look budgets up by record name
    /// alone, and `hardDeleteByCKRecordName` would then delete BOTH rows.
    static func recordName(monthDate: Int, sharedGroupId: String?) -> String {
        guard let groupId = sharedGroupId, !groupId.isEmpty else { return "budget-\(monthDate)" }
        return "budget-\(monthDate)-\(groupId)"
    }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(
            recordName: Self.recordName(monthDate: monthDate, sharedGroupId: sharedGroupId),
            zoneID: zoneID
        )
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["monthDate"] = monthDate as CKRecordValue
        record["amount"] = amount as CKRecordValue
        record["userId"] = (UIDUserDefaultsManager.shared.currentUserUID ?? "") as CKRecordValue
        record["sharedGroupId"] = sharedGroupId as CKRecordValue?
        // Real last-edit time, never `Date()` — see CKTransactionAdapter for why stamping the push
        // time silently reverted the other device's newer edit.
        record["updatedAt"] = (updatedAt ?? record.creationDate ?? Date()) as CKRecordValue
        record["createdByUid"] = createdByUid as CKRecordValue?
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> BudgetModel? {
        guard let monthDate = record["monthDate"] as? Int,
              let amount = record["amount"] as? Int
        else { return nil }

        let updatedAt = (record["updatedAt"] as? Date) ?? record.modificationDate ?? Date()

        return BudgetModel(
            monthDate: monthDate,
            amount: amount,
            sharedGroupId: record["sharedGroupId"] as? String,
            updatedAt: updatedAt,
            createdByUid: record["createdByUid"] as? String
        )
    }
}
