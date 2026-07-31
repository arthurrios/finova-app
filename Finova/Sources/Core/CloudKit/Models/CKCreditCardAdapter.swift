//
//  CKCreditCardAdapter.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit

extension CreditCard: CKRecordConvertible {
    static var recordType: String { "CreditCard" }

    var ckRecordID: CKRecord.ID? {
        guard let id = id else { return nil }
        return CKRecord.ID(
            recordName: "creditCard-\(id)",
            zoneID: targetZoneID
        )
    }

    var targetZoneID: CKRecordZone.ID {
        if let groupId = sharedGroupId {
            return CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: CKCurrentUserDefaultName)
        }
        return CloudKitManager.privateZoneID
    }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        return toCKRecord(in: zoneID, storedRecordName: nil)
    }

    /// - Parameter db: the database this row belongs to; see `CKTransactionAdapter` for why this
    ///   must be explicit rather than defaulting to the shared singleton.
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
                recordName: "creditCard-\(UUID().uuidString)",
                zoneID: zoneID
            )
        }

        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["localId"] = (id ?? 0) as CKRecordValue
        record["name"] = name as CKRecordValue
        record["lastFourDigits"] = lastFourDigits as CKRecordValue
        record["cardBrand"] = cardBrand.rawValue as CKRecordValue
        record["closingDay"] = closingDay as CKRecordValue
        record["dueDay"] = dueDay as CKRecordValue
        record["creditLimit"] = (creditLimit ?? 0) as CKRecordValue
        record["cardColor"] = cardColor.rawValue as CKRecordValue
        record["userId"] = userId as CKRecordValue
        record["sharedGroupId"] = sharedGroupId as CKRecordValue?
        record["isDeleted"] = (isDeleted ? 1 : 0) as CKRecordValue
        record["isDefault"] = (isDefault ? 1 : 0) as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
        record["createdByUid"] = createdByUid as CKRecordValue?

        // The card's stable identity. Without this the receiving device generates its own uuid for
        // the card, and every transaction referencing it by `creditCardUuid` then fails to resolve —
        // the reference is only as good as the referent's identity travelling with it.
        if let cardId = id, let ids = db.uuidIdentity(table: "CreditCards", localId: cardId) {
            record["uuid"] = ids.uuid as CKRecordValue
            // 2 = this device derives identities for the rows it GENERATES (recurring instances,
            // installment children, statements), so a receiver can match them exactly by uuid
            // and must NOT fall back to matching on title + amount + month.
            record["schemaVersion"] = 2 as CKRecordValue
        }
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> CreditCard? {
        guard let name = record["name"] as? String,
              let lastFour = record["lastFourDigits"] as? String,
              let brandRaw = record["cardBrand"] as? String,
              let brand = CardBrand(rawValue: brandRaw),
              let closingDay = record["closingDay"] as? Int,
              let dueDay = record["dueDay"] as? Int,
              let colorRaw = record["cardColor"] as? String,
              let color = CardColor(rawValue: colorRaw),
              let userId = record["userId"] as? String
        else { return nil }

        var card = CreditCard(
            id: record["localId"] as? Int,
            name: name,
            lastFourDigits: lastFour,
            cardBrand: brand,
            closingDay: closingDay,
            dueDay: dueDay,
            creditLimit: record["creditLimit"] as? Int,
            cardColor: color,
            userId: userId,
            isDeleted: (record["isDeleted"] as? Int) == 1,
            isDefault: (record["isDefault"] as? Int) == 1,
            createdAt: record.creationDate ?? Date(),
            updatedAt: (record["updatedAt"] as? Date) ?? record.modificationDate ?? Date()
        )
        card.sharedGroupId = record["sharedGroupId"] as? String
        card.createdByUid = record["createdByUid"] as? String
        return card
    }
}
