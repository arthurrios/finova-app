# Credit Card Feature - Step-by-Step Development Guide

## Spec Alignment Review

The `CREDIT_CARD_FEATURE_SPEC.md` is **well-aligned** with the current codebase, with a few notes:

| Spec Element | Current State | Alignment |
|---|---|---|
| Dashboard transaction list with statement entries | Existing `DashboardViewController` shows grouped transactions by month/date | Aligned - statements will appear as special transaction rows |
| Settings > Credit Cards entry point | Current `SettingsView` has: Security, Preferences, Notifications, About, Account | **Needs new "Financial" section** inserted between Preferences and Notifications |
| Add Transaction > Payment Method | Current `AddTransactionModalView` has: Title, Category, Mode, Amount, Date, Type | **Needs Payment Method section** added before the transaction type buttons |
| Transaction model extensions | Current `Transaction` model has no credit card fields | **Needs 3 new fields**: `creditCardId`, `statementId`, `isCreditCardStatement` |
| Programmatic UIKit architecture | 100% programmatic UIKit with MVVM + Flow Controllers | Aligned - all new screens follow this pattern |
| SwiftUI card component | App is UIKit-only currently | **Hybrid approach** - SwiftUI `CreditCardView` hosted in UIKit via `UIHostingController` |
| SQLite database | Uses `TransactionRepository` with SQLite | Aligned - new tables + ALTER for existing |
| Factory pattern | `ViewControllersFactory` creates all VCs | Aligned - new factory methods needed |
| Navigation via FlowDelegates | `AppFlowController` implements all delegates | Aligned - new delegate protocols needed |

---

## Development Phases

### Phase 0: Developer Shortcut (DEBUG Auto-Login)
> Skip login during development. Already implemented in `SplashViewController`.

Build and run. You should land directly on the Dashboard without any login screen.

---

### Phase 1: Data Layer Foundation
> Goal: Build the models, database tables, and repositories. **No UI yet** - just the data backbone.

#### Step 1.1: Create `CreditCard` Model
**File:** `Finova/Sources/Core/Models/CreditCard.swift` (NEW)

```swift
struct CreditCard: Codable {
    var id: Int?
    var name: String                    // "Nubank Ultravioleta"
    var lastFourDigits: String          // "1234"
    var cardBrand: CardBrand            // .visa, .mastercard, etc.
    var closingDay: Int                 // 1-28
    var dueDay: Int                     // 1-28
    var creditLimit: Int?               // In cents, optional
    var cardColor: CardColor            // Visual customization
    var userId: String
    var createdAt: Date
    var updatedAt: Date
}

enum CardBrand: String, Codable, CaseIterable {
    case visa, mastercard, amex, elo, hipercard, other

    var displayName: String { ... }
    var iconName: String { ... }        // Follow existing pattern: "cc_visa", etc.
}

enum CardColor: String, Codable, CaseIterable {
    case black, purple, blue, green, gold, platinum, red, orange

    var gradientColors: (start: String, end: String) { ... }
}
```

**Build & verify:** Compile succeeds. No visible change in the app.

#### Step 1.2: Create `CreditCardStatement` Model
**File:** `Finova/Sources/Core/Models/CreditCardStatement.swift` (NEW)

```swift
struct CreditCardStatement: Codable {
    var id: Int?
    var creditCardId: Int
    var closingDate: Date
    var dueDate: Date
    var totalAmount: Int                // In cents
    var isPaid: Bool
    var paidDate: Date?
    var paidAmount: Int?                // In cents
    var userId: String
    var createdAt: Date
    var updatedAt: Date

    var status: StatementStatus { ... } // Computed from dates + isPaid
}

enum StatementStatus: String, Codable {
    case open, closed, paid, overdue
}
```

**Build & verify:** Compile succeeds. No visible change.

#### Step 1.3: Database Migration
**File:** `Finova/Sources/Core/Database/DatabaseManager.swift` (EDIT - add migration)

