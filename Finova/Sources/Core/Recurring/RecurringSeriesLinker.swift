//
//  RecurringSeriesLinker.swift
//  Finova
//
//  Re-attaches recurring occurrences whose parent pointer is broken, so every CRUD action reaches
//  every row that belongs to the series.
//

import Foundation

/// Repairs recurring series membership by content, ahead of every create / edit / delete.
///
/// **Why this exists.** Series membership is stored as `parent_transaction_id` /
/// `parent_allocation_id` — a LOCAL autoincrement id. A row that arrived from another device, or that
/// predates a repair, can carry a pointer to a row that does not exist here. "Edit this and all
/// future" then silently skips it and it stays outdated forever. Relinking first is what lets the
/// selection stay a plain pointer filter.
///
/// **Deliberately local.** No CloudKit, no uuid columns, no `DeterministicIdentity`, no hydration
/// gate. It reads only through the models' coalesced accessors (`seriesPeriod ?? budgetMonthDate`,
/// `unadjustedDateTimestamp ?? dateTimestamp`), so it degrades correctly on schemas that predate
/// those columns and back-ports cleanly.
///
/// **Never creates or deletes.** Every repair is an UPDATE of one integer column, so it cannot lose
/// data and cannot diverge CloudKit beyond re-pushing the rows it re-parents.
struct RecurringSeriesLinker {
  private let transactionRepo: TransactionRepository
  private let allocationRepo: BudgetAllocationRepositoryProtocol

  init(
    transactionRepo: TransactionRepository = TransactionRepository(),
    allocationRepo: BudgetAllocationRepositoryProtocol = BudgetAllocationRepository()
  ) {
    self.transactionRepo = transactionRepo
    self.allocationRepo = allocationRepo
  }

  // MARK: - Transactions

