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

    func toCKRecord(in zoneID: CKRecordZone.ID, storedRecordName: String?) -> CKRecord {
        let actualZone = targetZoneID(for: creditCardId)
        let recordName: String
        if let storedName = storedRecordName {
            recordName = storedName
        } else {
            // Phase 3A: Use UUID-based names for new records to avoid cross-device ID collisions
            recordName = "statement-\(UUID().uuidString)"
        }
        let recordID = CKRecord.ID(recordName: recordName, zoneID: actualZone)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["localId"] = (id ?? 0) as CKRecordValue
        record["creditCardId"] = creditCardId as CKRecordValue
        record["closingDate"] = closingDate as CKRecordValue
        record["dueDate"] = dueDate as CKRecordValue
        record["totalAmount"] = totalAmount as CKRecordValue
        record["isPaid"] = (isPaid ? 1 : 0) as CKRecordValue
        record["paidDate"] = paidDate as CKRecordValue?
        record["paidAmount"] = (paidAmount ?? 0) as CKRecordValue
        record["userId"] = userId as CKRecordValue
        record["isDatesOverridden"] = (isDatesOverridden ? 1 : 0) as CKRecordValue
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
            updatedAt: record.modificationDate ?? Date()
        )
    }
}