Add the new tables and ALTER statements to the existing migration system:
- `CreditCards` table
- `CreditCardStatements` table
- ALTER `Transactions`: add `credit_card_id`, `statement_id`, `is_credit_card_statement` columns
- Create indexes

**Build & verify:** Run the app. Check console for successful migration logs. Dashboard still works normally.

#### Step 1.4: Extend `Transaction` Model
**File:** `Finova/Sources/Core/Repositories/TransactionRepository/TransactionModel.swift` (EDIT)

Add 3 optional fields to `Transaction`:
```swift
var creditCardId: Int?              // nil = cash/debit
var statementId: Int?               // Which statement this belongs to
var isCreditCardStatement: Bool?    // true = this is a statement payment
```

Update `TransactionData` accordingly.

**Build & verify:** App compiles. Existing transactions continue to work (new fields are nil/optional).

#### Step 1.5: Create `CreditCardRepository`
**File:** `Finova/Sources/Core/Repositories/CreditCardRepository.swift` (NEW)

Follow the same pattern as `TransactionRepository`:
```swift
class CreditCardRepository {
    func insertCard(_ card: CreditCard) -> Int?
    func fetchAllCards() -> [CreditCard]
    func fetchCard(byId id: Int) -> CreditCard?
    func updateCard(_ card: CreditCard) -> Bool
    func deleteCard(id: Int) -> Bool   // Soft delete recommended
}
```

**Build & verify:** Compile succeeds.

#### Step 1.6: Create `StatementRepository`
**File:** `Finova/Sources/Core/Repositories/StatementRepository.swift` (NEW)

```swift
class StatementRepository {
    func insertStatement(_ statement: CreditCardStatement) -> Int?
    func fetchStatements(forCardId cardId: Int) -> [CreditCardStatement]
    func fetchStatement(byId id: Int) -> CreditCardStatement?
    func fetchCurrentStatement(forCardId cardId: Int) -> CreditCardStatement?
    func updateStatement(_ statement: CreditCardStatement) -> Bool
    func markAsPaid(statementId: Int, paidAmount: Int?, paidDate: Date) -> Bool
}
```

**Build & verify:** Compile succeeds.

#### Step 1.7: Create `CreditCardService`
**File:** `Finova/Sources/Core/Services/CreditCardService.swift` (NEW)

Business logic layer:
```swift
class CreditCardService {
    func statementForTransaction(card: CreditCard, transactionDate: Date) -> CreditCardStatement
    func calculateDueDate(from closingDate: Date, dueDay: Int) -> Date
    func getOrCreateStatement(for card: CreditCard, transactionDate: Date) -> CreditCardStatement
    func recalculateStatementTotal(statementId: Int)
}
```

**Build & verify:** Compile succeeds. Full data layer is done.

**Checkpoint: Run the app.** Dashboard works identically. All existing features untouched. Data layer is ready.

---

### Phase 2: Credit Card Management Screens (Settings Flow)
> Goal: Add the ability to register, view, edit, and delete credit cards from Settings.

#### Step 2.1: Add "Credit Cards" Row to Settings
**Files:**
- `Finova/Sources/Scenes/Settings/SettingsView.swift` (EDIT)
- `Finova/Sources/Scenes/Settings/SettingsViewController.swift` (EDIT)
- `Finova/Sources/Scenes/Settings/SettingsFlowDelegate.swift` (EDIT)

In `SettingsView`:
- Add a **"FINANCIAL" section header** between Preferences and Notifications sections
- Add a `creditCardsContainer` row with credit card icon + chevron (follow exact pattern of `notificationsContainer`)

In `SettingsFlowDelegate`:
```swift
func navigateToCreditCards()
```

In `SettingsViewController`:
- Wire up tap gesture to call `flowDelegate?.navigateToCreditCards()`