  /// Adopts orphaned occurrences into the series owned by `parentId`. Returns how many were relinked.
  @discardableResult
  func repairTransactionSeries(around parentId: Int) -> Int {
    let all = transactionRepo.fetchAllTransactions()
    let scopeById = transactionRepo.fetchSharedGroupIds()
    let liveIds = Set(all.compactMap { $0.id })

    guard let parent = all.first(where: { $0.id == parentId }),
      let targetKey = fingerprint(of: parent, scopeById: scopeById, in: all)
    else { return 0 }

    // Rows already in the target series, and the slots they hold.
    let members = all.filter { $0.id == parentId || $0.parentTransactionId == parentId }
    var occupiedSlots = Set(members.map { $0.seriesPeriod })

    // Every amount this series has ever held. A stale orphan carries a PREVIOUS amount — that is
    // what makes it stale — so requiring it to equal the occurrence currently in effect at its slot
    // would reject exactly the rows this exists to adopt. Requiring membership in the series' own
    // set of amounts still refuses an unrelated transaction that merely shares title, category, type
    // and day.
    var seriesAmounts = Set(members.map { $0.amount })

    var relinked = 0

    // Ascending by slot, so a run of adopted rows extends the series' coverage in order.
    for candidate in all.sorted(by: { $0.seriesPeriod < $1.seriesPeriod }) {
      guard let candidateId = candidate.id, candidateId != parentId else { continue }
      guard candidate.parentTransactionId != parentId else { continue }
      guard candidate.mode == .recurring else { continue }

      // A series cannot own slots that precede its own start — see the allocation side. Adoption
      // has to agree with materialization, which is strictly forward-only from the parent's slot.
      guard candidate.seriesPeriod >= parent.seriesPeriod else { continue }

      // The fingerprint IS the membership test: same ledger, same title, category, type and anchor
      // day. Amount is checked separately, below, against the set the series has held.
      //
      // A rival series matching all of that used to make this bail ("ambiguous"). But two series
      // that agree on every one of those fields are indistinguishable in the UI too — the user sees
      // one recurring expense — and leaving them split is precisely what made an edit or delete skip
      // the months the other parent happened to own. Merging is the requested behaviour: a CRUD
      // action should reach everything that matches by day, value, category and title.
      guard fingerprint(of: candidate, scopeById: scopeById, in: all) == targetKey else { continue }

      // A row whose parent is live and does NOT match this fingerprint belongs to a genuinely
      // different series — never take it. (Reached only when the candidate itself matches but its
      // parent does not, i.e. the pointer is already wrong.)
      if let pointer = candidate.parentTransactionId, pointer != candidateId,
        liveIds.contains(pointer),
        let pointerRow = all.first(where: { $0.id == pointer }),
        fingerprint(of: pointerRow, scopeById: scopeById, in: all) != targetKey
      {
        continue
      }

      // The day check the fingerprint can't express: clamping means a day-31 series reads as day 28
      // in February, so raw equality would split it. Compared against the series' anchor day.
      let candidateDay = SeriesDay.anchorDay(of: candidate)
      let parentDay = SeriesDay.anchorDay(of: parent)
      guard
        SeriesDay.matches(
          candidateDay, inMonthOf: candidate.unadjustedDate,
          parentDay, inMonthOf: parent.unadjustedDate)
      else { continue }

      guard seriesAmounts.contains(candidate.amount) else { continue }

      // BOUND 2 — never merge into an occupied slot. Two rows in one slot is the duplicate this
      // whole design exists to prevent.
      guard !occupiedSlots.contains(candidate.seriesPeriod) else {
        logWarning(
          "[SeriesLink] slot \(candidate.seriesPeriod) already held by series \(parentId) — leaving row \(candidateId) alone"
        )
        continue
      }

      do {
        try transactionRepo.updateParentTransactionId(
          transactionId: candidateId, parentId: parentId)
        occupiedSlots.insert(candidate.seriesPeriod)
        seriesAmounts.insert(candidate.amount)
        relinked += 1
        logWarning(
          "[SeriesLink] adopted transaction \(candidateId) ('\(candidate.title)', slot \(candidate.seriesPeriod)) into series \(parentId)"
        )
      } catch {
        logError("[SeriesLink] failed to relink transaction \(candidateId): \(error)")
      }
    }

    if relinked > 0 {
      RecurringNotificationManager.shared.rescheduleNotifications(parentTransactionId: parentId)
    }

    return relinked
  }

  private func fingerprint(
    of transaction: Transaction, scopeById: [Int: String], in all: [Transaction]
  ) -> SeriesFingerprint? {
    guard let id = transaction.id else { return nil }
    // Anchor day follows the series parent when it is known locally, so a clamped child doesn't
    // report a different identity from its own parent.
    let anchorSource =
      transaction.parentTransactionId
      .flatMap { pointer in all.first(where: { $0.id == pointer }) } ?? transaction
    return SeriesFingerprint(
      scope: scopeById[id],
      title: transaction.title,
      category: transaction.category.key,
      type: transaction.type.key,
      anchorDay: SeriesDay.anchorDay(of: anchorSource))
  }

  // MARK: - Allocations

