//
//  TransactionDetailsViewModel.swift
//  Finova
//
//  Created by Arthur Rios on 05/09/25.
//

import Foundation
import UIKit

final class TransactionDetailsViewModel {
  private let transactionRepository: TransactionRepositoryProtocol
  private(set) var transaction: Transaction

  init(transactionRepository: TransactionRepositoryProtocol, transaction: Transaction) {
    self.transactionRepository = transactionRepository
    self.transaction = transaction
  }

  func deleteTransaction() -> Result<Void, Error> {
    guard let transactionId = transaction.id else {
      return .failure(
        NSError(
          domain: "TransactionDetails", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Invalid transaction ID"]))
    }

    // Capture group ID before deletion (needed for activity log)
    let groupId = getSharedGroupId()

    do {
      try transactionRepository.deleteTransactionAndRelated(id: transactionId)

      if let groupId = groupId {
        GroupNotificationService.shared.logActivity(
          action: .transactionDeleted, groupId: groupId, detail: transaction.title)
        SyncEngine.shared.pushPendingChangesNow()
      }

      return .success(())
    } catch {
      return .failure(error)
    }
  }

  func deleteTransactionWithOption(transactionId: Int, option: RecurringCleanupOption) -> Result<
    Void, Error
  > {
    do {
      // Use the same logic as the transactions table for consistency
      let allTransactions = transactionRepository.fetchAllTransactions()
      guard let transaction = allTransactions.first(where: { $0.id == transactionId }) else {
        return .failure(TransactionError.transactionNotFound)
      }

      // Capture group ID before deletion (needed for activity log)
      let groupId = getSharedGroupId()

      // Handle simple transactions directly
      if transaction.isRecurring != true && transaction.parentTransactionId == nil
        && transaction.hasInstallments != true
      {
        try transactionRepository.delete(id: transactionId)
      } else {
        // For complex transactions, use the repository method that handles cleanup properly
        try transactionRepository.deleteTransactionWithOption(id: transactionId, option: option)
      }

      if let groupId = groupId {
        GroupNotificationService.shared.logActivity(
          action: .transactionDeleted, groupId: groupId, detail: transaction.title)
        SyncEngine.shared.pushPendingChangesNow()
      }

      return .success(())
    } catch {
      return .failure(error)
    }
  }

  func deleteTransactionAsync(completion: @escaping (Result<Void, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }
      let result = self.deleteTransaction()
      DispatchQueue.main.async { completion(result) }
    }
  }

  func deleteTransactionWithOptionAsync(
    transactionId: Int, option: RecurringCleanupOption,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }
      let result = self.deleteTransactionWithOption(transactionId: transactionId, option: option)
      DispatchQueue.main.async { completion(result) }
    }
  }

  func getFormattedAmount() -> String {
    return transaction.amount.currencyString
  }

  func getFormattedDate() -> String {
    return DateFormatter.fullDateFormatter.string(from: transaction.date)
  }

  func getCategoryDisplayName() -> String {
    return transaction.category.rawValue.localized
  }

  func getTransactionTypeColor() -> UIColor {
    return transaction.type == .income ? Colors.mainGreen : Colors.mainRed
  }

  func getCreditCard() -> CreditCard? {
    guard let cardId = transaction.creditCardId else { return nil }
    return CreditCardRepository().fetchCard(byId: cardId)
  }

  // MARK: - Statement Move

  func isCreditCardTransaction() -> Bool {
    return transaction.creditCardId != nil && transaction.isCreditCardStatement != true
  }

  func getCurrentStatement() -> CreditCardStatement? {
    guard let stmtId = transaction.statementId else { return nil }
    guard let cardId = transaction.creditCardId else { return nil }
    let statements = StatementRepository().fetchStatements(forCardId: cardId)
    return statements.first(where: { $0.id == stmtId })
  }

  func getAvailableStatements() -> [CreditCardStatement] {
    guard let cardId = transaction.creditCardId else { return [] }
    let statements = StatementRepository().fetchStatements(forCardId: cardId)
    return statements.sorted { $0.closingDate < $1.closingDate }
  }

  /// Returns month options (past 6 through future 2) for the move-to-statement picker.
  /// Each entry is a `(label, Date)` where `Date` is the 1st of that month.
  func getMonthOptionsForMove() -> [(label: String, firstOfMonth: Date)] {
    let calendar = Calendar.current
    let now = Date()
    let formatter = DateFormatter.monthYearFormatter
    var options: [(label: String, firstOfMonth: Date)] = []

    for offset in -6...2 {
      guard let refDate = calendar.date(byAdding: .month, value: offset, to: now) else { continue }
      let components = calendar.dateComponents([.year, .month], from: refDate)
      guard let firstOfMonth = calendar.date(from: components) else { continue }
      options.append((label: formatter.string(from: firstOfMonth), firstOfMonth: firstOfMonth))
    }

    return options
  }

  /// Moves a transaction to a statement for the given month, creating the statement if needed.
  func moveToStatementForMonth(_ firstOfMonth: Date) {
    guard let cardId = transaction.creditCardId else { return }
    guard let userId = AuthenticationManager.shared.currentUser?.uid else { return }
    let cardRepo = CreditCardRepository()
    guard let card = cardRepo.fetchCard(byId: cardId) else { return }

    let ccService = CreditCardService()
    guard let targetStatement = ccService.getOrCreateStatement(
      for: card, transactionDate: firstOfMonth, userId: userId
    ) else { return }

    moveToStatement(targetStatement)
  }

  func moveToStatement(_ targetStatement: CreditCardStatement) {
    guard let txId = transaction.id,
          let cardId = transaction.creditCardId,
          let targetId = targetStatement.id else { return }

    let creditCardService = CreditCardService()
    let repo = transactionRepository as? TransactionRepository ?? TransactionRepository()

    creditCardService.moveTransactionToStatement(
      transactionId: txId,
      creditCardId: cardId,
      toStatementId: targetId,
      fromStatementId: transaction.statementId,
      transactionRepo: repo
    )

    // Refresh transaction from DB to pick up the new statementId
    refreshTransaction()

    SyncEngine.shared.pushPendingChangesNow()
  }

  func getTransactionModeDescription() -> String {
    switch transaction.mode {
    case .normal:
      return "transaction.mode.normal".localized
    case .recurring:
      return "transaction.mode.recurring".localized
    case .installments:
      if let installmentNumber = transaction.installmentNumber,
        let totalInstallments = transaction.totalInstallments
      {
        return String(
          format: "transaction.mode.installment".localized, installmentNumber, totalInstallments)
      }
      return "transaction.mode.installments".localized
    }
  }

  func getRelatedInstallments() -> [Transaction] {
    // If this is an installment transaction, find all related installments
    guard transaction.mode == .installments else { return [] }

    // Get the parent transaction ID (either this transaction's parent or this transaction itself if it's the parent)
    let parentId: Int?
    if let currentParentId = transaction.parentTransactionId {
      parentId = currentParentId
    } else if transaction.hasInstallments == true {
      parentId = transaction.id
    } else {
      return []
    }

    guard let targetParentId = parentId else { return [] }

    // Fetch all transactions and filter for the same parent
    let allTransactions = transactionRepository.fetchAllTransactions()
    var relatedInstallments = allTransactions.filter { tx in
      // Only include actual installment transactions (not the parent)
      return tx.parentTransactionId == targetParentId && tx.installmentNumber != nil
        && tx.totalInstallments != nil
    }

    // If no installments found with the current parent ID, try to find by title and date
    // This handles cases where the parent ID changed after an update
    if relatedInstallments.isEmpty {
      // Look for installments with the same title and total installments count
      if let totalInstallments = transaction.totalInstallments {
        relatedInstallments = allTransactions.filter { tx in
          return tx.title == transaction.title && tx.totalInstallments == totalInstallments
            && tx.installmentNumber != nil && tx.mode == .installments
        }
      }
    }

    // Sort by installment number
    return relatedInstallments.sorted { first, second in
      guard let firstInstallment = first.installmentNumber,
        let secondInstallment = second.installmentNumber
      else {
        return false
      }
      return firstInstallment < secondInstallment
    }
  }

  // MARK: - Early Installment Payment

  private let earlyPaymentService = EarlyPaymentService()

  /// How many installments of this series could still be brought forward. Zero hides the entry point.
  func getPayableInstallmentCount() -> Int {
    earlyPaymentService.payableInstallments(for: transaction).count
  }

  /// True when this transaction is itself the debit created by an early payment.
  func isEarlyPayment() -> Bool {
    earlyPaymentService.isEarlyPayment(transaction)
  }

  /// The installments this debit paid for, in installment order. Empty unless it is an early payment.
  func getIncludedInstallments() -> [Transaction] {
    guard let id = transaction.id, isEarlyPayment() else { return [] }
    return earlyPaymentService.settledInstallments(forPayment: id)
  }

  /// Installments of this series that are still owed — everything not paid early.
  func getOutstandingInstallments() -> [Transaction] {
    getRelatedInstallments().excludingEarlyPaidInstallments()
  }

  func hasEarlyPaidInstallments() -> Bool {
    getOutstandingInstallments().count != getRelatedInstallments().count
  }

  /// Undoes an early payment: the installments return to their own statements and the debit is
  /// deleted. Reported as a `Result` so the screen can distinguish "done, pop back" from a failure.
  func undoEarlyPayment() -> Result<Void, Error> {
    guard let id = transaction.id else { return .failure(TransactionError.transactionNotFound) }
    do {
      try earlyPaymentService.cancelEarlyPayment(paymentId: id)
      return .success(())
    } catch {
      return .failure(error)
    }
  }

  func getTransactionType(for transactionToCheck: Transaction) -> TransactionComplexityType {
    guard let transactionId = transactionToCheck.id else { return .simple }

    // Check if this is a recurring transaction instance
    if let parentId = transactionToCheck.parentTransactionId {
      // Special case: if parentTransactionId points to itself, treat it as a parent transaction
      if parentId == transactionId {
        // Continue to parent transaction checks below
      } else {
        let allTransactions = transactionRepository.fetchAllTransactions()
        let parentTransaction = allTransactions.first(where: { $0.id == parentId })

        if parentTransaction?.isRecurring == true {
          return .recurringInstance
        } else {
          return .installmentInstance
        }
      }
    }

    // Check if this is a parent recurring transaction
    if transactionToCheck.isRecurring == true {
      return .recurringParent
    }

    // Special case: if mode is recurring but isRecurring is false (data corruption), treat as recurring parent
    if transactionToCheck.mode == .recurring && transactionToCheck.isRecurring != true {
      return .recurringParent
    }

    // Check if this is a parent installment transaction (only if not recurring)
    if transactionToCheck.hasInstallments == true && transactionToCheck.isRecurring != true {
      return .installmentParent
    }

    return .simple
  }

  // MARK: - Permission Checks

  func canEditTransaction(in group: BudgetGroup?) -> Bool {
    guard let group = group else { return true }
    return BudgetGroupService.shared.currentUserCan(
      \.canEditTransactions,
      own: \.canEditOwnTransactions,
      createdByUid: transaction.createdByUid,
      in: group
    )
  }

  func canDeleteTransaction(in group: BudgetGroup?) -> Bool {
    guard let group = group else { return true }
    return BudgetGroupService.shared.currentUserCan(
      \.canDeleteTransactions,
      own: \.canDeleteOwnTransactions,
      createdByUid: transaction.createdByUid,
      in: group
    )
  }

  /// Returns the BudgetGroup this transaction belongs to, if any.
  func getGroup() -> BudgetGroup? {
    guard let groupId = getSharedGroupId() else { return nil }
    return BudgetGroupService.shared.fetchGroup(byId: groupId)
  }

  // MARK: - Group Context

  func getSharedGroupId() -> String? {
    guard let txId = transaction.id else { return nil }
    return DBHelper.shared.getSharedGroupId(transactionId: txId)
  }

  func isInGroup() -> Bool {
    return getSharedGroupId() != nil
  }

  func getAvailableGroups() -> [BudgetGroup] {
    return BudgetGroupService.shared.fetchAllGroups()
  }

  func moveTransactionToGroup(_ groupId: String) {
    guard let txId = transaction.id else { return }
    let repo = transactionRepository as? TransactionRepository
    repo?.updateSharedGroupId(transactionId: txId, groupId: groupId)
    let ckRecordName = repo?.fetchCKRecordName(for: txId)

    GroupNotificationService.shared.logActivity(
      action: .transactionCreated,
      groupId: groupId,
      detail: transaction.title,
      targetRecordName: ckRecordName
    )
    SyncEngine.shared.pushPendingChangesNow()
  }

  func moveTransactionToPersonal() {
    guard let txId = transaction.id else { return }
    let groupId = getSharedGroupId()
    if let groupId = groupId {
      GroupNotificationService.shared.logActivity(
        action: .transactionDeleted,
        groupId: groupId,
        detail: transaction.title
      )
      SyncEngine.shared.pushPendingChangesNow()
    }
    let repo = transactionRepository as? TransactionRepository
    repo?.updateSharedGroupId(transactionId: txId, groupId: nil)
  }

  func refreshTransaction() {
    // Reload the transaction from the repository to get fresh data
    guard let transactionId = transaction.id else { return }

    let allTransactions = transactionRepository.fetchAllTransactions()

    // For installment transactions, we need to find the updated transaction by parent ID and installment number
    // since the individual installment IDs change when we recreate the installment series
    if transaction.mode == .installments,
      let parentId = transaction.parentTransactionId,
      let installmentNumber = transaction.installmentNumber
    {
      // First try to find by the same parent ID and installment number
      if let updatedTransaction = allTransactions.first(where: {
        $0.parentTransactionId == parentId && $0.installmentNumber == installmentNumber
      }) {
        self.transaction = updatedTransaction
        return
      }

      // If not found, the parent ID might have changed. Look for any installment with the same title and date
      if let updatedTransaction = allTransactions.first(where: {
        $0.title == transaction.title && $0.installmentNumber == installmentNumber
          && $0.mode == .installments
          && Calendar.current.isDate($0.date, inSameDayAs: transaction.date)
      }) {
        self.transaction = updatedTransaction
        return
      }
    } else {
      // For normal and recurring transactions, find by ID
      if let updatedTransaction = allTransactions.first(where: { $0.id == transactionId }) {
        self.transaction = updatedTransaction
      }
    }
  }

  func refreshRelatedInstallments() {
    // Force refresh of related installments data
    // This is called after updating installment transactions to ensure the additional details are correct
    if transaction.mode == .installments {
      _ = getRelatedInstallments()
    }
  }
}
