//
//  UIDUserDefaultsManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 27/01/25.
//

import CloudKit
import Foundation

/// Manages user-specific settings linked to Firebase UID
class UIDUserDefaultsManager {

  // MARK: - Singleton
  static let shared = UIDUserDefaultsManager()
  private init() {}

  // MARK: - Private Keys
  private static let userSettingsPrefix = "userSettings_"
  private static let currentUserUIDKey = "currentUserUID"
  private static let globalCurrentMonthIndex = "currentMonthIndexKey"
  private static let globalBalanceDisplayMode = "BalanceDisplayMode"

  // MARK: - Current User Management

  var currentUserUID: String? {
    get {
      return UserDefaults.standard.string(forKey: Self.currentUserUIDKey)
    }
    set {
      if let uid = newValue {
        UserDefaults.standard.set(uid, forKey: Self.currentUserUIDKey)
      } else {
        UserDefaults.standard.removeObject(forKey: Self.currentUserUIDKey)
      }

    }
  }

  // MARK: - User-Specific Settings

  func saveUserSettings(for uid: String, settings: UserSettings) {
    let key = Self.userSettingsPrefix + uid
    let encoder = JSONEncoder()
    if let data = try? encoder.encode(settings) {
      UserDefaults.standard.set(data, forKey: key)

      logInfo("Saved settings for user: \(uid)")
    }
  }

  func getUserSettings(for uid: String) -> UserSettings? {
    let key = Self.userSettingsPrefix + uid
    if let data = UserDefaults.standard.data(forKey: key) {
      let decoder = JSONDecoder()
      if let settings = try? decoder.decode(UserSettings.self, from: data) {
        return settings
      }
    }
    return nil
  }

  func removeUserSettings(for uid: String) {
    let key = Self.userSettingsPrefix + uid
    UserDefaults.standard.removeObject(forKey: key)
    UserDefaults.standard.synchronize()
    logInfo("Removed settings for user: \(uid)")
  }

  // MARK: - Current User Convenience Methods

  func saveCurrentUserSettings(_ settings: UserSettings) {
    guard let uid = currentUserUID else {
      logError("Cannot save settings: No current user UID")
      return
    }
    saveUserSettings(for: uid, settings: settings)
  }

  func getCurrentUserSettings() -> UserSettings? {
    guard let uid = currentUserUID else {
      logError("Cannot get settings: No current user UID")
      return nil
    }
    return getUserSettings(for: uid)
  }

  // MARK: - Migration from Global Settings

  func migrateGlobalSettingsToUser(uid: String, globalUser: User) {
    // Check if user already has settings
    if getUserSettings(for: uid) != nil {
      logInfo("User \(uid) already has settings, skipping migration")
      return
    }

    // Create settings from global user data
    let settings = UserSettings(
      name: globalUser.name,
      email: globalUser.email,
      hasFaceIdEnabled: globalUser.hasFaceIdEnabled,
      isUserSaved: globalUser.isUserSaved,
      createdAt: globalUser.createdAt,
      lastSignIn: Date()
    )

    saveUserSettings(for: uid, settings: settings)
    logInfo("Migrated global settings to user: \(uid)")
  }

  // MARK: - Global Settings (Non-User Specific)

  func getCurrentMonthIndex() -> Int {
    return UserDefaults.standard.integer(forKey: Self.globalCurrentMonthIndex)
  }

  func setCurrentMonthIndex(_ index: Int) {
    UserDefaults.standard.set(index, forKey: Self.globalCurrentMonthIndex)
  }

  func getCurrentUserBalanceOffset() -> Int {
    guard let uid = currentUserUID else { return 0 }
    return UserDefaults.standard.integer(forKey: "balanceOffset_\(uid)")
  }

  func setCurrentUserBalanceOffset(_ offset: Int) {
    guard let uid = currentUserUID else { return }
    UserDefaults.standard.set(offset, forKey: "balanceOffset_\(uid)")
    pushBalanceOffsetToCloud(offset, key: "personal", uid: uid)
    if MirrorModeManager.shared.isEnabled,
       let groupId = MirrorModeManager.shared.linkedGroupId {
      setGroupBalanceOffset(offset, groupId: groupId)
    }
  }

  func getGroupBalanceOffset(groupId: String) -> Int {
    return UserDefaults.standard.integer(forKey: "balanceOffset_group_\(groupId)")
  }

