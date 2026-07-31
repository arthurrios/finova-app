//
//  BudgetRepository.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

final class BudgetRepository: BudgetRepositoryProtocol {
  /// Injectable for two-device tests; production always uses `.shared`.
  private let db: DBHelper

  init(db: DBHelper = .shared) { self.db = db }

  func insert(budget: BudgetModel) throws {
    // The model's own scope is honoured. Previously it was DISCARDED — `insert` wrote the row and
    // then only ever set `shared_group_id` from mirror mode, so a budget explicitly created for a
    // group silently landed as a personal one. That was invisible while `month_date` was a global
    // primary key (there could only be one row per month anyway); now that a month can hold a
    // personal budget and one per group, dropping the scope collapses them onto the same row.
    let scope = budget.sharedGroupId
      ?? (MirrorModeManager.shared.isEnabled ? MirrorModeManager.shared.linkedGroupId : nil)

    try db.insertBudget(monthDate: budget.monthDate, amount: budget.amount, sharedGroupId: scope)
    markSyncPending(forMonthDate: budget.monthDate, sharedGroupId: scope)
    NotificationCenter.default.post(name: .budgetDataChanged, object: nil)
  }

  func update(budget: BudgetModel) throws {
    try db.updateBudget(monthDate: budget.monthDate, amount: budget.amount)
    db.executeSyncUpdate(
      "UPDATE Budgets SET sync_status = 'pending' WHERE month_date = ?;",
      intBindings: [budget.monthDate]
    )
    if MirrorModeManager.shared.isEnabled,
       let groupId = MirrorModeManager.shared.linkedGroupId {
      updateSharedGroupId(monthDate: budget.monthDate, groupId: groupId)
    }

    let groupId = db.fetchSingleString(
      "SELECT shared_group_id FROM Budgets WHERE month_date = ?;",
      intBinding: budget.monthDate
    )
    if let groupId = groupId {
      GroupNotificationService.shared.logActivity(
        action: .budgetEdited, groupId: groupId, detail: "")
    }

    NotificationCenter.default.post(name: .budgetDataChanged, object: nil)
  }

  func delete(monthDate: Int) throws {
    // Check if synced
    let ckName = db.fetchSingleString(
      "SELECT ck_record_id FROM Budgets WHERE month_date = ?;",
      intBinding: monthDate
    )
    if ckName != nil {
      db.executeSyncUpdate(
        "UPDATE Budgets SET is_deleted = 1, sync_status = 'pendingDelete' WHERE month_date = ?;",
        intBindings: [monthDate]
      )
    } else {
      try db.deleteBudget(monthDate: monthDate)
    }
    NotificationCenter.default.post(name: .budgetDataChanged, object: nil)
  }

  func fetchBudgets() -> [BudgetModel] {
    if let uid = UIDUserDefaultsManager.shared.currentUserUID {
      return (try? db.getBudgets(forUser: uid)) ?? []
    }
    return (try? db.getBudgets()) ?? []
  }

  func exists(monthDate: Int) -> Bool {
    let budgets = fetchBudgets()
    return budgets.contains { $0.monthDate == monthDate }
  }

  // MARK: - Mirror Mode

  func updateSharedGroupId(monthDate: Int, groupId: String?) {
    if let groupId = groupId {
      db.executeSyncUpdate(
        "UPDATE Budgets SET shared_group_id = ?, sync_status = 'pending' WHERE month_date = ?;",
        textBindings: [groupId],
        intBindings: [monthDate]
      )
    } else {
      db.executeSyncUpdate(
        "UPDATE Budgets SET shared_group_id = NULL, sync_status = 'pending' WHERE month_date = ?;",
        intBindings: [monthDate]
      )
    }
  }

  // MARK: - Group Queries

  func fetchBudgetsForGroup(groupId: String) -> [BudgetModel] {
    do {
      return try db.fetchBudgetsForGroup(groupId: groupId)
    } catch {
      logError("Failed to fetch budgets for group: \(error)")
      return []
    }
  }

  // MARK: - CloudKit Sync Methods

  func fetchPendingSync() -> [BudgetModel] {
    if let uid = UIDUserDefaultsManager.shared.currentUserUID {
      return db.fetchPendingSyncBudgets(userId: uid)
    }
    return db.fetchPendingSyncBudgets(userId: nil)
  }

