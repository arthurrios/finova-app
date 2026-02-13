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
        let recordID: CKRecord.ID
        if let existingID = ckRecordID {
            recordID = existingID
        } else {
            recordID = CKRecord.ID(
                recordName: "creditCard-\(id ?? 0)",
                zoneID: targetZoneID
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
            updatedAt: record.modificationDate ?? Date()
        )
        card.sharedGroupId = record["sharedGroupId"] as? String
        return card
    }
}
