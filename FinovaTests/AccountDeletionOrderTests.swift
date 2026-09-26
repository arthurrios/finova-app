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
        func didCompleteDataRecovery(success: Bool, message: String) {}
    }

    private var transactionRepo: TransactionRepository!

    override func setUp() {
        super.setUp()
        // Secure storage is the source of truth on this release.
        SecureLocalDataManager.shared.authenticateUser(
            firebaseUID: "test_account_deletion_\(UUID().uuidString)")
        transactionRepo = TransactionRepository()
        transactionRepo.clearAllTransactionsForTesting()
        _ = try? transactionRepo.insertTransactionAndGetId(
            TransactionModel(
                title: "Groceries", category: "market", amount: 5000, type: "expense",
                dateTimestamp: Int(Date().timeIntervalSince1970), budgetMonthDate: Date().monthAnchor))
    }

    override func tearDown() {
        transactionRepo.clearAllTransactionsForTesting()
        SecureLocalDataManager.shared.signOut()
        super.tearDown()
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
            SecureLocalDataManager.shared.loadTransactions().isEmpty, "Precondition: there is data")

        deleteAccount(failingWith: AuthErrorCode.networkError.rawValue)

        XCTAssertFalse(
            SecureLocalDataManager.shared.loadTransactions().isEmpty,
            "The account still exists, so its data must too")
    }

    func testAskingToSignInAgainKeepsTheLocalData() {
        deleteAccount(failingWith: AuthErrorCode.requiresRecentLogin.rawValue)

        XCTAssertFalse(
            SecureLocalDataManager.shared.loadTransactions().isEmpty,
            "The user may cancel the sign-in prompt; nothing was deleted yet")
    }
}