  /// Consolidates every recurring allocation row for one (category, scope) into the series owned by
  /// `parentId`. Returns how many were re-parented.
  ///
  /// **Category + scope IS the series identity for an allocation.** There is no title, no type and
  /// no day to distinguish two series, and the storage layer allows at most ONE live allocation per
  /// (month, category, scope) — so two recurring "series" for the same category in the same ledger
  /// are not two timelines, they are one timeline whose rows got split across two parents. Merging
  /// them is the correct reading, not a guess.
  ///
  /// This is why an edit or delete could skip a couple of months in the middle of a series: those
  /// months' rows had been created by an EARLIER series (creation rejects a month that is already
  /// taken, so the new series was born with holes exactly there), and a scope filter keyed on the
  /// parent pointer never saw them. They rendered with stale values forever.
  ///
  /// Note that `fetchAllAllocations()` is personal-scoped, so this can never reach a group
  /// allocation and therefore can never merge across ledgers. Group allocation scoping is a separate
  /// known gap.
  @discardableResult
  func repairAllocationSeries(around parentId: Int) -> Int {
    let all = allocationRepo.fetchAllAllocations()

    guard let parent = all.first(where: { $0.dbId == parentId }) else { return 0 }
    let targetKey = AllocationSeriesFingerprint(
      scope: parent.sharedGroupId, category: parent.category.key)

    let members = all.filter { $0.dbId == parentId || $0.parentAllocationId == parentId }
    var occupiedMonths = Set(members.map { $0.monthDate })

    var relinked = 0

    // Ascending, so a merged run is adopted in order and each adoption extends the series' own
    // month coverage for the next candidate.
    for candidate in all.sorted(by: { $0.monthDate < $1.monthDate }) {
      guard let candidateId = candidate.dbId, candidateId != parentId else { continue }
      guard candidate.parentAllocationId != parentId else { continue }

      // A series cannot own months that precede its own start. Without this, creating a series in
      // 2027 adopted a previous series' 2026 history — and a later "delete all" would then wipe
      // months the user never associated with it. Materialization already refuses to generate
      // before the parent's month; adoption has to agree.
      guard candidate.monthDate >= parent.monthDate else { continue }

      // Must already participate in recurrence. A plain one-off allocation the user created for a
      // single month is NOT part of anyone's series and must never be swept in — that is the one
      // distinction category + scope cannot make on its own.
      //
      // "Owns children" is the third case and it is not optional: a BOUNDED series has its parent's
      // `is_recurring` cleared (that flag is how the end month is stored), so its parent reads
      // exactly like a one-off — `isRecurring == false`, `parentAllocationId == nil`. Without this
      // the parent of an earlier bounded series was never adopted, and the month it occupied stayed
      // stranded outside the current series: the "skipped a couple of months" report.
      let ownsChildren = all.contains { $0.parentAllocationId == candidateId }
      guard candidate.isRecurring || candidate.parentAllocationId != nil || ownsChildren else {
        continue
      }

      guard
        AllocationSeriesFingerprint(scope: candidate.sharedGroupId, category: candidate.category.key)
          == targetKey
      else { continue }

      // Never merge into an occupied month. Storage should already make this impossible, but the
      // uniqueness check is enforced in Swift rather than by a constraint, and the legacy
      // UserDefaults migration bypasses it — so duplicates can exist and must not be compounded.
      guard !occupiedMonths.contains(candidate.monthDate) else {
        logWarning(
          "[SeriesLink] month \(candidate.monthDate) already held by allocation series \(parentId) — leaving row \(candidateId) alone"
        )
        continue
      }

      do {
        try allocationRepo.updateParentAllocationId(id: candidateId, parentId: parentId)
        occupiedMonths.insert(candidate.monthDate)
        relinked += 1
        logWarning(
          "[SeriesLink] adopted allocation \(candidateId) ('\(candidate.category.key)', month \(candidate.monthDate)) into series \(parentId)"
        )

        // Flatten: anything that pointed at the row we just adopted must now point at the target.
        // Series membership is matched one level deep (`parentAllocationId == parentId`), so leaving
        // a chain would hide those grandchildren from every scoped edit and delete — reintroducing
        // the exact bug this repair exists to close.
        if ownsChildren {
          for grandchild in all where grandchild.parentAllocationId == candidateId {
            guard let grandchildId = grandchild.dbId else { continue }
            guard !occupiedMonths.contains(grandchild.monthDate) else { continue }
            try allocationRepo.updateParentAllocationId(id: grandchildId, parentId: parentId)
            occupiedMonths.insert(grandchild.monthDate)
            relinked += 1
          }
        }
      } catch {
        logError("[SeriesLink] failed to relink allocation \(candidateId): \(error)")
      }
    }

    return relinked
  }
}
