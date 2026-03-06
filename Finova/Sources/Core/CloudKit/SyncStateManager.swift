//
//  SyncStateManager.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import CloudKit
import Foundation

final class SyncStateManager {
    static let shared = SyncStateManager()

    private let defaults = UserDefaults.standard
    private let tokenKeyPrefix = "ck_changeToken_"
    private let lastSyncKeyPrefix = "ck_lastSync_"

    func changeToken(for recordType: String, database: String = "private") -> CKServerChangeToken? {
        let key = tokenKeyPrefix + database + "_" + recordType
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    func saveChangeToken(_ token: CKServerChangeToken?, for recordType: String, database: String = "private") {
        let key = tokenKeyPrefix + database + "_" + recordType
        if let token = token,
           let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func lastSyncDate(for recordType: String) -> Date? {
        let key = lastSyncKeyPrefix + recordType
        let interval = defaults.double(forKey: key)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    func updateLastSyncDate(for recordType: String) {
        let key = lastSyncKeyPrefix + recordType
        defaults.set(Date().timeIntervalSince1970, forKey: key)
    }

    func resetSharedDBTokens() {
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(tokenKeyPrefix + "shared_") {
            defaults.removeObject(forKey: key)
        }
    }

    func resetAllTokens() {
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(tokenKeyPrefix) || key.hasPrefix(lastSyncKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
