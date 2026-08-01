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

    /// - Parameter db: the database this row belongs to. Explicit because the adapter reads the
    ///   row's identity columns and its referents' CK names; defaulting to `.shared` silently read
    ///   the WRONG database whenever the caller was operating on another one (as the two-device
    ///   test harness does), which produced nil references that then "resolved" by coincidence.
    func toCKRecord(
        in zoneID: CKRecordZone.ID,
        storedRecordName: String?,
        db: DBHelper = .shared
    ) -> CKRecord {
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
            record["isStatementOverridden"] = (db.isStatementOverridden(transactionId: txId) ? 1 : 0) as CKRecordValue
            // Early installment payment. Only the UUID travels — the local integer is another
            // device's autoincrement id and would point at an unrelated row there, the same reason
            // `parentTransactionUuid` exists. `settledByTransactionUuid` is written even when nil so
            // reversing an early payment propagates as a cleared pointer rather than a stale one.
            //
            // `earlyPaymentSchema` is what makes an absent pointer readable as a deliberate clear.
            // Without it the receiver cannot tell "this device reversed the early payment" from
            // "this device is on an older build that has never heard of one", and would un-settle
            // installments every time a legacy peer re-pushed an untouched row.
            //
            // Version 1 introduced the early-payment pointer, version 2 the cancellation pointer.
            // The receiver gates each field on the version that introduced it, so a v1 peer's silence
            // about cancellation is read as "doesn't know", not "not cancelled".
            record["earlyPaymentSchema"] = 2 as CKRecordValue
            record["settledByTransactionUuid"] = db.settledByTransactionUuid(transactionId: txId) as CKRecordValue?
            record["isEarlyPayment"] = (db.isEarlyPayment(transactionId: txId) ? 1 : 0) as CKRecordValue
            record["cancelledByTransactionUuid"] =
                db.installmentPointerUuid(.cancelled, transactionId: txId) as CKRecordValue?
            record["isCancellationRefund"] =
                (db.isCancellationRefund(transactionId: txId) ? 1 : 0) as CKRecordValue
        }

        // Stable, device-independent identity and relationships.
        //
        // These are what let the receiving device resolve a reference REGARDLESS of arrival order.
        // The `*CKRecordName` fields below are nil until the referent has been pushed, so a record
        // that arrives before its parent/card cannot be linked and the sender's meaningless local
        // integer ends up in the receiver's database. A uuid exists from row creation, so it is
        // always available and always correct.
        if let txId = id, let ids = db.uuidIdentity(table: "Transactions", localId: txId) {
            record["uuid"] = ids.uuid as CKRecordValue
            record["creditCardUuid"] = ids.creditCardUuid as CKRecordValue?
            record["statementUuid"] = ids.statementUuid as CKRecordValue?
            record["parentTransactionUuid"] = ids.parentUuid as CKRecordValue?
            // 2 = this device derives identities for the rows it GENERATES (recurring instances,
            // installment children, statements), so a receiver can match them exactly by uuid
            // and must NOT fall back to matching on title + amount + month.
            record["schemaVersion"] = 2 as CKRecordValue
        }

        // Legacy cross-device remapping fields. Still written so a device on an older build keeps
        // working exactly as before; the uuid path above supersedes them and they can be dropped
        // once every peer reports schemaVersion >= 1.
        if let ccId = creditCardId {
            record["creditCardCKRecordName"] = CreditCardRepository(db: db).fetchCKRecordName(for: ccId) as CKRecordValue?
        }
        if let stmtId = statementId {
            record["statementCKRecordName"] = StatementRepository(db: db).fetchCKRecordName(for: stmtId) as CKRecordValue?
        }
        if let parentId = parentTransactionId {
            let parentCKName = TransactionRepository(db: db).fetchCKRecordName(for: parentId)
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