**Build & verify:** Run app > Go to Settings. You should see the new "FINANCIAL" section with "Credit Cards" row. Tapping does nothing yet (will crash if delegate not implemented).

#### Step 2.2: Create Credit Cards List Screen (Empty State First)
**Files (ALL NEW):**
- `Finova/Sources/Scenes/CreditCards/CreditCardsView.swift`
- `Finova/Sources/Scenes/CreditCards/CreditCardsViewController.swift`
- `Finova/Sources/Scenes/CreditCards/CreditCardsViewModel.swift`
- `Finova/Sources/Scenes/CreditCards/CreditCardsFlowDelegate.swift`

Follow the existing pattern (e.g., `SettingsView` / `SettingsViewController`):
- Header with back button + title "Credit Cards" + "+" add button
- Empty state: centered message "No credit cards yet" + "Add your first card" button
- UIScrollView with UIStackView for card list (will be populated later)

In `ViewControllersFactory`:
```swift
func makeCreditCardsViewController(flowDelegate: CreditCardsFlowDelegate) -> CreditCardsViewController
```

In `AppFlowController`:
- Implement `SettingsFlowDelegate.navigateToCreditCards()`
- Implement `CreditCardsFlowDelegate` (back navigation)

**Build & verify:** Settings > Credit Cards > See empty state screen with back navigation working.

#### Step 2.3: Create Add Credit Card Screen (Form Only)
**Files (ALL NEW):**
- `Finova/Sources/Scenes/AddCreditCard/AddCreditCardView.swift`
- `Finova/Sources/Scenes/AddCreditCard/AddCreditCardViewController.swift`
- `Finova/Sources/Scenes/AddCreditCard/AddCreditCardViewModel.swift`

Form fields (follow existing `Input` component pattern):
1. **Card Name** - `Input(placeholder: "Card name")`
2. **Last 4 Digits** - `Input(type: .number, placeholder: "1234")` with 4-char limit
3. **Card Brand** - Horizontal selector (custom component or segmented control)
4. **Closing Day** - `Input(type: .picker(...), placeholder: "15")` with values 1-28
5. **Due Day** - `Input(type: .picker(...), placeholder: "22")` with values 1-28
6. **Credit Limit** - `Input(type: .currency, placeholder: "0,00")` (optional)
7. **Card Color** - Horizontal color dots selector

Bottom: Save `Button`

**Build & verify:** Credit Cards List > "+" button > See Add Card form. Fill in fields and tap Save. Card should persist to SQLite. Go back to list > Card should appear.

#### Step 2.4: Build the Credit Card Cell (List Item)
**File:** `Finova/Sources/Scenes/CreditCards/Views/CreditCardCell.swift` (NEW)

A UIView showing:
- Mini card preview (colored rectangle with card name, last 4 digits, brand icon)
- Below: "Closes: 15th - Due: 22nd - Limit: R$ 5.000"
- Current statement amount (fetched from `CreditCardService`)

**Build & verify:** Add a card > Go back to list > See the styled card cell with real data.

#### Step 2.5: SwiftUI Animated Card Component (Optional Enhancement)
**Files (ALL NEW):**
- `Finova/Sources/SwiftUI/CreditCard/CreditCardView.swift`
- `Finova/Sources/SwiftUI/CreditCard/CardFrontView.swift`
- `Finova/Sources/SwiftUI/CreditCard/CardBackView.swift`

Build the animated 3D flip card per the spec. Host in UIKit using `UIHostingController`.

Use this in the Add Card screen as a **live preview** at the top, and in the Card List as the card display.

**Build & verify:** Add Card screen shows live-updating card preview. Card List shows animated cards.

#### Step 2.6: Edit & Delete Credit Card
**Edit existing files:**
- `CreditCardsViewController` - Add swipe-to-delete and tap-to-edit
- `AddCreditCardViewController` - Support edit mode (populate fields from existing card)
- `CreditCardsViewModel` - Add delete logic (soft delete)