  /// See `TransactionRepository.markAsSynced` for why `pushedUpdatedAt` matters: without it, an
  /// edit made while the push was in flight is marked synced and never pushed.
  func markAsSynced(ckRecordName: String, pushedUpdatedAt: Date? = nil) {
    // Phase 3C: CK record name is pre-stored before push, so matching by ck_record_id is sufficient
    guard let pushedUpdatedAt = pushedUpdatedAt else {
      db.executeSyncUpdate(
        "UPDATE Budgets SET sync_status = 'synced' WHERE ck_record_id = ?;",
        textBindings: [ckRecordName]
      )
      return
    }
    db.executeSyncUpdate(
      "UPDATE Budgets SET sync_status = 'synced' WHERE ck_record_id = ? AND COALESCE(updated_at, 0) <= ?;",
      textBindings: [ckRecordName],
      intBindings: [Int(pushedUpdatedAt.timeIntervalSince1970)]
    )
  }

  func insertFromCloud(_ budget: BudgetModel, ckRecordName: String) {
    db.executeSyncUpdate(
      "DELETE FROM Budgets WHERE ck_record_id = ?;",
      textBindings: [ckRecordName]
    )

    do {
      try db.executeGroupWriteChecked(
        """
        INSERT INTO Budgets (month_date, amount, user_id, shared_group_id, ck_record_id, sync_status, ck_modified_at, updated_at, created_by_uid)
        VALUES (?, ?, ?, ?, ?, 'synced', ?, ?, ?);
        """,
        orderedBindings: [
          budget.monthDate,
          budget.amount,
          // The record's author, NOT the receiving device's user. Binding the receiver's uid
          // rewrote every inbound budget into the local namespace, which is what makes the
          // month_date collision below inevitable rather than incidental.
          budget.createdByUid ?? UIDUserDefaultsManager.shared.currentUserUID,
          budget.sharedGroupId,
          ckRecordName,
          Int(Date().timeIntervalSince1970),
          Int((budget.updatedAt ?? Date()).timeIntervalSince1970),
          budget.createdByUid
        ]
      )
    } catch {
      // `Budgets.month_date` is a GLOBAL primary key, so a month can hold exactly one budget row
      // — a personal budget and a group budget for the same month are physically the same row.
      // This insert therefore fails whenever the month is already taken, and until now that
      // failure was discarded, silently dropping the record.
      //
      // Deliberately NOT resolved by upserting: `INSERT OR REPLACE` would let an arriving group
      // budget overwrite the user's personal budget for that month. Surfacing it is the correct
      // interim behaviour; the real fix is the scoped key in Stage 2.
      logError("""
        [Budget] Cannot insert \(ckRecordName) for month \(budget.monthDate) — a budget already \
        exists for that month and `month_date` is a global primary key. Record NOT stored. \
        (\(error))
        """)
    }
  }

  func updateFromCloud(_ budget: BudgetModel, ckRecordName: String) {
    db.executeGroupWrite(
      """
      UPDATE Budgets SET amount = ?, shared_group_id = ?, sync_status = 'synced', ck_modified_at = ?, updated_at = ?,
          created_by_uid = COALESCE(?, created_by_uid), is_deleted = 0
      WHERE ck_record_id = ?;
      """,
      orderedBindings: [
        budget.amount,
        budget.sharedGroupId,
        Int(Date().timeIntervalSince1970),
        Int((budget.updatedAt ?? Date()).timeIntervalSince1970),
        budget.createdByUid,
        ckRecordName
      ]
    )
  }

  func deleteFromCloud(ckRecordName recordName: String) {
    // RECREATION-WINS guard: keep a row that has unpushed local edits instead of applying a
    // remote delete (it re-pushes, so the newer local change is preserved).
    if db.fetchSingleString("SELECT sync_status FROM Budgets WHERE ck_record_id = ?;", textBinding: recordName) == "pending" {
      return
    }
    db.executeSyncUpdate(
      "DELETE FROM Budgets WHERE ck_record_id = ?;",
      textBindings: [recordName]
    )
  }

  func fetchPendingDeletes() -> [(ckRecordName: String, monthDate: Int)] {
    let query = "SELECT month_date, ck_record_id FROM Budgets WHERE sync_status = 'pendingDelete' AND ck_record_id IS NOT NULL;"
    guard let rows = db.fetchIdAndCKRecordName(query) else { return [] }
    return rows.map { (ckRecordName: $0.ckRecordName, monthDate: $0.localId) }
  }

  func hardDeleteByCKRecordName(_ recordName: String) {
    db.executeSyncUpdate(
      "DELETE FROM Budgets WHERE ck_record_id = ?;",
      textBindings: [recordName]
    )
  }

  func fetchBudget(byCKRecordName recordName: String) -> BudgetModel? {
    guard let monthDate = db.fetchSingleInt(
      "SELECT month_date FROM Budgets WHERE ck_record_id = ? AND (is_deleted IS NULL OR is_deleted = 0);",
      textBinding: recordName
    ) else { return nil }
    guard let amount = db.fetchSingleInt(
      "SELECT amount FROM Budgets WHERE month_date = ? AND (is_deleted IS NULL OR is_deleted = 0);",
      intBinding: monthDate
    ) else { return nil }
    return BudgetModel(monthDate: monthDate, amount: amount)
  }