  func setGroupBalanceOffset(_ offset: Int, groupId: String) {
    UserDefaults.standard.set(offset, forKey: "balanceOffset_group_\(groupId)")
    if let uid = currentUserUID {
      pushBalanceOffsetToCloud(offset, key: "group-\(groupId)", uid: uid)
      // Also push to the group zone so members can see the offset
      pushBalanceOffsetToGroupZone(offset, groupId: groupId, uid: uid)
    }
  }

  // MARK: - CloudKit Balance Offset Sync

  private func pushBalanceOffsetToCloud(_ offset: Int, key: String, uid: String) {
    let recordID = CKRecord.ID(
      recordName: "balanceOffset-\(uid)-\(key)",
      zoneID: CloudKitManager.privateZoneID
    )
    let record = CKRecord(recordType: "BalanceOffset", recordID: recordID)
    record["offset"] = offset as CKRecordValue
    record["key"] = key as CKRecordValue
    record["updatedAt"] = Date() as CKRecordValue

    let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
    operation.savePolicy = .allKeys
    operation.qualityOfService = .utility
    operation.modifyRecordsResultBlock = { result in
      switch result {
      case .success:
        logInfo("Balance offset synced to CloudKit: \(key) = \(offset)")
      case .failure(let error):
        logError("Failed to sync balance offset to CloudKit: \(error)")
      }
    }
    CloudKitManager.shared.privateDatabase.add(operation)
  }

  private func pushBalanceOffsetToGroupZone(_ offset: Int, groupId: String, uid: String) {
    let group = BudgetGroupService.shared.fetchGroup(byId: groupId)
    guard let group = group, group.isOwner else { return }

    let zoneID = CKRecordZone.ID(zoneName: "Group-\(groupId)", ownerName: CKCurrentUserDefaultName)
    let recordID = CKRecord.ID(recordName: "balanceOffset-group-\(groupId)", zoneID: zoneID)
    let record = CKRecord(recordType: "BalanceOffset", recordID: recordID)
    record["offset"] = offset as CKRecordValue
    record["key"] = "group-\(groupId)" as CKRecordValue
    record["updatedAt"] = Date() as CKRecordValue

    let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
    operation.savePolicy = .allKeys
    operation.qualityOfService = .utility
    operation.modifyRecordsResultBlock = { result in
      switch result {
      case .success:
        logInfo("Balance offset synced to group zone: group-\(groupId) = \(offset)")
      case .failure(let error):
        logError("Failed to sync balance offset to group zone: \(error)")
      }
    }
    CloudKitManager.shared.privateDatabase.add(operation)
  }