**Build & verify:**
- Long-press or swipe on card > Delete option > Card removed
- Tap card > Opens edit form pre-filled > Save updates the card

**Checkpoint: Full credit card CRUD from Settings is complete.**

---

### Phase 3: Payment Method in Add Transaction
> Goal: When adding a transaction, user can choose "Cash/Debit" or "Credit Card".

#### Step 3.1: Add Payment Method Selector to Add Transaction Modal
**File:** `Finova/Sources/Scenes/AddTransaction/AddTransactionModalView.swift` (EDIT)

Add a new section between the date field and the transaction type buttons:
1. **Separator line**
2. **"Payment Method" label**
3. **Two radio-style options:**
   - Cash/Debit (default selected) with subtitle "Affects balance immediately"
   - Credit Card with subtitle "Goes to card statement"

When "Credit Card" is selected:
- Show a card selector dropdown (or picker) populated from `CreditCardRepository.fetchAllCards()`
- Show info banner: "Goes to [Month] statement - Due: [date]"

When no cards registered:
- "Credit Card" option shows "No cards registered - Tap to add"
- Tapping navigates to Add Credit Card

**Build & verify:** Open Add Transaction modal > See new Payment Method section. Cash/Debit selected by default. Toggle to Credit Card > See card selector + statement info.

#### Step 3.2: Wire Payment Method to Transaction Save
**File:** `Finova/Sources/Scenes/AddTransaction/AddTransactionModalViewController.swift` (EDIT)

When saving with Credit Card:
1. Set `creditCardId` on the transaction
2. Use `CreditCardService.getOrCreateStatement()` to find/create the statement
3. Set `statementId` on the transaction
4. Recalculate statement total

**Build & verify:** Add a transaction with credit card > Check database > Transaction has `credit_card_id` and `statement_id` set. Statement total updated.

#### Step 3.3: Update Add Transaction Modal Height
The modal needs more vertical space for the payment method section. Adjust the `sheetHeight` calculation.

**Build & verify:** Modal doesn't clip content. All fields visible and scrollable.

**Checkpoint: Transactions can be tagged to credit cards.**

---

### Phase 4: Statement Generation & Dashboard Integration
> Goal: Statements appear as special transactions in the dashboard on their due date.

#### Step 4.1: Statement Transaction Auto-Generation
**File:** `Finova/Sources/Core/Services/CreditCardService.swift` (EDIT)

Add a method that runs on app launch / dashboard load:
```swift
func generateStatementTransactions(for userId: String)
```

Logic:
- For each credit card, check if a statement transaction exists for the current billing cycle
- If a statement closed and no transaction exists yet, create one:
  - Title: "[Card Name] Statement ****[last4]"
  - Amount: statement total
  - Date: due date
  - Category: `.bankSlip` (or new `.creditCardStatement`)
  - `isCreditCardStatement = true`

**Build & verify:** Add credit card transactions > Wait for statement period > Statement transaction appears in dashboard on due date.

#### Step 4.2: Statement Transaction Visual Differentiation
**File:** `Finova/Sources/Scenes/Dashboard/Views/TransactionCell.swift` (EDIT - or equivalent)

When rendering a transaction where `isCreditCardStatement == true`:
- Show credit card icon instead of category icon
- Show "[N] transactions - Tap to view" subtitle
- Slightly different background tint (subtle)

**Build & verify:** Dashboard shows statement transactions with distinct visual treatment.

#### Step 4.3: Balance Calculation Update
**File:** `Finova/Sources/Scenes/Dashboard/DashboardViewModel.swift` (EDIT)

Update balance calculation:
```
Current Balance =
    Starting Balance
    + All Income (cash/debit)
    - All Expenses (cash/debit)
    - Paid Credit Card Statements
    // NOT included: individual CC transactions (they don't affect balance)
```

Category budget calculation stays the same (includes CC transactions by date).

**Build & verify:** Add CC transactions > Balance doesn't change immediately. When statement is due and marked paid > Balance decreases.