  func fetchBudget(byMonthDate monthDate: Int) -> BudgetModel? {
    guard let amount = db.fetchSingleInt(
      "SELECT amount FROM Budgets WHERE month_date = ? AND (is_deleted IS NULL OR is_deleted = 0);",
      intBinding: monthDate
    ) else { return nil }
    return BudgetModel(monthDate: monthDate, amount: amount)
  }

  /// If a soft-deleted budget with this CK record name exists (is_deleted=1),
  /// restores its sync_status to 'pendingDelete' so the next push will remove it from
  /// CloudKit. Returns true if such a record was found (caller should skip re-insertion).
  func restorePendingDeleteIfNeeded(ckRecordName: String) -> Bool {
    let check = "SELECT month_date FROM Budgets WHERE ck_record_id = ? AND is_deleted = 1;"
    guard db.fetchSingleInt(check, textBinding: ckRecordName) != nil else { return false }
    db.executeSyncUpdate(
      "UPDATE Budgets SET sync_status = 'pendingDelete' WHERE ck_record_id = ? AND is_deleted = 1;",
      textBindings: [ckRecordName]
    )
    return true
  }

  func lastModifiedDate(forMonthDate monthDate: Int) -> Date? {
    let query = "SELECT updated_at FROM Budgets WHERE month_date = ?;"
    guard let timestamp = db.fetchSingleInt(query, intBinding: monthDate), timestamp > 0 else {
      return nil
    }
    return Date(timeIntervalSince1970: TimeInterval(timestamp))
  }

  func markSyncPending(forMonthDate monthDate: Int) {
    let now = Int(Date().timeIntervalSince1970)
    db.executeSyncUpdate(
      "UPDATE Budgets SET sync_status = 'pending', ck_modified_at = ? WHERE month_date = ?;",
      intBindings: [now, monthDate]
    )
  }

  /// - Parameter sharedGroupId: which budget for that month — `nil` means the personal one.
  ///
  /// Since Stage 2 a month can hold several budgets (one personal, one per group), so every
  /// identity-critical write must say WHICH. Without the scope this tagged an arbitrary row with
  /// another scope's CloudKit identity.
  func setCKRecordId(forMonthDate monthDate: Int, sharedGroupId: String? = nil, ckRecordName: String) {
    // orderedBindings, not textBindings/intBindings: those bind ALL text before ALL ints, which
    // would scramble a query whose placeholders interleave the two types.
    db.executeGroupWrite(
      """
      UPDATE Budgets SET ck_record_id = ?
       WHERE month_date = ? AND ck_record_id IS NULL
         AND COALESCE(shared_group_id, '') = ?;
      """,
      orderedBindings: [ckRecordName, monthDate, sharedGroupId ?? ""]
    )
  }

  /// The budget for a month in a specific scope. `nil` group means the personal budget.
  func fetchBudget(byMonthDate monthDate: Int, sharedGroupId: String?) -> BudgetModel? {
    guard let amount = db.fetchSingleInt(
      """
      SELECT amount FROM Budgets
       WHERE month_date = ? AND COALESCE(shared_group_id, '') = ?
         AND (is_deleted IS NULL OR is_deleted = 0);
      """,
      orderedBindings: [monthDate, sharedGroupId ?? ""]
    ) else { return nil }
    return BudgetModel(monthDate: monthDate, amount: amount, sharedGroupId: sharedGroupId)
  }

  /// Scoped counterpart of `lastModifiedDate(forMonthDate:)`, so conflict resolution compares the
  /// timestamp of the budget actually being resolved rather than whichever row the month matched.
  func lastModifiedDate(forMonthDate monthDate: Int, sharedGroupId: String?) -> Date? {
    guard let ts = db.fetchSingleInt(
      "SELECT updated_at FROM Budgets WHERE month_date = ? AND COALESCE(shared_group_id, '') = ?;",
      orderedBindings: [monthDate, sharedGroupId ?? ""]
    ), ts > 0 else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(ts))
  }

  /// Scoped counterpart of `markSyncPending(forMonthDate:)`.
  func markSyncPending(forMonthDate monthDate: Int, sharedGroupId: String?) {
    db.executeGroupWrite(
      """
      UPDATE Budgets SET sync_status = 'pending', ck_modified_at = ?
       WHERE month_date = ? AND COALESCE(shared_group_id, '') = ?;
      """,
      orderedBindings: [Int(Date().timeIntervalSince1970), monthDate, sharedGroupId ?? ""]
    )
  }
}
