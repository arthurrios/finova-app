//
//  CKRecordConvertible.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit

protocol CKRecordConvertible {
    static var recordType: String { get }
    var ckRecordID: CKRecord.ID? { get }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord
    static func fromCKRecord(_ record: CKRecord) -> Self?
}
