//
//  InstallmentParentRepairTests.swift
//  FinovaTests
//
//  Installment children synced before their parent kept the sender's local parent id, which means
//  nothing on the receiver. The repair re-links them from what the row still carries, and joins a
//  purchase split across several dangling ids — never deleting, never creating.
//

import Foundation
import XCTest

@testable import Finova

final class InstallmentParentRepairTests: XCTestCase {
  private var transactionRepo: TransactionRepository!
  private var uid: String!
  private let db = DBHelper.shared

  override func setUp() {
    super.setUp()
    uid = "test_parent_repair_\(UUID().uuidString)"
    UIDUserDefaultsManager.shared.currentUserUID = uid
    transactionRepo = TransactionRepository()
    transactionRepo.clearAllTransactionsForTesting()
  }

  override func tearDown() {
    transactionRepo.clearAllTransactionsForTesting()
    UIDUserDefaultsManager.shared.signOut()
    super.tearDown()
  }

  // MARK: - Helpers

  private func insertParent(title: String, total: Int, ckName: String) throws -> Int {
    let id = try transactionRepo.insertTransactionAndGetId(
      CloudKitSyncTestHelpers.makeTransactionModel(
        title: title, amount: 0, hasInstallments: true, totalInstallments: total))
    transactionRepo.setCKRecordId(for: id, ckRecordName: ckName)
    return id
  }

  private func insertChild(
    title: String, number: Int, total: Int, danglingParent: Int, ckParent: String? = nil,
    card: Int? = nil
  ) throws -> Int {
    let id = try transactionRepo.insertTransactionAndGetId(
      CloudKitSyncTestHelpers.makeTransactionModel(
        title: title, amount: 1_000, parentTransactionId: danglingParent,
        installmentNumber: number, totalInstallments: total, creditCardId: card))
    if let ckParent {
      db.executeSyncUpdate(
        "UPDATE Transactions SET ck_parent_record_name = ? WHERE id = ?;",
        textBindings: [ckParent], intBindings: [id])
    }
    return id
  }

  private func parentId(of id: Int) throws -> Int? {
    TransactionRepository.invalidateCache()
    return try XCTUnwrap(transactionRepo.fetchAllTransactions().first { $0.id == id }).parentTransactionId
  }

  // MARK: - Tests

  /// HBO Max on the reporter's phone: the children still named their parent's record, and that
  /// parent was right there under a different local id.
  func testChildrenFollowTheParentRecordNameTheyCarry() throws {
    let parent = try insertParent(title: "HBO Max - Installment Parent", total: 3, ckName: "transaction-507A0D9B")
    let kids = try (1...3).map {
      try insertChild(title: "HBO Max", number: $0, total: 3, danglingParent: 999_001, ckParent: "transaction-507A0D9B")
    }

    let result = InstallmentParentRepair.run(transactionRepo: transactionRepo, userId: uid)

    XCTAssertEqual(result.linkedByRecordName, 3)
    for kid in kids { XCTAssertEqual(try parentId(of: kid), parent) }
    XCTAssertEqual(result.affectedParentIds, [parent])
  }

  /// Old record names encode the creating device's local id — the same number the child kept.
  func testLegacyRecordNameMatchesTheDanglingId() throws {
    let parent = try insertParent(title: "Toalheiro elétrico - Installment Parent", total: 2, ckName: "transaction-999002")
    let kid = try insertChild(title: "Toalheiro elétrico", number: 1, total: 2, danglingParent: 999_002)

    let result = InstallmentParentRepair.run(transactionRepo: transactionRepo, userId: uid)

    XCTAssertEqual(result.linkedByLegacyName, 1)
    XCTAssertEqual(try parentId(of: kid), parent)
  }

  /// A record name alone is not enough: a parent with another title is a different purchase.
  func testARecordNameWithAnotherTitleIsNotFollowed() throws {
    _ = try insertParent(title: "Something else", total: 2, ckName: "transaction-ABC")
    let kid = try insertChild(title: "Maquiê", number: 2, total: 2, danglingParent: 999_003, ckParent: "transaction-ABC")

    let result = InstallmentParentRepair.run(transactionRepo: transactionRepo, userId: uid)

    XCTAssertEqual(result.total, 0)
    XCTAssertEqual(try parentId(of: kid), 999_003, "Left exactly as it was")
  }

  /// Adam Audio: one purchase split across three dangling ids, no number twice — joined into the
  /// largest piece.
  func testSplitPiecesOfOnePurchaseAreJoined() throws {
    let a = try [1, 2].map { try insertChild(title: "Adam", number: $0, total: 10, danglingParent: 999_010, card: 70) }
    let b = try (3...9).map { try insertChild(title: "Adam", number: $0, total: 10, danglingParent: 999_011, card: 70) }
    let c = try insertChild(title: "Adam", number: 10, total: 10, danglingParent: 999_012, card: 70)

    let result = InstallmentParentRepair.run(transactionRepo: transactionRepo, userId: uid)

    XCTAssertEqual(result.joined, 3)
    for id in a + b + [c] { XCTAssertEqual(try parentId(of: id), 999_011) }
  }

  /// Sutiã: installment #2 three times. Which copies are real is the user's call — nothing moves.
  func testARepeatedInstallmentNumberIsReportedNotResolved() throws {
    let first = try [1, 2].map { try insertChild(title: "Sutiã", number: $0, total: 2, danglingParent: 999_020) }
    let dupA = try insertChild(title: "Sutiã", number: 2, total: 2, danglingParent: 999_021)
    let dupB = try insertChild(title: "Sutiã", number: 2, total: 2, danglingParent: 999_022)

    let result = InstallmentParentRepair.run(transactionRepo: transactionRepo, userId: uid)

    XCTAssertEqual(result.conflicts, ["Sutiã"])
    XCTAssertEqual(result.joined, 0)
    for id in first { XCTAssertEqual(try parentId(of: id), 999_020) }
    XCTAssertEqual(try parentId(of: dupA), 999_021)
    XCTAssertEqual(try parentId(of: dupB), 999_022)
  }

  func testRunningTwiceChangesNothingTheSecondTime() throws {
    _ = try insertParent(title: "HBO Max", total: 2, ckName: "transaction-X")
    _ = try (1...2).map {
      try insertChild(title: "HBO Max", number: $0, total: 2, danglingParent: 999_030, ckParent: "transaction-X")
    }
    XCTAssertEqual(InstallmentParentRepair.run(transactionRepo: transactionRepo, userId: uid).total, 2)
    XCTAssertEqual(InstallmentParentRepair.run(transactionRepo: transactionRepo, userId: uid).total, 0)
  }
}
