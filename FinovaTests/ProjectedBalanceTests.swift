//
//  ProjectedBalanceTests.swift
//  FinovaTests
//
//  The projected balance of the current month and the months ahead, through a real database, real
//  statement rows and the real forecast:
//  `projected(M) = base(M) - outstandingCard(M) - plan(current..M)`.
//
//  Every read also asserts the budget history and the dashboard's card agree on every month ahead.
//

import XCTest

@testable import Finova

final class ProjectedBalanceTests: XCTestCase {
    private var db: DBHelper!
    private var dbPath: URL!
    private var userUID: String!
    private var txRepo: TransactionRepository!
    private var allocationRepo: BudgetAllocationRepository!
    private var budgetRepo: BudgetRepository!
    private var statementRepo: StatementRepository!
    private var cardService: CreditCardService!
    private var allocationService: BudgetAllocationService!
    private var card: CreditCard!
    private let groupId = "grp-projected"

    private let reference = Date()
    private func month(_ offset: Int) -> Int { reference.monthAnchor(offsetByMonths: offset) }
    private var opening = 10_000

    override func setUp() {
        super.setUp()
        userUID = "projected_\(UUID().uuidString)"
        UIDUserDefaultsManager.shared.currentUserUID = userUID
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinovaProjected-\(UUID().uuidString).sqlite")
        db = DBHelper(path: dbPath)
        TransactionRepository.invalidateCache()

        txRepo = TransactionRepository(db: db)
        allocationRepo = BudgetAllocationRepository(db: db)
        budgetRepo = BudgetRepository(db: db)
        statementRepo = StatementRepository(db: db)
        let cardRepo = CreditCardRepository(db: db)
        cardService = CreditCardService(cardRepo: cardRepo, stmtRepo: statementRepo, transactionRepo: txRepo)
        allocationService = BudgetAllocationService(
            allocationRepo: allocationRepo, transactionRepo: txRepo, budgetRepo: budgetRepo,
            statementRepo: statementRepo)

        var visa = CreditCard(
            name: "Visa", lastFourDigits: "4242", cardBrand: .visa, closingDay: 28, dueDay: 8,
            creditLimit: 900_000, cardColor: .blue, userId: userUID, isDeleted: false, isDefault: false,
            createdAt: Date(), updatedAt: Date())
        visa.id = cardRepo.insertCard(visa)
        card = visa
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
        }
        TransactionRepository.invalidateCache()
        UIDUserDefaultsManager.shared.signOut()
        super.tearDown()
    }

    // MARK: - Fixture

    private func date(_ day: Int, of month: Int) -> Date {
        Date.fromMonthAnchor(month).addingTimeInterval(TimeInterval(day - 1) * 86_400)
    }

    /// A statement closing the 28th of the month at `closingOffset`, due the 8th of the month after.
    private func statement(closing closingOffset: Int) throws -> CreditCardStatement {
        let id = try db.insertStatement(
            creditCardId: try XCTUnwrap(card.id),
            closingDate: Int(date(28, of: month(closingOffset)).timeIntervalSince1970),
            dueDate: Int(date(8, of: month(closingOffset + 1)).timeIntervalSince1970),
            totalAmount: 0, userId: userUID)
        return try XCTUnwrap(statementRepo.fetchStatements(forCardId: try XCTUnwrap(card.id)).first { $0.id == id })
    }

    @discardableResult
    private func add(
        _ amount: Int, _ category: TransactionCategory = .market, month anchor: Int, type: String = "expense",
        on statement: CreditCardStatement? = nil, title: String = UUID().uuidString, group: String? = nil
    ) throws -> Int {
        try txRepo.insertTransaction(
            TransactionTestFixtures.makeTransactionModel(
                title: title, category: category.key, amount: amount, type: type,
                dateTimestamp: Int(date(10, of: anchor).timeIntervalSince1970),
                budgetMonthDate: anchor,
                creditCardId: statement == nil ? nil : card.id, statementId: statement?.id,
                // The statement SQL reads `= 0`, and the column stays NULL without this.
                isCreditCardStatement: statement == nil ? nil : false))
        let id = try XCTUnwrap(db.fetchSingleInt("SELECT id FROM Transactions WHERE title = ?;", textBinding: title))
        if let group {
            try db.executeGroupWriteChecked(
                "UPDATE Transactions SET shared_group_id = ?, user_id = ? WHERE id = ?;",
                orderedBindings: [group, userUID, id])
        }
        TransactionRepository.invalidateCache()
        return id
    }

    private func allocate(_ amount: Int, _ category: TransactionCategory = .market, offsets: ClosedRange<Int> = 0...7) throws {
        for offset in offsets {
            _ = try allocationRepo.insertAllocation(
                BudgetAllocationModel(
                    monthDate: month(offset), categoryKey: category.key, allocatedAmount: amount,
                    isRecurring: false))
        }
    }

    /// An opening balance, so the figures below read as what is left of it.
    private func addOpening() throws {
        try add(opening, .salary, month: month(0), type: "income")
    }

    private func pay(_ statement: CreditCardStatement, _ amount: Int, on paymentDate: Date) throws {
        try StatementPaymentService(
            transactionRepo: txRepo, statementRepo: statementRepo, creditCardService: cardService, db: db
        ).pay(statement: statement, card: try XCTUnwrap(card), amount: amount, paymentDate: paymentDate)
        TransactionRepository.invalidateCache()
    }

    private func ledger() -> TransactionLedgerService {
        TransactionLedgerService(
            transactionRepo: txRepo, budgetRepo: budgetRepo, creditCardService: cardService,
            statementUserId: { [userUID] in userUID })
    }

    /// One whole read: the card's projection for each open month, built as the dashboard builds it.
    private func read(through last: Int = 3) throws -> [AllocationBalanceProjection] {
        let ledger = ledger()
        let cards = ledger.calculateMonthlyData(for: -2...7, referenceDate: reference)
        let commitments = allocationService.balanceCommitments(
            monthsAhead: SeriesMonths.carouselRange.upperBound,
            statementsDue: ledger.statementsDueByMonth(), in: .personal, asOf: reference)
        let forecast = BudgetHistoryService(
            allocationRepo: allocationRepo, transactionRepo: txRepo, budgetRepo: budgetRepo,
            statementRepo: statementRepo, ledger: self.ledger()
        ).forecast(in: .personal, asOf: reference)

        return try (0...last).map { offset in
            let anchor = month(offset)
            let commitment = try XCTUnwrap(commitments[anchor])
            let budgetCard = BudgetCard()
            budgetCard.configure(
                month: "M", year: "Y",
                allocations: allocationService.getAllocationsWithUsage(forMonth: anchor, in: .personal),
                unallocatedSummary: allocationService.getUnallocatedSummary(forMonth: anchor, in: .personal),
                unallocatedSpending: allocationService.getUnallocatedCategoriesWithSpending(
                    forMonth: anchor, in: .personal),
                monthAnchor: anchor,
                monthData: cards.first { $0.date.monthAnchor == anchor },
                deferredCardSpending: commitment.outstandingCard,
                reservedPlan: commitment.reservedPlan)
            let dashboard = try XCTUnwrap(budgetCard.projection)
            if offset > 0 {
                XCTAssertEqual(forecast.month(anchor)?.projection, dashboard, "month +\(offset)")
            }
            return dashboard
        }
    }

    private func projected(through last: Int = 3) throws -> [Int] { try read(through: last).map(\.projected) }

    // MARK: - The plan

    func testEachMonthCarriesThePlansBeforeIt() throws {
        for offset in 0...7 { try add(8_000, .salary, month: month(offset), type: "income") }
        try allocate(1_000)

        XCTAssertEqual(try projected(through: 2), [7_000, 14_000, 21_000])
    }

    func testAPartlySpentCurrentMonthAddsOnlyWhatIsLeft() throws {
        try addOpening()
        try allocate(1_000)
        try add(400, month: month(0))

        // 9.600 - 600 left of this month, then 1.000 more for next month.
        let read = try read(through: 1)
        XCTAssertEqual(read[0].projected, 9_000)
        XCTAssertEqual(read[0].reservedPlan, 600)
        XCTAssertEqual(read[1].projected, 8_000)
    }

    func testPastPlansAddNothing() throws {
        try addOpening()
        try allocate(5_000, offsets: 0...0)
        _ = try allocationRepo.insertAllocation(
            BudgetAllocationModel(
                monthDate: month(-1), categoryKey: TransactionCategory.market.key, allocatedAmount: 7_000,
                isRecurring: false))

        XCTAssertEqual(try read(through: 0)[0].reservedPlan, 5_000)
    }

    func testHeadroomIsNotReserved() throws {
        try addOpening()
        try allocate(1_000, offsets: 0...0)
        try budgetRepo.insert(budget: BudgetModel(monthDate: month(0), amount: 6_000))

        XCTAssertEqual(try projected(through: 1), [9_000, 9_000])
    }

    // MARK: - A card purchase counts once

    /// 10.000 in, 300 spent on a 1.000 plan: 9.000 is what survives, however the 300 is settled.
    private func assertCountedOnce(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try projected(through: 2), [9_000, 9_000, 9_000], file: file, line: line)
    }

    func testACardPurchaseCountsOnceInItsMonthAndAcrossItsSettling() throws {
        try addOpening()
        try allocate(1_000, offsets: 0...0)
        try add(300, month: month(0), on: try statement(closing: 0))

        try assertCountedOnce()
        let read = try read(through: 1)
        XCTAssertEqual(read[0].deferredCardSpending, 300)
        XCTAssertEqual(read[1].deferredCardSpending, 0)
        XCTAssertEqual(read[1].base, 9_700)
    }

    func testAStatementPaidBeforeItsDueDateCountsOnce() throws {
        try addOpening()
        try allocate(1_000, offsets: 0...0)
        let bill = try statement(closing: 0)
        try add(300, month: month(0), on: bill)
        try pay(bill, 300, on: date(15, of: month(0)))

        try assertCountedOnce()
    }

    func testAStatementPaidBeforeItClosesCountsOnce() throws {
        // The credit's budget month is the closing month, next month. The debit is already in this one.
        try addOpening()
        try allocate(1_000, offsets: 0...0)
        let bill = try statement(closing: 1)
        try add(300, month: month(0), on: bill)
        try pay(bill, 300, on: date(15, of: month(0)))

        try assertCountedOnce()
    }

    func testAPaymentScheduledForTheDueDateDropsNothing() throws {
        // The credit's budget month is this month, but the debit reaches the balance next month.
        try addOpening()
        try allocate(1_000, offsets: 0...0)
        let bill = try statement(closing: 0)
        try add(300, month: month(0), on: bill)
        try pay(bill, 300, on: date(8, of: month(1)))

        try assertCountedOnce()
    }

    func testAPartlyPaidStatementCountsOnce() throws {
        try addOpening()
        try allocate(1_000, offsets: 0...0)
        let bill = try statement(closing: 0)
        try add(300, month: month(0), on: bill)
        try pay(bill, 100, on: date(15, of: month(0)))

        try assertCountedOnce()
    }

    func testAPurchaseSettlingLaterStaysOutstandingUntilThen() throws {
        try addOpening()
        try allocate(1_000, offsets: 0...0)
        try add(300, month: month(0), on: try statement(closing: 1))

        let read = try read(through: 3)
        XCTAssertEqual(read[1].deferredCardSpending, 300, "bought in month 1, settles in month 3")
        XCTAssertEqual(read[2].deferredCardSpending, 0)
        XCTAssertEqual(read.map(\.projected), [9_000, 9_000, 9_000, 9_000])
    }

    func testAStoredRowCountsFromItsOwnBudgetMonth() throws {
        try addOpening()
        try add(300, month: month(1), on: try statement(closing: 2))

        XCTAssertEqual(try read().map(\.deferredCardSpending), [0, 300, 300, 0])
    }

    func testARowWithNoLiveStatementStaysOutstanding() throws {
        try addOpening()
        try txRepo.insertTransaction(
            TransactionTestFixtures.makeTransactionModel(
                title: "orphan", category: "market", amount: 300,
                dateTimestamp: Int(date(10, of: month(0)).timeIntervalSince1970),
                budgetMonthDate: month(0), creditCardId: card.id))
        TransactionRepository.invalidateCache()

        XCTAssertEqual(try projected(through: 2), [9_700, 9_700, 9_700])
    }

    func testARefundNetsLikeTheStatementDoes() throws {
        try addOpening()
        let bill = try statement(closing: 0)
        try add(300, month: month(0), on: bill)
        try add(100, month: month(0), type: "income", on: bill)

        let read = try read(through: 2)
        XCTAssertEqual(read[0].deferredCardSpending, 200)
        XCTAssertEqual(read.map(\.projected), [9_800, 9_800, 9_800])
    }

    // MARK: - The Credit Card category

    func testACreditCardAllocationDoesNotDoubleTheBill() throws {
        try addOpening()
        try allocate(1_000, .creditCard, offsets: 1...1)
        try add(800, .meals, month: month(0), on: try statement(closing: 0))

        // Next month 800 of the 1.000 is the bill itself, so only 200 is still to leave.
        let read = try read(through: 1)
        XCTAssertEqual(read[1].reservedPlan, 200)
        XCTAssertEqual(read[1].projected, 9_000)
    }

    func testAPaidBillStillDrawsDownItsCreditCardAllocation() throws {
        try addOpening()
        try allocate(1_000, .creditCard, offsets: 1...1)
        let bill = try statement(closing: 0)
        try add(800, .meals, month: month(0), on: bill)
        try pay(bill, 800, on: date(5, of: month(1)))

        XCTAssertEqual(try read(through: 1)[1].projected, 9_000)
    }

    // MARK: - Paying a statement

    /// The purchases are the spending. The payment only moves the money that pays for them, so it
    /// leaves the balance and never counts against the budget.
    func testAStatementPaymentIsNotBudgetSpending() throws {
        try addOpening()
        let bill = try statement(closing: 0)
        try add(300, .meals, month: month(0), on: bill)
        try pay(bill, 300, on: date(15, of: month(0)))

        let used = ledger().calculateMonthlyData(for: 0...0, referenceDate: reference).first?.usedValue
        XCTAssertEqual(used, 300, "the month card's Used")
        let outside = allocationService.getUnallocatedCategoriesWithSpending(forMonth: month(0), in: .personal)
        XCTAssertEqual(outside.map(\.category), [.meals], "spending outside allocations")
        let history = BudgetHistoryService(
            allocationRepo: allocationRepo, transactionRepo: txRepo, budgetRepo: budgetRepo,
            statementRepo: statementRepo, ledger: ledger())
        XCTAssertFalse(history.expenses(in: .personal).contains { $0.category == .creditCard })
        XCTAssertEqual(try read(through: 0)[0].base, 9_700, "the balance still loses the money")
    }

    func testAStatementPaymentDoesNotSpendACreditCardAllocation() throws {
        try addOpening()
        try allocate(1_000, .creditCard, offsets: 0...0)
        let bill = try statement(closing: 0)
        try add(300, .meals, month: month(0), on: bill)
        try pay(bill, 300, on: date(15, of: month(0)))

        let allocation = allocationService.getAllocationsWithUsage(forMonth: month(0), in: .personal)
            .first { $0.category == .creditCard }
        XCTAssertEqual(allocation?.usedAmount, 0)
        XCTAssertEqual(
            allocationService.getTransactions(forCategory: .creditCard, monthAnchor: month(0)).count, 0)
    }

    // MARK: - Closed months

    func testAClosedMonthKeepsItsOwnFigures() {
        var allocation = BudgetAllocation(
            dbId: nil, monthDate: month(-1), category: .market, allocatedAmount: 1_000, isRecurring: false,
            parentAllocationId: nil, sharedGroupId: nil)
        allocation.setUsedAmount(0)
        let card = BudgetCard()
        card.configure(
            month: "M", year: "Y", allocations: [allocation],
            unallocatedSummary: UnallocatedBudgetSummary(
                monthDate: month(-1), totalBudget: 2_000, totalAllocated: 1_000,
                totalUsedInUnallocatedCategories: 0),
            unallocatedSpending: [], monthAnchor: month(-1),
            monthData: MonthBudgetCardType(
                date: Date.fromMonthAnchor(month(-1)), month: "M", usedValue: 0, budgetLimit: 2_000,
                finalBalance: 10_000, currentBalance: 10_000, previousBalance: 10_000))

        XCTAssertEqual(card.projection?.tense, .actual)
        XCTAssertEqual(card.projection?.reservedPlan, 1_000)
        XCTAssertEqual(card.projection?.projected, 9_000)
        XCTAssertEqual(card.projection?.totalSaved, 2_000)
    }

    func testClosedMonthsHaveNoCommitments() {
        let commitments = allocationService.balanceCommitments(
            monthsAhead: 2, statementsDue: [:], in: .personal, asOf: reference)
        XCTAssertNil(commitments[month(-1)])
        XCTAssertNotNil(commitments[month(0)])
        XCTAssertNotNil(commitments[month(2)])
        XCTAssertNil(commitments[month(3)])
    }

    // MARK: - Scope

    func testAGroupReadsItsOwnCardDebt() throws {
        let bill = try statement(closing: 0)
        try add(300, month: month(0), on: bill)
        try add(500, month: month(0), on: bill, group: groupId)

        func outstanding(_ scope: LedgerScope) -> Int? {
            allocationService.balanceCommitments(
                monthsAhead: 1, statementsDue: [:], in: scope, asOf: reference)[month(0)]?.outstandingCard
        }
        XCTAssertEqual(outstanding(.personal), 300)
        XCTAssertEqual(outstanding(LedgerScope(groupId: groupId, localUid: userUID)), 500)
    }

    // MARK: - The dashboard's cache

    func testTheDashboardLoadsTheFiguresOnceUntilSomethingChanges() {
        var loads = 0
        let cache = BalanceCommitmentsCache { _, _ in
            loads += 1
            return .none
        }

        for _ in 0..<5 { _ = cache.commitments(in: .personal, asOf: reference) }
        XCTAssertEqual(loads, 1)

        NotificationCenter.default.post(name: .allocationDataChanged, object: nil)
        _ = cache.commitments(in: .personal, asOf: reference)
        XCTAssertEqual(loads, 2)

        NotificationCenter.default.post(name: .transactionDataChanged, object: nil)
        _ = cache.commitments(in: .personal, asOf: reference)
        XCTAssertEqual(loads, 3)

        _ = cache.commitments(in: LedgerScope(groupId: groupId, localUid: userUID), asOf: reference)
        XCTAssertEqual(loads, 4, "another ledger is never served this one's table")
    }
}
