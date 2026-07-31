//
//  CKCreditCardStatementAdapter.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit

extension CreditCardStatement: CKRecordConvertible {
    static var recordType: String { "CreditCardStatement" }

    var ckRecordID: CKRecord.ID? {
        guard let id = id else { return nil }
        return CKRecord.ID(
            recordName: "statement-\(id)",
            zoneID: targetZoneID(for: creditCardId)
        )
    }

    func targetZoneID(for cardId: Int) -> CKRecordZone.ID {
        if let card = CreditCardRepository().fetchCard(byId: cardId),
           let groupId = card.sharedGroupId {
            return CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: CKCurrentUserDefaultName)
        }
        return CloudKitManager.privateZoneID
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
            recordName = "statement-\(UUID().uuidString)"
        }
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["localId"] = (id ?? 0) as CKRecordValue
        record["creditCardId"] = creditCardId as CKRecordValue
        // Store credit card's CK record name for cross-device ID remapping
        if let cardCKName = CreditCardRepository(db: db).fetchCKRecordName(for: creditCardId) {
            record["creditCardCKRecordName"] = cardCKName as CKRecordValue
        }
        record["closingDate"] = closingDate as CKRecordValue
        record["dueDate"] = dueDate as CKRecordValue
        record["totalAmount"] = totalAmount as CKRecordValue
        record["isPaid"] = (isPaid ? 1 : 0) as CKRecordValue
        record["paidDate"] = paidDate as CKRecordValue?
        record["paidAmount"] = (paidAmount ?? 0) as CKRecordValue
        record["userId"] = userId as CKRecordValue
        record["isDatesOverridden"] = (isDatesOverridden ? 1 : 0) as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
        record["createdByUid"] = createdByUid as CKRecordValue?

        // Stable, device-independent identity and relationship. `creditCardCKRecordName` above is
        // nil until the card has been pushed, so a statement arriving before its card could not be
        // linked and the sender's meaningless local integer stayed in the receiver's database. A
        // uuid exists from row creation, so it is always available and always correct —
        // `resolveUuidForeignKeys()` converts it to a local id on this or a later pass.
        if let stmtId = id, let ids = db.uuidIdentity(table: "CreditCardStatements", localId: stmtId) {
            record["uuid"] = ids.uuid as CKRecordValue
            record["creditCardUuid"] = ids.creditCardUuid as CKRecordValue?
            // 2 = this device derives identities for the rows it GENERATES (recurring instances,
            // installment children, statements), so a receiver can match them exactly by uuid
            // and must NOT fall back to matching on title + amount + month.
            record["schemaVersion"] = 2 as CKRecordValue
        }
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> CreditCardStatement? {
        guard let creditCardId = record["creditCardId"] as? Int,
              let closingDate = record["closingDate"] as? Date,
              let dueDate = record["dueDate"] as? Date,
              let totalAmount = record["totalAmount"] as? Int,
              let userId = record["userId"] as? String
        else { return nil }

        return CreditCardStatement(
            id: record["localId"] as? Int,
            creditCardId: creditCardId,
            closingDate: closingDate,
            dueDate: dueDate,
            totalAmount: totalAmount,
            isPaid: (record["isPaid"] as? Int) == 1,
            paidDate: record["paidDate"] as? Date,
            paidAmount: record["paidAmount"] as? Int,
            isDatesOverridden: (record["isDatesOverridden"] as? Int) == 1,
            userId: userId,
            createdAt: record.creationDate ?? Date(),
            updatedAt: (record["updatedAt"] as? Date) ?? record.modificationDate ?? Date(),
            createdByUid: record["createdByUid"] as? String
        )
    }
}
