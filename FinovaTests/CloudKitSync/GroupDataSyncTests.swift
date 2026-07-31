//
//  GroupDataSyncTests.swift
//  FinovaTests
//
//  Created by Arthur Rios on 14/02/26.
//

import CloudKit
import XCTest

@testable import Finova

final class GroupDataSyncTests: XCTestCase {
    private var ownerUID: String!
    private var memberUID: String!
    private var mockCloud: MockCloudStore!
    private var ownerDevice: DeviceSimulator!
    private var memberDevice: DeviceSimulator!
    private var groupRepo: BudgetGroupRepository!
    private var groupId: String!

    override func setUp() {
        super.setUp()
        ownerUID = "test_owner_\(UUID().uuidString)"
        memberUID = "test_member_\(UUID().uuidString)"
        mockCloud = MockCloudStore()
        ownerDevice = DeviceSimulator(userUID: ownerUID, mockCloud: mockCloud)
        memberDevice = DeviceSimulator(userUID: memberUID, mockCloud: mockCloud)
        groupRepo = BudgetGroupRepository()

        // Create a test group
        let group = CloudKitSyncTestHelpers.makeGroup(
            name: "Shared Budget",
            ownerId: ownerUID,
            ownerName: "Owner",
            ownerEmail: "owner@test.com"
        )
        groupId = group.id
        groupRepo.insertGroup(group)
    }

