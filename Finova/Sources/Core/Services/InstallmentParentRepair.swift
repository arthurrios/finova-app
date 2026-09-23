//
//  InstallmentParentRepair.swift
//  Finova
//
//  Re-links installment children whose `parent_transaction_id` points at a row this device does not
//  hold.
//
//  The parent link travels between devices as `parentCKRecordName` (and, on newer builds, a parent
//  uuid). When a child arrives before its parent, the receiver keeps the SENDER's local integer, and
//  only the uuid pointer is ever resolved afterwards — so children synced without a parent uuid stay
//  pointing at an id that means nothing here, and one purchase can end up split across two or three
//  such dangling ids. The edit path then cannot find the series' parent and falls back to a rebuild
//  that re-derives the whole series.
//
//  Never deletes and never creates rows. A purchase with the same installment number twice is
//  reported, not resolved: which copy is real is the user's call.
//

import Foundation

enum InstallmentParentRepair {

  struct Result: Equatable {
    var linkedByRecordName = 0
    var linkedByLegacyName = 0
    var joined = 0
    /// Purchases left alone because an installment number appears more than once.
    var conflicts: [String] = []
    /// The series the moved rows belong to now — whose reminders must be recomputed.
    var affectedParentIds: Set<Int> = []

    var total: Int { linkedByRecordName + linkedByLegacyName + joined }
  }

  /// The current user's PERSONAL, live installment children whose parent id resolves to nothing.
  /// Group rows are never touched (ownership invariant: they may belong to someone else).
  /// `?1` is the user id.
  private static let orphanChild = """
    Transactions.installment_number IS NOT NULL AND Transactions.is_deleted = 0
      AND Transactions.parent_transaction_id IS NOT NULL
      AND Transactions.user_id = ?1 AND Transactions.shared_group_id IS NULL
      AND NOT EXISTS (SELECT 1 FROM Transactions x
                       WHERE x.id = Transactions.parent_transaction_id AND x.is_deleted = 0)
    """

  /// A live installment parent whose record name is `key`, same owner and scope, titled like the
  /// child (parents carry either the plain title or the " - Installment Parent" suffix). Record names
  /// are per zone, so a name alone is not an identity: owner, scope and title narrow it to the right
  /// copy, and a match is only taken when exactly ONE row qualifies.
  private static func parentMatch(_ key: String) -> String {
    """
    FROM Transactions p
     WHERE p.ck_record_id = \(key) AND p.is_deleted = 0 AND p.has_installments = 1
       AND p.parent_transaction_id IS NULL AND p.user_id = Transactions.user_id
       AND p.shared_group_id IS NULL
       AND (p.title = Transactions.title OR p.title = Transactions.title || ' - Installment Parent')
    """
  }