  func fetchBalanceOffsetsFromCloud(completion: @escaping () -> Void) {
    guard let uid = currentUserUID else {
      completion()
      return
    }

    // If the pull phase already delivered a fresh BalanceOffset record,
    // skip re-fetching to avoid overwriting with a potentially stale value.
    if SyncEngine.shared.didReceiveBalanceOffsetDuringPull {
      logInfo("Skipping fetchBalanceOffsetsFromCloud — offset already updated during pull")
      completion()
      return
    }

    let dispatchGroup = DispatchGroup()
    var didUpdate = false

    // Track fetched values for mirror mode reconciliation
    var fetchedPersonalOffset: Int?
    var fetchedPersonalDate: Date?
    var fetchedGroupOffsets: [(groupId: String, offset: Int, updatedAt: Date)] = []
    let groupOffsetsQueue = DispatchQueue(label: "com.finova.groupOffsets")

    // Fetch personal offset by known record ID (avoids CKQuery which requires queryable indexes)
    let personalRecordID = CKRecord.ID(
      recordName: "balanceOffset-\(uid)-personal",
      zoneID: CloudKitManager.privateZoneID
    )

    dispatchGroup.enter()
    CloudKitManager.shared.privateDatabase.fetch(withRecordID: personalRecordID) { [weak self] record, error in
      guard let self = self else {
        dispatchGroup.leave()
        return
      }

      if let record = record,
         let offset = record["offset"] as? Int {
        fetchedPersonalOffset = offset
        fetchedPersonalDate = record["updatedAt"] as? Date
        let currentLocal = UserDefaults.standard.integer(forKey: "balanceOffset_\(uid)")
        if currentLocal != offset {
          UserDefaults.standard.set(offset, forKey: "balanceOffset_\(uid)")
          logInfo("Balance offset updated from CloudKit: personal = \(offset)")
          didUpdate = true
        }
      } else if let ckError = error as? CKError, ckError.code == .unknownItem {
        // No personal offset in CloudKit yet — push local if non-zero
        let localOffset = UserDefaults.standard.integer(forKey: "balanceOffset_\(uid)")
        if localOffset != 0 {
          self.pushBalanceOffsetToCloud(localOffset, key: "personal", uid: uid)
        }
      } else if let error = error {
        logError("Failed to fetch personal balance offset from CloudKit: \(error)")
      }

      dispatchGroup.leave()
    }

    // Fetch group balance offsets for all known groups
    let groups = BudgetGroupService.shared.fetchAllGroups()
    for group in groups {
      // Fetch from own private zone (owner's copy or member's locally-pushed copy)
      let groupRecordID = CKRecord.ID(
        recordName: "balanceOffset-\(uid)-group-\(group.id)",
        zoneID: CloudKitManager.privateZoneID
      )

      dispatchGroup.enter()
      CloudKitManager.shared.privateDatabase.fetch(withRecordID: groupRecordID) { record, error in
        if let record = record,
           let offset = record["offset"] as? Int {
          let updatedAt = record["updatedAt"] as? Date ?? .distantPast
          groupOffsetsQueue.sync {
            fetchedGroupOffsets.append((groupId: group.id, offset: offset, updatedAt: updatedAt))
          }
          let currentLocal = UserDefaults.standard.integer(forKey: "balanceOffset_group_\(group.id)")
          if currentLocal != offset {
            UserDefaults.standard.set(offset, forKey: "balanceOffset_group_\(group.id)")
            logInfo("Balance offset updated from CloudKit: group-\(group.id) = \(offset)")
            didUpdate = true
          }
        } else if let ckError = error as? CKError, ckError.code == .unknownItem {
          // No group offset in CloudKit yet — push local if non-zero
          let localOffset = UserDefaults.standard.integer(forKey: "balanceOffset_group_\(group.id)")
          if localOffset != 0 {
            UIDUserDefaultsManager.shared.setGroupBalanceOffset(localOffset, groupId: group.id)
          }
        } else if let error = error {
          logError("Failed to fetch group balance offset from CloudKit: \(error)")
        }

        dispatchGroup.leave()
      }

      // For member groups, also fetch the offset from the shared group zone
      // where the owner pushes the canonical group offset
      if !group.isOwner, let zoneOwner = group.ckZoneOwner {
        let sharedZoneID = CKRecordZone.ID(zoneName: "Group-\(group.id)", ownerName: zoneOwner)
        let sharedRecordID = CKRecord.ID(
          recordName: "balanceOffset-group-\(group.id)",
          zoneID: sharedZoneID
        )

        dispatchGroup.enter()
        CloudKitManager.shared.sharedDatabase.fetch(withRecordID: sharedRecordID) { record, error in
          if let record = record,
             let offset = record["offset"] as? Int {
            let updatedAt = record["updatedAt"] as? Date ?? .distantPast
            groupOffsetsQueue.sync {
              // Only use if newer than what we already fetched
              if let existing = fetchedGroupOffsets.first(where: { $0.groupId == group.id }) {
                if updatedAt > existing.updatedAt {
                  fetchedGroupOffsets.removeAll { $0.groupId == group.id }
                  fetchedGroupOffsets.append((groupId: group.id, offset: offset, updatedAt: updatedAt))
                  UserDefaults.standard.set(offset, forKey: "balanceOffset_group_\(group.id)")
                  logInfo("Balance offset updated from group zone: group-\(group.id) = \(offset)")
                  didUpdate = true
                }
              } else {
                fetchedGroupOffsets.append((groupId: group.id, offset: offset, updatedAt: updatedAt))
                let currentLocal = UserDefaults.standard.integer(forKey: "balanceOffset_group_\(group.id)")
                if currentLocal != offset {
                  UserDefaults.standard.set(offset, forKey: "balanceOffset_group_\(group.id)")
                  logInfo("Balance offset updated from group zone: group-\(group.id) = \(offset)")
                  didUpdate = true
                }
              }
            }
          } else if let error = error {
            logError("Failed to fetch group balance offset from group zone: \(error)")
          }

          dispatchGroup.leave()
        }
      }
    }

    dispatchGroup.notify(queue: .main) { [weak self] in
      // Mirror mode reconciliation: ensure personal and linked group offsets stay in sync
      if MirrorModeManager.shared.isEnabled,
         let mirrorGroupId = MirrorModeManager.shared.linkedGroupId,
         let self = self {
        let personalOffset = fetchedPersonalOffset ?? UserDefaults.standard.integer(forKey: "balanceOffset_\(uid)")
        let personalDate = fetchedPersonalDate ?? .distantPast

        let groupEntry = fetchedGroupOffsets.first(where: { $0.groupId == mirrorGroupId })
        let groupOffset = groupEntry?.offset ?? UserDefaults.standard.integer(forKey: "balanceOffset_group_\(mirrorGroupId)")
        let groupDate = groupEntry?.updatedAt ?? .distantPast

        if personalOffset != groupOffset {
          // Use the most recently updated value as source of truth
          let sourceOffset = personalDate >= groupDate ? personalOffset : groupOffset
          logInfo("Mirror reconciliation: personal=\(personalOffset) group=\(groupOffset), using \(personalDate >= groupDate ? "personal" : "group") = \(sourceOffset)")

          UserDefaults.standard.set(sourceOffset, forKey: "balanceOffset_\(uid)")
          UserDefaults.standard.set(sourceOffset, forKey: "balanceOffset_group_\(mirrorGroupId)")

          // Push corrected value to the stale side
          if personalDate >= groupDate {
            self.pushBalanceOffsetToCloud(sourceOffset, key: "group-\(mirrorGroupId)", uid: uid)
          } else {
            self.pushBalanceOffsetToCloud(sourceOffset, key: "personal", uid: uid)
          }
          didUpdate = true
        }
      }

      if didUpdate {
        NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
      }
      completion()
    }
  }