**Checkpoint: Dashboard correctly shows statements and calculates balances.**

---

### Phase 5: Statement Details Screen
> Goal: Tapping a statement transaction opens a detailed breakdown view.

#### Step 5.1: Create Statement Details Screen
**Files (ALL NEW):**
- `Finova/Sources/Scenes/StatementDetails/StatementDetailsView.swift`
- `Finova/Sources/Scenes/StatementDetails/StatementDetailsViewController.swift`
- `Finova/Sources/Scenes/StatementDetails/StatementDetailsViewModel.swift`
- `Finova/Sources/Scenes/StatementDetails/Views/StatementTransactionCell.swift`

Layout per spec:
- Header: Card preview (mini) + "February 2026 Statement"
- Summary: Total, Due Date, Status badge (Open/Closed/Paid/Overdue)
- Transaction list: Grouped by date, showing all transactions in this statement
- Bottom: "Mark as Paid" button (or "Paid on [date]" if already paid)

**Build & verify:** Dashboard > Tap statement transaction > Opens Statement Details with correct transaction list.

#### Step 5.2: Wire Navigation
**Files:**
- `Finova/Sources/Scenes/StatementDetails/StatementDetailsFlowDelegate.swift` (NEW)
- `Finova/AppFlowController.swift` (EDIT)
- `Finova/Sources/Core/Factories/ViewControllersFactory/ViewControllersFactory.swift` (EDIT)

Add factory method and flow delegate implementation.

When tapping a statement transaction on Dashboard:
```swift
func navigateToStatementDetails(statement: CreditCardStatement)
```

**Build & verify:** Full navigation flow works. Back button returns to dashboard.

#### Step 5.3: Mark as Paid Functionality
In `StatementDetailsViewController`:
- "Mark as Paid" updates statement `isPaid = true`, `paidDate = Date()`
- Refreshes the view to show "Paid" status
- On dismissal, dashboard refreshes balance

**Build & verify:** Statement Details > Mark as Paid > Status badge changes to green "Paid". Dashboard balance updates.

**Checkpoint: Complete statement flow is working.**

---

### Phase 6: Edge Cases & Polish
> Goal: Handle all the weird scenarios.

#### Step 6.1: Closing Day Edge Cases
- Month with 30 days but closing day = 31 -> Use last day of month
- February -> Use 28 (or 29 for leap year)
- Transaction exactly on closing day -> Include in current statement

#### Step 6.2: Transaction Edit/Delete with Credit Cards
- Edit transaction date to different statement period -> Move to correct statement, recalculate both
- Delete credit card transaction -> Recalculate statement total
- Delete credit card with existing transactions -> Soft delete card, keep transactions

