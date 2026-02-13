//
//  BudgetRepository.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation

final class BudgetRepository: BudgetRepositoryProtocol {
  private let db = DBHelper.shared

  func insert(budget: BudgetModel) throws {
    try db.insertBudget(monthDate: budget.monthDate, amount: budget.amount)
    db.executeSyncUpdate(
      "UPDATE Budgets SET sync_status = 'pending' WHERE month_date = ?;",
      intBindings: [budget.monthDate]
    )
    if MirrorModeManager.shared.isEnabled,
       let groupId = MirrorModeManager.shared.linkedGroupId {
      updateSharedGroupId(monthDate: budget.monthDate, groupId: groupId)
    }
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

  func markAsSynced(ckRecordName: String) {
    // Phase 3C: CK record name is pre-stored before push, so matching by ck_record_id is sufficient
    db.executeSyncUpdate(
      "UPDATE Budgets SET sync_status = 'synced' WHERE ck_record_id = ?;",
      textBindings: [ckRecordName]
    )
  }

  func insertFromCloud(_ budget: BudgetModel, ckRecordName: String) {
    db.executeSyncUpdate(
      "DELETE FROM Budgets WHERE ck_record_id = ?;",
      textBindings: [ckRecordName]
    )

    db.executeGroupWrite(
      """
      INSERT INTO Budgets (month_date, amount, user_id, ck_record_id, sync_status, ck_modified_at)
      VALUES (?, ?, ?, ?, 'synced', ?);
      """,
      orderedBindings: [
        budget.monthDate,
        budget.amount,
        UIDUserDefaultsManager.shared.currentUserUID,
        ckRecordName,
        Int(Date().timeIntervalSince1970)
      ]
    )
  }

  func updateFromCloud(_ budget: BudgetModel, ckRecordName: String) {
    db.executeGroupWrite(
      """
      UPDATE Budgets SET amount = ?, sync_status = 'synced', ck_modified_at = ?
      WHERE ck_record_id = ?;
      """,
      orderedBindings: [
        budget.amount,
        Int(Date().timeIntervalSince1970),
        ckRecordName
      ]
    )
  }

  func softDeleteByCKRecordName(_ recordName: String) {
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
      "SELECT month_date FROM Budgets WHERE ck_record_id = ?;",
      textBinding: recordName
    ) else { return nil }
    guard let amount = db.fetchSingleInt(
      "SELECT amount FROM Budgets WHERE month_date = ?;",
      intBinding: monthDate
    ) else { return nil }
    return BudgetModel(monthDate: monthDate, amount: amount)
  }

  func fetchBudget(byMonthDate monthDate: Int) -> BudgetModel? {
    guard let amount = db.fetchSingleInt(
      "SELECT amount FROM Budgets WHERE month_date = ?;",
      intBinding: monthDate
    ) else { return nil }
    return BudgetModel(monthDate: monthDate, amount: amount)
  }

  func lastModifiedDate(forMonthDate monthDate: Int) -> Date? {
    let query = "SELECT ck_modified_at FROM Budgets WHERE month_date = ?;"
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

  func setCKRecordId(forMonthDate monthDate: Int, ckRecordName: String) {
    db.executeSyncUpdate(
      "UPDATE Budgets SET ck_record_id = ? WHERE month_date = ? AND ck_record_id IS NULL;",
      textBindings: [ckRecordName],
      intBindings: [monthDate]
    )
  }
}
