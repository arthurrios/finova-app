//
//  StatementScopeTests.swift
//  FinovaTests
//
//  A statement's count and total must come from the same ledger as the transactions listed under it.
//
//  They did not. In group context `generateStatementTransactions` read the database with NO scope
//  predicate — `WHERE statement_id = ?` and nothing else — while the transaction list beside it went
//  through the (scoped) repository. Once the personal reads were narrowed to
//  `shared_group_id IS NULL`, that produced a statement reporting "4 transactions" above an empty
//  table with no total: the count was drawn from the personal ledger, the list from the group's.
//
//  A screen that contradicts itself is worse than one that shows nothing, because the user cannot
//  tell which half to believe.
//

import XCTest

@testable import Finova

final class StatementScopeTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var userUID: String!
    private let groupId = "grp-statement-scope"

    private var statementId: Int = 0

    override func setUp() {
        super.setUp()
        userUID = "stmtscope_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaStmtScope-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        TransactionRepository.invalidateCache()

        // A card and a statement to hang transactions off.
        let cardId = CreditCardRepository(db: db).insertCard(
            CreditCard(
                name: "Visa", lastFourDigits: "4242", cardBrand: .visa,
                closingDay: 5, dueDay: 12, creditLimit: 500_000,
                cardColor: .blue, userId: userUID,
                isDeleted: false, isDefault: false, createdAt: Date(), updatedAt: Date()
            )
        )
        statementId = (try? db.insertStatement(
            creditCardId: cardId ?? 0,
            closingDate: Int(Date().timeIntervalSince1970),
            dueDate: Int(Date().addingTimeInterval(7 * 86400).timeIntervalSince1970),
            totalAmount: 0, userId: userUID)) ?? 0
        XCTAssertGreaterThan(statementId, 0, "setup: statement insert failed")
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        TransactionRepository.invalidateCache()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    /// Books a transaction onto the statement in the given scope.
    private func addCharge(title: String, amount: Int, sharedGroupId: String?) {
        let repo = TransactionRepository(db: db)
        try? repo.insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(title: title, amount: amount))
        guard let id = db.fetchSingleInt(
            "SELECT id FROM Transactions WHERE title = ?;", textBinding: title) else {
            return XCTFail("setup: could not insert \(title)")
        }
        try? db.executeGroupWriteChecked(
            """
            UPDATE Transactions SET statement_id = ?, shared_group_id = ?, user_id = ?
             WHERE id = ?;
            """,
            orderedBindings: [statementId, sharedGroupId, userUID, id])
        TransactionRepository.invalidateCache()
    }

    // MARK: - Each ledger sees only its own

    func testPersonalScopeCountsOnlyPersonalCharges() {
        addCharge(title: "Groceries", amount: 5_000, sharedGroupId: nil)
        addCharge(title: "Dinner", amount: 3_000, sharedGroupId: nil)
        addCharge(title: "GroupLunch", amount: 9_000, sharedGroupId: groupId)

        let totals = db.statementTotals(statementId: statementId, scope: .personal)

        XCTAssertEqual(totals.count, 2, "Only the two personal charges belong to the personal ledger")
        XCTAssertEqual(totals.total, 8_000, "and the total must match those two, not all three")
    }

    func testGroupScopeCountsOnlyGroupCharges() {
        addCharge(title: "Groceries", amount: 5_000, sharedGroupId: nil)
        addCharge(title: "GroupLunch", amount: 9_000, sharedGroupId: groupId)

        let totals = db.statementTotals(statementId: statementId, scope: .group(groupId))

        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals.total, 9_000)
    }

    /// The reported symptom, reduced: every charge is personal, so the GROUP statement must report
    /// nothing rather than reporting the personal ledger's figures above an empty table.
    func testGroupScopeReportsNothingWhenEveryChargeIsPersonal() {
        addCharge(title: "Groceries", amount: 5_000, sharedGroupId: nil)
        addCharge(title: "Dinner", amount: 3_000, sharedGroupId: nil)

        let totals = db.statementTotals(statementId: statementId, scope: .group(groupId))

        XCTAssertEqual(
            totals.count, 0,
            """
            The group statement counted personal charges. That is what produced "4 transactions" \
            above an empty table: the count came from an unscoped query, the list from a scoped one.
            """
        )
        XCTAssertEqual(totals.total, 0, "and no total, consistently — not a total with no rows")
    }

    /// A charge belonging to a DIFFERENT group is not this group's either.
    func testAnotherGroupsChargeIsExcluded() {
        addCharge(title: "OtherGroup", amount: 7_000, sharedGroupId: "some-other-group")

        XCTAssertEqual(db.statementTotals(statementId: statementId, scope: .group(groupId)).count, 0)
        XCTAssertEqual(db.statementTotals(statementId: statementId, scope: .personal).count, 0)
    }

    // MARK: - The invariant

    /// Whatever the data, count and total must describe the SAME set of rows. This is the property
    /// whose violation the user actually sees.
    func testCountAndTotalAlwaysDescribeTheSameRows() {
        addCharge(title: "P1", amount: 1_000, sharedGroupId: nil)
        addCharge(title: "P2", amount: 2_000, sharedGroupId: nil)
        addCharge(title: "G1", amount: 4_000, sharedGroupId: groupId)

        for scope in [LedgerScope.personal, LedgerScope.group(groupId)] {
            let totals = db.statementTotals(statementId: statementId, scope: scope)
            if totals.count == 0 {
                XCTAssertEqual(totals.total, 0, "zero rows must mean zero total")
            } else {
                XCTAssertGreaterThan(
                    totals.total, 0,
                    "a non-zero count must come with a non-zero total — they read one query now"
                )
            }
        }
    }

    /// Soft-deleted charges count for neither. The old count query omitted the `is_deleted` filter
    /// that the sum query had, so a deleted charge inflated the count but not the total.
    func testSoftDeletedChargesAreExcludedFromBoth() {
        addCharge(title: "Live", amount: 5_000, sharedGroupId: nil)
        addCharge(title: "Deleted", amount: 9_000, sharedGroupId: nil)
        try? db.executeGroupWriteChecked(
            "UPDATE Transactions SET is_deleted = 1 WHERE title = 'Deleted';", orderedBindings: [])

        let totals = db.statementTotals(statementId: statementId, scope: .personal)

        XCTAssertEqual(totals.count, 1, "the deleted charge must not be counted")
        XCTAssertEqual(totals.total, 5_000)
    }
}
