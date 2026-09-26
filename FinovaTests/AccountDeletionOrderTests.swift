//
//  AccountDeletionOrderTests.swift
//  FinovaTests
//
//  Deleting the account cleared this device's data BEFORE asking Firebase to delete the account. When
//  Firebase refused (it often wants a recent sign-in, or there is no network), the account stayed and
//  its data was already gone.
//

import FirebaseAuth
import Foundation
import XCTest

@testable import Finova

final class AccountDeletionOrderTests: XCTestCase {
    private final class Spy: SettingsViewModelDelegate {
        var onFailure: (() -> Void)?
        var onReAuthentication: (() -> Void)?

        func didRequestReAuthentication() { onReAuthentication?() }
        func didFailAccountDeletion(title: String, message: String) { onFailure?() }
        func didUpdateBiometricUI(isEnabled: Bool, biometricType: String) {}
        func didRequestOpenSettings(title: String, message: String) {}
        func didUpdateAppVersion(version: String) {}
        func didUpdateCurrency(displayText: String) {}
        func didUpdateTagTranslation(isEnabled: Bool, isSupported: Bool) {}
        func didEncounterBiometricError(title: String, message: String) {}
        func didCompleteAccountDeletion() {}
        func shouldShowLoading(_ show: Bool, message: String?) {}
        func didUpdateTransparency(isEnabled: Bool, groupName: String?) {}
        func didRequestGroupSelection(groups: [BudgetGroup]) {}
    }

    private var transactionRepo: TransactionRepository!

    override func setUp() {
        super.setUp()
        UIDUserDefaultsManager.shared.currentUserUID = "test_account_deletion_\(UUID().uuidString)"
        transactionRepo = TransactionRepository()
        transactionRepo.clearAllTransactionsForTesting()
        _ = try? transactionRepo.insertTransactionAndGetId(
            CloudKitSyncTestHelpers.makeTransactionModel(title: "Groceries", amount: 5000))
    }

    override func tearDown() {
        transactionRepo.clearAllTransactionsForTesting()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    private func storedTransactions() -> [Transaction] {
        TransactionRepository.invalidateCache()
        return transactionRepo.fetchAllTransactions()
    }

    private func deleteAccount(failingWith code: Int) {
        let viewModel = SettingsViewModel()
        let spy = Spy()
        viewModel.delegate = spy
        viewModel.deleteAuthAccount = { completion in
            completion(NSError(domain: "FIRAuthErrorDomain", code: code))
        }
        let answered = expectation(description: "the refusal is reported")
        spy.onFailure = { answered.fulfill() }
        spy.onReAuthentication = { answered.fulfill() }

        viewModel.deleteAccount()
        wait(for: [answered], timeout: 5)
    }

    func testARefusedDeleteKeepsTheLocalData() {
        XCTAssertFalse(
            storedTransactions().isEmpty, "Precondition: there is data")

        deleteAccount(failingWith: AuthErrorCode.networkError.rawValue)

        XCTAssertFalse(
            storedTransactions().isEmpty,
            "The account still exists, so its data must too")
    }

    func testAskingToSignInAgainKeepsTheLocalData() {
        deleteAccount(failingWith: AuthErrorCode.requiresRecentLogin.rawValue)

        XCTAssertFalse(
            storedTransactions().isEmpty,
            "The user may cancel the sign-in prompt; nothing was deleted yet")
    }
}
