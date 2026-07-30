//
//  CKTransactionAdapter.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit

extension Transaction: CKRecordConvertible {
    static var recordType: String { "Transaction" }

    var ckRecordID: CKRecord.ID? {
        guard let id = id else { return nil }
        return CKRecord.ID(
            recordName: "transaction-\(id)",
            zoneID: CloudKitManager.privateZoneID
        )
    }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        return toCKRecord(in: zoneID, storedRecordName: nil)
    }

    func toCKRecord(in zoneID: CKRecordZone.ID, storedRecordName: String?) -> CKRecord {
        let recordID: CKRecord.ID
        if let storedName = storedRecordName {
            recordID = CKRecord.ID(recordName: storedName, zoneID: zoneID)
        } else {
            // Phase 3A: Use UUID-based names for new records to avoid cross-device ID collisions
            recordID = CKRecord.ID(
                recordName: "transaction-\(UUID().uuidString)",
                zoneID: zoneID
            )
        }

        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["localId"] = (id ?? 0) as CKRecordValue
        record["title"] = title as CKRecordValue
        record["amount"] = amount as CKRecordValue
        record["type"] = type.rawValue as CKRecordValue
        record["category"] = category.rawValue as CKRecordValue
        record["date"] = date as CKRecordValue
        record["budgetMonthDate"] = budgetMonthDate as CKRecordValue
        record["isRecurring"] = ((isRecurring ?? false) ? 1 : 0) as CKRecordValue
        record["hasInstallments"] = ((hasInstallments ?? false) ? 1 : 0) as CKRecordValue
        record["parentTransactionId"] = parentTransactionId as CKRecordValue?
        record["installmentNumber"] = installmentNumber as CKRecordValue?
        record["totalInstallments"] = totalInstallments as CKRecordValue?
        record["originalAmount"] = originalAmount as CKRecordValue?
        record["creditCardId"] = creditCardId as CKRecordValue?
        record["statementId"] = statementId as CKRecordValue?
        record["isCreditCardStatement"] = ((isCreditCardStatement ?? false) ? 1 : 0) as CKRecordValue
        if let txId = id {
            record["isStatementOverridden"] = (DBHelper.shared.isStatementOverridden(transactionId: txId) ? 1 : 0) as CKRecordValue
        }

        // Store CK record names for cross-device ID remapping
        if let ccId = creditCardId {
            record["creditCardCKRecordName"] = CreditCardRepository().fetchCKRecordName(for: ccId) as CKRecordValue?
        }
        if let stmtId = statementId {
            record["statementCKRecordName"] = StatementRepository().fetchCKRecordName(for: stmtId) as CKRecordValue?
        }

        // Phase 4A: Store parent's CK record name for cross-device parent resolution
        if let parentId = parentTransactionId {
            let parentCKName = TransactionRepository().fetchCKRecordName(for: parentId)
            record["parentCKRecordName"] = parentCKName as CKRecordValue?
        }

        // The receiving device orders conflicts on this value, so it must be the real last-edit
        // time — never `Date()`. Stamping "now" made every push look newer than the other device's
        // genuine edit, so any non-edit re-push (mirror reconcile, CC repair, force re-push) silently
        // reverted it. `nil` only happens for legacy rows written before `updated_at` existed; those
        // have no basis for comparison, so fall back to the record's creation date if we have one.
        record["updatedAt"] = (updatedAt ?? record.creationDate ?? Date()) as CKRecordValue
        record["createdByUid"] = createdByUid as CKRecordValue?

        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> Transaction? {
        guard
            let title = record["title"] as? String,
            let amount = record["amount"] as? Int,
            let typeRaw = record["type"] as? String,
            let type = TransactionType(rawValue: typeRaw),
            let categoryRaw = record["category"] as? String,
            let category = TransactionCategory(rawValue: categoryRaw),
            let date = record["date"] as? Date
        else { return nil }

        let localId = record["localId"] as? Int
        let budgetMonthDate = record["budgetMonthDate"] as? Int ?? 0

        let updatedAt = (record["updatedAt"] as? Date) ?? record.modificationDate ?? Date()

        let uiData = UITransactionData(
            id: localId,
            title: title,
            amount: amount,
            dateTimestamp: Int(date.timeIntervalSince1970),
            budgetMonthDate: budgetMonthDate,
            isRecurring: (record["isRecurring"] as? Int) == 1,
            hasInstallments: (record["hasInstallments"] as? Int) == 1,
            parentTransactionId: record["parentTransactionId"] as? Int,
            installmentNumber: record["installmentNumber"] as? Int,
            totalInstallments: record["totalInstallments"] as? Int,
            originalAmount: record["originalAmount"] as? Int,
            creditCardId: record["creditCardId"] as? Int,
            statementId: record["statementId"] as? Int,
            isCreditCardStatement: (record["isCreditCardStatement"] as? Int) == 1,
            updatedAt: updatedAt,
            createdByUid: record["createdByUid"] as? String,
            category: category,
            type: type
        )

        return Transaction(data: uiData)
    }
}