#### Step 6.3: Edit Transaction Modal Updates
When editing a credit card transaction:
- Show payment method section as read-only (can't change cash <-> credit card)
- Or allow changing with proper statement recalculation

#### Step 6.4: Refund/Negative Amounts
- Allow negative amounts on credit card transactions (refunds)
- Statement total reflects refunds

**Build & verify each edge case individually.**

---

### Phase 7: Final Integration Testing
> Run through these scenarios end-to-end:

1. **New user flow:** No cards -> Settings -> Add card -> Add CC transaction -> Check dashboard
2. **Multiple cards:** Add 2+ cards -> Transactions on different cards -> Correct statement grouping
3. **Statement cycle:** Transactions before/after closing day -> Correct statement assignment
4. **Mark as paid:** Statement paid -> Balance updates -> Status reflects paid
5. **Edit flows:** Edit CC transaction -> Statement totals update
6. **Delete flows:** Delete CC transaction -> Statement totals update. Delete card -> Transactions preserved
7. **Budget accuracy:** CC transactions immediately affect category budgets
8. **Balance accuracy:** CC transactions don't affect balance until statement paid

---

## File Creation Order (Summary)

```
Phase 1 - Data Layer:
  1. Core/Models/CreditCard.swift           (NEW)
  2. Core/Models/CreditCardStatement.swift   (NEW)
  3. Core/Database/DatabaseManager.swift     (EDIT - migration)
  4. Core/Repositories/TransactionModel.swift (EDIT - 3 new fields)
  5. Core/Repositories/CreditCardRepository.swift  (NEW)
  6. Core/Repositories/StatementRepository.swift    (NEW)
  7. Core/Services/CreditCardService.swift          (NEW)

Phase 2 - Settings Flow:
  8. Scenes/Settings/SettingsView.swift      (EDIT - add Financial section)
  9. Scenes/Settings/SettingsFlowDelegate.swift (EDIT)
  10. Scenes/Settings/SettingsViewController.swift  (EDIT)
  11. Scenes/CreditCards/CreditCardsFlowDelegate.swift  (NEW)
  12. Scenes/CreditCards/CreditCardsView.swift           (NEW)
  13. Scenes/CreditCards/CreditCardsViewController.swift (NEW)
  14. Scenes/CreditCards/CreditCardsViewModel.swift      (NEW)
  15. Scenes/AddCreditCard/AddCreditCardView.swift       (NEW)
  16. Scenes/AddCreditCard/AddCreditCardViewController.swift (NEW)
  17. Scenes/AddCreditCard/AddCreditCardViewModel.swift  (NEW)
  18. Scenes/CreditCards/Views/CreditCardCell.swift      (NEW)
  19. SwiftUI/CreditCard/CreditCardView.swift            (NEW - optional)
  20. SwiftUI/CreditCard/CardFrontView.swift             (NEW - optional)
  21. SwiftUI/CreditCard/CardBackView.swift              (NEW - optional)
  22. Core/Factories/ViewControllersFactory.swift  (EDIT)
  23. AppFlowController.swift                      (EDIT)

Phase 3 - Add Transaction:
  24. Scenes/AddTransaction/AddTransactionModalView.swift       (EDIT)
  25. Scenes/AddTransaction/AddTransactionModalViewController.swift (EDIT)

Phase 4 - Dashboard:
  26. Core/Services/CreditCardService.swift  (EDIT - statement generation)
  27. Scenes/Dashboard/DashboardViewModel.swift (EDIT - balance calc)
  28. Scenes/Dashboard/Views/ (EDIT - statement cell styling)

Phase 5 - Statement Details:
  29. Scenes/StatementDetails/StatementDetailsFlowDelegate.swift (NEW)
  30. Scenes/StatementDetails/StatementDetailsView.swift         (NEW)
  31. Scenes/StatementDetails/StatementDetailsViewController.swift (NEW)
  32. Scenes/StatementDetails/StatementDetailsViewModel.swift    (NEW)
  33. Scenes/StatementDetails/Views/StatementTransactionCell.swift (NEW)
  34. Core/Factories/ViewControllersFactory.swift  (EDIT)
  35. AppFlowController.swift                      (EDIT)
```

---

## Quick Reference: Build Checkpoints

| After Phase | What You Should See |
|---|---|
| Phase 0 | App auto-logs in and lands on Dashboard (DEBUG only) |
| Phase 1 | App works identically. No visual changes. Database has new tables. |
| Phase 2.1 | Settings shows "Financial > Credit Cards" row |
| Phase 2.2 | Credit Cards list with empty state |
| Phase 2.3 | Add Card form works, cards persist |
| Phase 2.4 | Card list shows styled card cells |
| Phase 3.1 | Add Transaction has Payment Method section |
| Phase 3.2 | CC transactions save with card + statement references |
| Phase 4.1 | Statement transactions auto-appear on due date |
| Phase 4.3 | Balance correctly excludes unpaid CC transactions |
| Phase 5.1 | Statement detail screen shows transaction breakdown |
| Phase 5.3 | Mark as Paid updates balance |
