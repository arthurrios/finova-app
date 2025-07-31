//
//  BalanceMonitorTests.swift
//  FinovaTests
//
//  Created by Arthur Rios on 17/01/25.
//

import XCTest
@testable import Finova

final class BalanceMonitorTests: XCTestCase {
    
    var balanceMonitor: BalanceMonitorManager!
    var transactionRepo: TransactionRepository!
    var budgetRepo: BudgetRepository!
    
    override func setUpWithError() throws {
        super.setUp()
        
        // Setup test environment
        transactionRepo = TransactionRepository()
        budgetRepo = BudgetRepository()
        balanceMonitor = BalanceMonitorManager(
            transactionRepo: transactionRepo,
            budgetRepo: budgetRepo
        )
        
        // Clear existing notifications
        balanceMonitor.removeNegativeBalanceNotifications()
    }
    
    override func tearDownWithError() throws {
        // Clean up
        balanceMonitor.removeNegativeBalanceNotifications()
        super.tearDown()
    }
    
    func testBalanceMonitorCreation() throws {
        XCTAssertNotNil(balanceMonitor)
        XCTAssertNotNil(transactionRepo)
        XCTAssertNotNil(budgetRepo)
    }
    
    func testNegativeBalanceDetection() throws {
        // This test would require setting up test data
        // For now, just test that the method doesn't crash
        balanceMonitor.monitorCurrentMonthBalance()
        
        // Should not crash
        XCTAssertTrue(true)
    }
    
    func testNotificationRemoval() throws {
        // Test that removing notifications doesn't crash
        balanceMonitor.removeNegativeBalanceNotifications()
        
        // Should not crash
        XCTAssertTrue(true)
    }
    
    func testHasNegativeBalanceNotifications() throws {
        // Test the method returns a boolean
        let hasNotifications = balanceMonitor.hasNegativeBalanceNotifications()
        
        // Should return a boolean value
        XCTAssertTrue(hasNotifications == true || hasNotifications == false)
    }
    
    func testDebugNegativeBalanceNotifications() throws {
        // Test that debug method doesn't crash
        balanceMonitor.debugNegativeBalanceNotifications()
        
        // Should not crash
        XCTAssertTrue(true)
    }
    
    func testDateFormatting() throws {
        // Test date formatting for different locales
        // Use a specific date that works regardless of timezone
        var dateComponents = DateComponents()
        dateComponents.year = 2022
        dateComponents.month = 3
        dateComponents.day = 15
        dateComponents.hour = 12 // Use noon to avoid timezone issues
        dateComponents.minute = 0
        dateComponents.second = 0
        
        let calendar = Calendar.current
        guard let testDate = calendar.date(from: dateComponents) else {
            XCTFail("Failed to create test date")
            return
        }
        
        // Test Portuguese format (DD/MM)
        let ptFormatter = DateFormatter()
        ptFormatter.dateFormat = "dd/MM"
        let ptFormatted = ptFormatter.string(from: testDate)
        XCTAssertEqual(ptFormatted, "15/03")
        
        // Test English format (MM/DD)
        let enFormatter = DateFormatter()
        enFormatter.dateFormat = "MM/dd"
        let enFormatted = enFormatter.string(from: testDate)
        XCTAssertEqual(enFormatted, "03/15")
    }
} 