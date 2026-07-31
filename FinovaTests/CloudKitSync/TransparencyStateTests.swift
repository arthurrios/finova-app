//
//  TransparencyStateTests.swift
//  FinovaTests
//
//  Transparent Mode's state rides on `GroupMember.permissions`, an already-deployed CloudKit STRING
//  field. Two properties make that safe, and both are easy to break by accident:
//
//  1. Old JSON that predates the key must decode to NOT publishing. Every other permission added to
//     this blob defaults to `true` for backward compatibility; copying that here would silently
//     publish an existing user's personal ledger to their group on upgrade.
//  2. The key must survive a JSON round-trip — it is stored as text and re-parsed on every read, so
//     an omission from `CodingKeys` would lose the flag with no error anywhere.
//

import XCTest

@testable import Finova

final class TransparencyStateTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var repo: BudgetGroupRepository!
    private var manager: TransparencyManager!
    private var userUID: String!
    private let groupId = "grp-transparency"

    override func setUp() {
        super.setUp()
        userUID = "transparency_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaTransp-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        repo = BudgetGroupRepository(db: db)
        manager = TransparencyManager(db: db)

        repo.insertGroup(
            BudgetGroup(
                id: groupId, name: "Family", ownerId: userUID,
                ownerName: "Me", ownerEmail: "me@example.com"
            )
        )
        repo.insertMember(
            GroupMember(
                groupId: groupId, userId: userUID, name: "Me",
                email: "me@example.com", role: .owner, permissions: .fullAccess
            )
        )
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        UserDefaults.standard.removeObject(forKey: "groupMemberPushed_\(groupId)")
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Encoding

    /// The flag is stored as JSON text and re-parsed on every read. Leaving it out of `CodingKeys`
    /// would drop it silently on the first round-trip.
    func testFlagSurvivesJSONRoundTrip() {
        var permissions = GroupPermissions.memberDefault
        permissions.publishesPersonalLedger = true

        let restored = GroupPermissions.fromJSON(permissions.asJSON)
        XCTAssertTrue(
            restored.publishesPersonalLedger,
            "publishesPersonalLedger must be encoded and decoded — it is persisted only as JSON text"
        )
    }

    /// Permissions written before Transparent Mode existed have no such key. They must decode to
    /// NOT publishing: the opposite default would expose an existing user's personal ledger on
    /// upgrade, without them asking for it.
    func testLegacyJSONDefaultsToNotPublishing() {
        let legacy = """
            {"canCreateTransactions":true,"canEditTransactions":true,"canDeleteTransactions":true,\
            "canEditBudgets":true,"canEditAllocations":true,"canViewCreditCards":true,\
            "canManageCreditCards":true,"canInviteMembers":true}
            """
        let decoded = GroupPermissions.fromJSON(legacy)

        XCTAssertFalse(
            decoded.publishesPersonalLedger,
            "Permissions predating Transparent Mode must default to NOT publishing"
        )
        XCTAssertTrue(
            decoded.canEditOwnTransactions,
            "The other backward-compatible defaults must be unaffected"
        )
    }

    /// No role preset may publish. Publishing is the member's own decision, so it can never arrive
    /// as a side effect of the owner assigning a role.
    func testNoRolePresetPublishes() {
        for (name, preset) in [
            ("memberDefault", GroupPermissions.memberDefault),
            ("viewOnly", GroupPermissions.viewOnly),
            ("canAdd", GroupPermissions.canAdd),
            ("fullAccess", GroupPermissions.fullAccess),
        ] {
            XCTAssertFalse(
                preset.publishesPersonalLedger,
                "\(name) must not publish — transparency is opted into, never granted by a role"
            )
        }
    }

    /// The owner's permission editor must not offer it, or the owner could publish a member's
    /// personal finances on their behalf.
    func testFlagIsNotOwnerEditable() {
        XCTAssertFalse(
            GroupPermissions.memberDefault.allPermissions
                .contains { $0.key == "publishesPersonalLedger" },
            "publishesPersonalLedger must not appear in the owner-facing permission list"
        )

        var permissions = GroupPermissions.memberDefault
        permissions.setPermission(key: "publishesPersonalLedger", value: true)
        XCTAssertFalse(
            permissions.publishesPersonalLedger,
            "setPermission drives the owner's editor and must not be able to reach this flag"
        )
    }

    // MARK: - Manager

    func testDefaultsToNotPublishing() {
        XCTAssertFalse(manager.isPublishing(toGroup: groupId))
        XCTAssertTrue(manager.publishedGroupIds().isEmpty)
    }

    func testEnablingPersistsAndIsListed() {
        XCTAssertTrue(manager.setPublishing(true, forGroup: groupId))

        XCTAssertTrue(
            manager.isPublishing(toGroup: groupId),
            "The flag must survive being written to and re-read from the member row"
        )
        XCTAssertEqual(manager.publishedGroupIds(), [groupId])
    }

    func testDisablingPersists() {
        manager.setPublishing(true, forGroup: groupId)
        manager.setPublishing(false, forGroup: groupId)

        XCTAssertFalse(manager.isPublishing(toGroup: groupId))
        XCTAssertTrue(manager.publishedGroupIds().isEmpty)
    }

    /// SyncEngine skips the GroupMember save when `groupMemberPushed_<id>` is set, so a toggle that
    /// leaves the flag in place never leaves the device.
    func testTogglingClearsThePushFlagSoTheChangeCanSync() {
        UserDefaults.standard.set(true, forKey: "groupMemberPushed_\(groupId)")

        manager.setPublishing(true, forGroup: groupId)

        XCTAssertNil(
            UserDefaults.standard.object(forKey: "groupMemberPushed_\(groupId)"),
            "Toggling transparency must clear the push flag or the member record is never re-pushed"
        )
    }

    /// Transparency is a decision recorded about the ledger, not an edit to it. Nothing in the
    /// financial tables may move — this is the entire difference from Mirror Mode.
    func testTogglingTouchesNoFinancialRow() {
        try? db.insertBudget(monthDate: 1_700_000_000, amount: 500_000)
        try? TransactionRepository(db: db).insertTransaction(
            CloudKitSyncTestHelpers.makeTransactionModel(title: "Groceries", amount: 4200)
        )

        let before = financialScopeFingerprint()
        manager.setPublishing(true, forGroup: groupId)
        let afterEnable = financialScopeFingerprint()
        manager.setPublishing(false, forGroup: groupId)
        let afterDisable = financialScopeFingerprint()

        XCTAssertEqual(
            before, afterEnable,
            "Enabling transparency must not re-tag or re-zone a single personal row — Mirror Mode "
                + "did exactly that, which is what stopped those rows being personal"
        )
        XCTAssertEqual(before, afterDisable, "Disabling must be equally inert")
    }

    /// Every scope tag and sync state across the financial tables, as one comparable string.
    private func financialScopeFingerprint() -> String {
        let parts = ["Transactions", "Budgets", "CreditCards", "BudgetAllocations"].map { table in
            db.fetchSingleString(
                "SELECT COALESCE(group_concat("
                    + "COALESCE(shared_group_id,'~') || '/' || COALESCE(sync_status,'~')"
                    + "), '') FROM \(table);"
            ) ?? "?"
        }
        return parts.joined(separator: "|")
    }
}