  @discardableResult
  static func run(
    db: DBHelper = .shared, transactionRepo: TransactionRepository, userId: String
  ) -> Result {
    var result = Result()
    let now = Int(Date().timeIntervalSince1970)

    let before = transactionRepo.fetchAllTransactions()
    let liveBefore = Set(before.compactMap(\.id))
    let orphanIds = Set(before.filter {
      $0.installmentNumber != nil && ($0.parentTransactionId.map { !liveBefore.contains($0) } ?? false)
    }.compactMap(\.id))

    // 1. Links the row still carries: the parent's record name as synced, then the legacy
    //    `transaction-<local id>` names, which encode the creating device's id — the same number the
    //    child kept. Every SET expression reads the row's OLD values, so all three columns are
    //    computed against the same match.
    for (key, isLegacy) in [
      ("Transactions.ck_parent_record_name", false),
      ("'transaction-' || Transactions.parent_transaction_id", true),
    ] {
      let match = parentMatch(key)
      let count = db.executeSyncUpdateCount(
        """
        UPDATE Transactions SET
          parent_transaction_id = (SELECT p.id \(match)),
          parent_transaction_uuid = (SELECT p.uuid \(match)),
          ck_parent_record_name = (SELECT p.ck_record_id \(match)),
          sync_status = 'pending', ck_modified_at = ?2, updated_at = ?2
        WHERE \(orphanChild)
          AND (SELECT count(*) \(match)) = 1;
        """,
        textBindings: [userId],
        intBindings: [now]
      )
      if isLegacy { result.linkedByLegacyName = count } else { result.linkedByRecordName = count }
    }
    TransactionRepository.invalidateCache()

    // 2. Pieces of one purchase left under different dangling ids. Same title, installment count
    //    and card, and no installment number twice — then they are one series. If exactly one piece
    //    already has a live parent, the rest join it; with none, they join the largest piece.
    let all = transactionRepo.fetchAllTransactions()
    let liveIds = Set(all.compactMap(\.id))

    struct Key: Hashable { let title: String; let total: Int; let card: Int? }
    let children = all.filter {
      $0.installmentNumber != nil && $0.parentTransactionId != nil && $0.isCreditCardStatement != true
    }
    let byKey = Dictionary(grouping: children) {
      Key(title: $0.title, total: $0.totalInstallments ?? 0, card: $0.creditCardId)
    }

    for (key, rows) in byKey {
      let pieces = Dictionary(grouping: rows) { $0.parentTransactionId! }
      let dangling = pieces.filter { !liveIds.contains($0.key) }
      guard pieces.count > 1, !dangling.isEmpty else { continue }

      // Personal only, same as step 1.
      let personal = rows.allSatisfy { tx in
        guard let txId = tx.id else { return false }
        return transactionRepo.fetchSharedGroupId(for: txId) == nil
      }
      guard personal else { continue }

      let numbers = rows.compactMap(\.installmentNumber)
      guard Set(numbers).count == numbers.count else {
        result.conflicts.append(key.title)
        logWarning("[InstallmentParentRepair] '\(key.title)' (\(key.total)x): installment number repeated \(numbers.sorted()) — left alone")
        continue
      }

      let anchored = pieces.keys.filter { liveIds.contains($0) }
      guard anchored.count <= 1 else { continue }
      // Largest piece, ties to the smallest id, so every device picks the same one.
      let largest: Int = pieces
        .map { (pid: $0.key, size: $0.value.count) }
        .sorted { $0.size != $1.size ? $0.size > $1.size : $0.pid < $1.pid }[0].pid
      let target: Int = anchored.first ?? largest

      for (pid, piece) in pieces where pid != target {
        for tx in piece {
          guard let txId = tx.id else { continue }
          // The joined rows take the target's link columns too, so the push carries one parent.
          result.joined += db.executeSyncUpdateCount(
            """
            UPDATE Transactions SET
              parent_transaction_id = ?2,
              parent_transaction_uuid = CASE WHEN EXISTS (SELECT 1 FROM Transactions x WHERE x.id = ?2)
                THEN (SELECT x.uuid FROM Transactions x WHERE x.id = ?2)
                ELSE (SELECT s.parent_transaction_uuid FROM Transactions s WHERE s.parent_transaction_id = ?2 AND s.id <> ?3 LIMIT 1) END,
              ck_parent_record_name = CASE WHEN EXISTS (SELECT 1 FROM Transactions x WHERE x.id = ?2)
                THEN (SELECT x.ck_record_id FROM Transactions x WHERE x.id = ?2)
                ELSE (SELECT s.ck_parent_record_name FROM Transactions s WHERE s.parent_transaction_id = ?2 AND s.id <> ?3 LIMIT 1) END,
              sync_status = 'pending', ck_modified_at = ?4, updated_at = ?4
            WHERE id = ?3 AND user_id = ?1;
            """,
            textBindings: [userId],
            intBindings: [target, txId, now]
          )
        }
      }
    }

    TransactionRepository.invalidateCache()
    if result.total > 0 {
      result.affectedParentIds = Set(transactionRepo.fetchAllTransactions()
        .filter { $0.id.map(orphanIds.contains) ?? false }
        .compactMap(\.parentTransactionId))
    }
    if result.total > 0 || !result.conflicts.isEmpty {
      logWarning("[InstallmentParentRepair] linked \(result.linkedByRecordName) by record name, \(result.linkedByLegacyName) by legacy name, joined \(result.joined); conflicts: \(result.conflicts)")
      NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
    }
    return result
  }

  /// One-time launch pass, once per account on this device.
  static func runIfNeeded(transactionRepo: TransactionRepository, userId: String) {
    let key = "hasRepairedOrphanedInstallmentParents_v1_\(userId)"
    guard !UserDefaults.standard.bool(forKey: key) else { return }

    // The hydration rule every repair obeys: a half-pulled device may simply not have the parent YET,
    // and would "repair" a link the next pull resolves properly. With sync off there is nothing
    // left to arrive.
    let hydrated = UserDefaults.standard.bool(forKey: "syncFullPullVerified_v2")
    guard hydrated || !UserDefaultsManager.getSyncEnabled() else { return }

    DBHelper.shared.snapshotDatabase(tag: "pre-installment-parent-repair")
    let result = run(transactionRepo: transactionRepo, userId: userId)

    // Installment reminders are bucketed per parent; the links just changed.
    for parentId in result.affectedParentIds {
      InstallmentNotificationManager.shared.rescheduleNotifications(parentTransactionId: parentId)
    }
    UserDefaults.standard.set(true, forKey: key)
  }
}
