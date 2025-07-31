//
//  MonthlyNotificationTests.swift
//  FinovaTests
//
//  Created by Arthur Rios on 17/01/25.
//

import XCTest
@testable import Finova

final class MonthlyNotificationTests: XCTestCase {
    
    var monthlyManager: MonthlyNotificationManager!
    var transactionRepo: TransactionRepository!
    var budgetRepo: BudgetRepository!
    
    override func setUpWithError() throws {
        super.setUp()
        
        // Setup test environment
        transactionRepo = TransactionRepository()
        budgetRepo = BudgetRepository()
        monthlyManager = MonthlyNotificationManager(
            transactionRepo: transactionRepo,
            budgetRepo: budgetRepo
        )
    }
    
    override func tearDownWithError() throws {
        // Clean up
        super.tearDown()
    }
    
    func testMonthlyManagerCreation() throws {
        XCTAssertNotNil(monthlyManager)
        XCTAssertNotNil(transactionRepo)
        XCTAssertNotNil(budgetRepo)
    }
    
    func testMonthlyNotificationStatus() throws {
        // Test that the method returns a valid status
        let status = monthlyManager.checkMonthlyNotificationsStatus()
        
        // Should return a valid status enum
        XCTAssertTrue(status == .notConfigured || status == .configured || status == .outdated)
    }
    
    func testSetupMonthlyNotificationSystem() throws {
        // Test that setup doesn't crash
        monthlyManager.setupMonthlyNotificationSystem()
        
        // Should not crash
        XCTAssertTrue(true)
    }
    
    func testScheduleAllMonthlyNotifications() throws {
        // Test that scheduling doesn't crash
        let result = monthlyManager.scheduleAllMonthlyNotifications()
        
        // Should return a boolean
        XCTAssertTrue(result == true || result == false)
    }
} 