    override func tearDown() {
        ownerDevice.cleanup()
        memberDevice.cleanup()
        // Clean up budgets
        let budgetRepo = BudgetRepository()
        for budget in budgetRepo.fetchBudgets() {
            try? budgetRepo.delete(monthDate: budget.monthDate)
        }
        mockCloud.reset()

        // Clean up group data
        groupRepo.softDeleteGroup(id: groupId)

        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Owner Transaction Includes Group ID

    func testOwnerTransactionIncludesGroupId() {
        ownerDevice.activate()

        let model = CloudKitSyncTestHelpers.makeTransactionModel(
            title: "Group Expense",
            amount: 15000
        )
        try! ownerDevice.transactionRepo.insertTransaction(model)
        TransactionRepository.invalidateCache()

        // Tag the transaction with the group ID
        let txs = ownerDevice.transactionRepo.fetchAllTransactions()
        guard let txId = txs.first?.id else {
            XCTFail("No transaction found")
            return
        }
        ownerDevice.transactionRepo.updateSharedGroupId(transactionId: txId, groupId: groupId)

        ownerDevice.pushTransactions()

        // Verify the CKRecord in mock cloud has sharedGroupId
        let cloudRecords = mockCloud.fetchAll(recordType: "Transaction")
        XCTAssertEqual(cloudRecords.count, 1)

        let cloudGroupId = cloudRecords.first?["sharedGroupId"] as? String
        XCTAssertEqual(cloudGroupId, groupId, "CKRecord should contain the sharedGroupId")
    }

    // MARK: - Member Receives Group Transaction

    func testMemberReceivesGroupTransaction() {
        // Owner creates and tags a transaction with group
        ownerDevice.activate()

        let model = CloudKitSyncTestHelpers.makeTransactionModel(
            title: "Shared Grocery",
            amount: 8000
        )
        try! ownerDevice.transactionRepo.insertTransaction(model)
        TransactionRepository.invalidateCache()

        let txs = ownerDevice.transactionRepo.fetchAllTransactions()
        guard let txId = txs.first?.id else {
            XCTFail("No transaction found")
            return
        }
        ownerDevice.transactionRepo.updateSharedGroupId(transactionId: txId, groupId: groupId)
        ownerDevice.pushTransactions()

        // Member pulls
        memberDevice.activate()
        memberDevice.pullTransactions()

        // Member should see it via fetchTransactionsForGroup
        let groupTxs = memberDevice.transactionRepo.fetchTransactionsForGroup(groupId: groupId)
        XCTAssertEqual(groupTxs.count, 1)
        XCTAssertEqual(groupTxs.first?.title, "Shared Grocery")
        XCTAssertEqual(groupTxs.first?.amount, 8000)
    }

    // MARK: - Member Creates Group Transaction, Owner Receives

    func testMemberCreatesGroupTransaction_OwnerReceives() {
        memberDevice.activate()

        let model = CloudKitSyncTestHelpers.makeTransactionModel(
            title: "Member Expense",
            amount: 3500
        )
        try! memberDevice.transactionRepo.insertTransaction(model)
        TransactionRepository.invalidateCache()

        let txs = memberDevice.transactionRepo.fetchAllTransactions()
        guard let txId = txs.first?.id else {
            XCTFail("No transaction found")
            return
        }
        memberDevice.transactionRepo.updateSharedGroupId(transactionId: txId, groupId: groupId)
        memberDevice.pushTransactions()

        // Owner pulls
        ownerDevice.activate()
        ownerDevice.pullTransactions()

        let groupTxs = ownerDevice.transactionRepo.fetchTransactionsForGroup(groupId: groupId)
        XCTAssertEqual(groupTxs.count, 1)
        XCTAssertEqual(groupTxs.first?.title, "Member Expense")
        XCTAssertEqual(groupTxs.first?.amount, 3500)
    }

    // MARK: - Group Isolation

    func testGroupIsolation() {
        // Verify that group-tagged transactions are queryable via fetchTransactionsForGroup
        // and that non-group transactions are NOT returned by group queries
        ownerDevice.activate()

        // Create a group-tagged transaction
        let groupModel = CloudKitSyncTestHelpers.makeTransactionModel(
            title: "Group Only",
            amount: 6000
        )
        try! ownerDevice.transactionRepo.insertTransaction(groupModel)
        TransactionRepository.invalidateCache()

        let txs = ownerDevice.transactionRepo.fetchAllTransactions()
        guard let txId = txs.first?.id else {
            XCTFail("No transaction found")
            return
        }
        ownerDevice.transactionRepo.updateSharedGroupId(transactionId: txId, groupId: groupId)

        // Create a non-group transaction
        let personalModel = CloudKitSyncTestHelpers.makeTransactionModel(
            title: "Personal Only",
            amount: 3000
        )
        try! ownerDevice.transactionRepo.insertTransaction(personalModel)
        TransactionRepository.invalidateCache()

        // fetchTransactionsForGroup should only return the group-tagged transaction
        let groupTxs = ownerDevice.transactionRepo.fetchTransactionsForGroup(groupId: groupId)
        XCTAssertEqual(groupTxs.count, 1, "Only group-tagged transaction should appear")
        XCTAssertEqual(groupTxs.first?.title, "Group Only")

        // A different group ID should return nothing
        let otherGroupTxs = ownerDevice.transactionRepo.fetchTransactionsForGroup(groupId: "nonexistent-group")
        XCTAssertEqual(otherGroupTxs.count, 0, "Non-matching group should return no transactions")

        // `fetchAllTransactions` is the PERSONAL ledger, so it returns only the untagged row.
        // It used to filter on `user_id` alone and therefore returned group records too, which is
        // why a group's spending was counted against personal budgets as well as the group's.
        let personalTxs = ownerDevice.transactionRepo.fetchAllTransactions()
        XCTAssertEqual(personalTxs.map(\.title), ["Personal Only"], "Personal scope excludes group rows")

        // Neither row was deleted — the group one simply belongs to a different ledger.
        XCTAssertEqual(
            ownerDevice.db.fetchSingleInt(
                "SELECT COUNT(*) FROM Transactions WHERE (is_deleted IS NULL OR is_deleted = 0);"),
            2,
            "Both transactions must still exist in the database"
        )
    }

    // MARK: - Invitation Local Flow

    func testInvitationLocalFlow() {
        let memberEmail = "member@test.com"

        // Owner creates invitation
        let invitation = CloudKitSyncTestHelpers.makeInvitation(
            groupId: groupId,
            groupName: "Shared Budget",
            inviterName: "Owner",
            inviterEmail: "owner@test.com",
            inviteeEmail: memberEmail
        )
        groupRepo.insertInvitation(invitation)

        // Member queries pending invitations
        let pending = groupRepo.fetchPendingInvitations(forEmail: memberEmail)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.groupName, "Shared Budget")
        XCTAssertEqual(pending.first?.status, "pending")

        // Member accepts
        groupRepo.updateInvitationStatus(id: invitation.id, status: "accepted")

        // Verify status updated
        let accepted = groupRepo.fetchInvitation(byId: invitation.id)
        XCTAssertEqual(accepted?.status, "accepted")

        // No more pending for this email
        let pendingAfter = groupRepo.fetchPendingInvitations(forEmail: memberEmail)
        XCTAssertEqual(pendingAfter.count, 0)
    }

    // MARK: - Budget Sync With Group ID