  func getBalanceDisplayMode() -> BalanceDisplayMode {
    let modeString = UserDefaults.standard.string(forKey: Self.globalBalanceDisplayMode) ?? "final"
    return modeString == "current" ? .current : .final
  }

  func setBalanceDisplayMode(_ mode: BalanceDisplayMode) {
    let modeString: String
    switch mode {
    case .current:
      modeString = "current"
    case .final:
      modeString = "final"
    case .daySpecific:
      // Don't save day-specific mode to UserDefaults
      return
    }
    UserDefaults.standard.set(modeString, forKey: Self.globalBalanceDisplayMode)
  }

  // MARK: - Last Active Context

  func saveLastContext(_ context: DataContext) {
    guard let uid = currentUserUID else { return }
    let key = "lastContext_\(uid)"
    switch context {
    case .personal:
      UserDefaults.standard.set("personal", forKey: key)
    case .group(let group):
      UserDefaults.standard.set(group.id, forKey: key)
    }
  }

  func getLastContext() -> DataContext {
    guard let uid = currentUserUID else { return .personal }
    let key = "lastContext_\(uid)"
    guard let value = UserDefaults.standard.string(forKey: key), value != "personal" else {
      return .personal
    }
    // value is a group ID — look it up (skip soft-deleted groups)
    if let group = BudgetGroupService.shared.fetchGroup(byId: value), !group.isDeleted {
      return .group(group)
    }
    return .personal
  }

  // MARK: - Cleanup Methods

  func signOut() {
    currentUserUID = nil
    logInfo("UIDUserDefaultsManager signed out")
  }

  func clearAllUserSettings() {
    // Get all UserDefaults keys and remove user-specific ones
    if let keys = UserDefaults.standard.dictionaryRepresentation().keys as? [String] {
      for key in keys {
        if key.hasPrefix(Self.userSettingsPrefix) {
          UserDefaults.standard.removeObject(forKey: key)
        }
      }
    }
    UserDefaults.standard.synchronize()
    logInfo("Cleared all user settings")
  }
}

// MARK: - UserSettings Model

struct UserSettings: Codable {
  var name: String  // Made mutable to allow name updates from different login methods
  let email: String
  var hasFaceIdEnabled: Bool
  var isUserSaved: Bool
  let createdAt: Date
  var lastSignIn: Date

  init(
    name: String, email: String, hasFaceIdEnabled: Bool = false, isUserSaved: Bool = false,
    createdAt: Date = Date(), lastSignIn: Date = Date()
  ) {
    self.name = name
    self.email = email
    self.hasFaceIdEnabled = hasFaceIdEnabled
    self.isUserSaved = isUserSaved
    self.createdAt = createdAt
    self.lastSignIn = lastSignIn
  }

  var displayName: String {
    return name.isEmpty ? "User" : name
  }
}