    func testBudgetSyncWithGroupId() {
        // Use a unique month to avoid collisions with other tests
        let cal = Calendar.current
        let uniqueMonth = cal.date(byAdding: .month, value: -7, to: Date())!
        let monthDate = uniqueMonth.monthAnchor

        ownerDevice.activate()

        // Create budget with sharedGroupId
        let budget = BudgetModel(monthDate: monthDate, amount: 400000, sharedGroupId: groupId)
        try! ownerDevice.budgetRepo.insert(budget: budget)
        ownerDevice.budgetRepo.updateSharedGroupId(monthDate: monthDate, groupId: groupId)
        ownerDevice.pushBudgets()

        // Verify the CKRecord in mock cloud has sharedGroupId
        let cloudRecords = mockCloud.fetchAll(recordType: "Budget")
        XCTAssertEqual(cloudRecords.count, 1)
        let cloudGroupId = cloudRecords.first?["sharedGroupId"] as? String
        XCTAssertEqual(cloudGroupId, groupId, "Budget CKRecord should contain sharedGroupId")

        // Verify the budget is accessible via group query
        let groupBudgets = ownerDevice.budgetRepo.fetchBudgetsForGroup(groupId: groupId)
        let matching = groupBudgets.filter { $0.monthDate == monthDate }
        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching.first?.amount, 400000)
    }

    // MARK: - Multiple Members Sync

    func testMultipleMembersSync() {
        let thirdUID = "test_third_\(UUID().uuidString)"
        let thirdDevice = DeviceSimulator(userUID: thirdUID, mockCloud: mockCloud)

        // Owner creates tx
        ownerDevice.activate()
        let model1 = CloudKitSyncTestHelpers.makeTransactionModel(
            title: "Owner TX",
            amount: 1000
        )
        try! ownerDevice.transactionRepo.insertTransaction(model1)
        TransactionRepository.invalidateCache()
        let ownerTxs = ownerDevice.transactionRepo.fetchAllTransactions()
        if let txId = ownerTxs.first?.id {
            ownerDevice.transactionRepo.updateSharedGroupId(transactionId: txId, groupId: groupId)
        }
        ownerDevice.pushTransactions()

        // Member creates tx
        memberDevice.activate()
        let model2 = CloudKitSyncTestHelpers.makeTransactionModel(
            title: "Member TX",
            amount: 2000
        )
        try! memberDevice.transactionRepo.insertTransaction(model2)
        TransactionRepository.invalidateCache()
        let memberTxs = memberDevice.transactionRepo.fetchAllTransactions()
        // Find the member's own transaction (not the one from cloud)
        if let tx = memberTxs.first(where: { $0.title == "Member TX" }), let txId = tx.id {
            memberDevice.transactionRepo.updateSharedGroupId(transactionId: txId, groupId: groupId)
        }
        memberDevice.pushTransactions()

        // Third user creates tx
        thirdDevice.activate()
        let model3 = CloudKitSyncTestHelpers.makeTransactionModel(
            title: "Third TX",
            amount: 3000
        )
        try! thirdDevice.transactionRepo.insertTransaction(model3)
        TransactionRepository.invalidateCache()
        let thirdTxs = thirdDevice.transactionRepo.fetchAllTransactions()
        if let tx = thirdTxs.first(where: { $0.title == "Third TX" }), let txId = tx.id {
            thirdDevice.transactionRepo.updateSharedGroupId(transactionId: txId, groupId: groupId)
        }
        thirdDevice.pushTransactions()

        // All pull
        ownerDevice.activate()
        ownerDevice.pullTransactions()

        memberDevice.activate()
        memberDevice.pullTransactions()

        thirdDevice.activate()
        thirdDevice.pullTransactions()

        // Each should have all 3 group transactions
        ownerDevice.activate()
        let ownerGroupTxs = ownerDevice.transactionRepo.fetchTransactionsForGroup(groupId: groupId)

        memberDevice.activate()
        let memberGroupTxs = memberDevice.transactionRepo.fetchTransactionsForGroup(groupId: groupId)

        thirdDevice.activate()
        let thirdGroupTxs = thirdDevice.transactionRepo.fetchTransactionsForGroup(groupId: groupId)

        XCTAssertEqual(ownerGroupTxs.count, 3, "Owner should have 3 group transactions")
        XCTAssertEqual(memberGroupTxs.count, 3, "Member should have 3 group transactions")
        XCTAssertEqual(thirdGroupTxs.count, 3, "Third user should have 3 group transactions")

        let ownerTitles = Set(ownerGroupTxs.map { $0.title })
        XCTAssertTrue(ownerTitles.contains("Owner TX"))
        XCTAssertTrue(ownerTitles.contains("Member TX"))
        XCTAssertTrue(ownerTitles.contains("Third TX"))

        thirdDevice.cleanup()
    }
}
