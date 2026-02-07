# Credit Card Feature Specification (v1.5.0)

## Overview

This document specifies the credit card intelligence feature for Finova v1.5.0, including UX decisions, data architecture, and implementation details.

---

## UX Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Card number display | Last 4 digits only | Security + identification |
| Card registration UI | Animated 3D card view | Premium UX, engagement |
| Transaction timing | Register now, affect balance on due date | Matches real credit card behavior |
| Statement grouping | Parent statement transaction with child transactions | Clean organization, easy reconciliation |

---

## 1. Card Number Masking

### Display Format

```
Stored: Full number (encrypted) or last 4 only (recommended)
Displayed: •••• •••• •••• 1234
```

### Recommendation: Store Only Last 4 Digits

**Why not store the full number:**
- No actual need for full number (not processing payments)
- Reduces security liability
- Simpler compliance (no PCI DSS concerns)
- User only needs to identify which card

**Implementation:**

```swift
struct CreditCard {
    let id: UUID
    var name: String                    // "Nubank Ultravioleta"
    var lastFourDigits: String          // "1234"
    var cardBrand: CardBrand            // .visa, .mastercard, .amex, etc.
    var closingDay: Int                 // 1-28 (day of month statement closes)
    var dueDay: Int                     // 1-28 (day of month payment is due)
    var creditLimit: Decimal?           // Optional limit tracking
    var cardColor: CardColor            // For visual customization
    let userId: String
    let createdAt: Date
    var updatedAt: Date
}

enum CardBrand: String, Codable, CaseIterable {
    case visa = "Visa"
    case mastercard = "Mastercard"
    case amex = "American Express"
    case elo = "Elo"
    case hipercard = "Hipercard"
    case other = "Other"

    var icon: String {
        switch self {
        case .visa: return "cc_visa"
        case .mastercard: return "cc_mastercard"
        case .amex: return "cc_amex"
        case .elo: return "cc_elo"
        case .hipercard: return "cc_hipercard"
        case .other: return "cc_generic"
        }
    }
}

enum CardColor: String, Codable, CaseIterable {
    case black, purple, blue, green, gold, platinum, red, orange

    var gradient: [UIColor] {
        switch self {
        case .black: return [.black, .darkGray]
        case .purple: return [UIColor(hex: "#8B5CF6"), UIColor(hex: "#6D28D9")]
        case .blue: return [UIColor(hex: "#3B82F6"), UIColor(hex: "#1D4ED8")]
        case .green: return [UIColor(hex: "#10B981"), UIColor(hex: "#059669")]
        case .gold: return [UIColor(hex: "#F59E0B"), UIColor(hex: "#D97706")]
        case .platinum: return [UIColor(hex: "#94A3B8"), UIColor(hex: "#64748B")]
        case .red: return [UIColor(hex: "#EF4444"), UIColor(hex: "#DC2626")]
        case .orange: return [UIColor(hex: "#F97316"), UIColor(hex: "#EA580C")]
        }
    }
}
```

### Input UI

```
┌─────────────────────────────────────────┐
│  Last 4 digits of card                  │
│  ┌─────────────────────────────────────┐│
│  │  [____]                             ││
│  └─────────────────────────────────────┘│
│  This helps you identify which card     │
│  when viewing statements                │
└─────────────────────────────────────────┘
```

---

## 2. Animated Card View Component

### Visual Design

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ ████████████████████████████████████████████████████ │  │
│  │ ██                                              ██  │  │
│  │ ██    FINOVA                                    ██  │  │
│  │ ██                                              ██  │  │
│  │ ██    •••• •••• •••• 1234                       ██  │  │
│  │ ██                                              ██  │  │
│  │ ██    CARDHOLDER NAME              [VISA]      ██  │  │
│  │ ██                                              ██  │  │
│  │ ████████████████████████████████████████████████████ │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│           ← Swipe to flip / See back →                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘

Back of card (when flipped):
┌───────────────────────────────────────────────────────┐
│ ████████████████████████████████████████████████████ │
│ ██▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██ │  ← Magnetic stripe
│ ██                                              ██ │
│ ██    Closes on: 15th                           ██ │
│ ██    Due on: 22nd                              ██ │
│ ██                                              ██ │
│ ██    Limit: R$ 5.000,00                        ██ │
│ ██    Available: R$ 3.245,00                    ██ │
│ ██                                              ██ │
│ ████████████████████████████████████████████████████ │
└───────────────────────────────────────────────────────┘
```

### Animation Specifications

```swift
// CreditCardView.swift - SwiftUI Component

struct CreditCardView: View {
    let card: CreditCard
    @State private var isFlipped = false
    @State private var rotationAngle: Double = 0

    var body: some View {
        ZStack {
            // Front of card
            CardFrontView(card: card)
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(
                    .degrees(rotationAngle),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )

            // Back of card
            CardBackView(card: card)
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(
                    .degrees(rotationAngle + 180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if abs(value.translation.width) > 50 {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            isFlipped.toggle()
                            rotationAngle += 180
                        }
                    }
                }
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isFlipped.toggle()
                rotationAngle += 180
            }
        }
    }
}

// Entrance animation when card is created
extension CreditCardView {
    static func entranceAnimation() -> Animation {
        .spring(response: 0.8, dampingFraction: 0.7)
            .delay(0.1)
    }

    func onAppearAnimation() -> some View {
        self
            .scaleEffect(0.8)
            .opacity(0)
            .offset(y: 50)
            .onAppear {
                withAnimation(Self.entranceAnimation()) {
                    // Animates to normal state
                }
            }
    }
}
```

### Card Interactions

| Interaction | Animation | Duration |
|-------------|-----------|----------|
| Appear (new card) | Scale up + fade in + slide up | 0.8s spring |
| Tap | 3D flip to back | 0.6s spring |
| Swipe left/right | 3D flip | 0.6s spring |
| Long press | Subtle scale pulse | 0.3s |
| Delete | Shrink + fade + fall | 0.5s |

### Color Gradient Animation (Subtle Shimmer)

```swift
struct ShimmerGradient: View {
    @State private var phase: CGFloat = 0
    let colors: [Color]

    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: colors + [colors[0].opacity(0.8)] + colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .hueRotation(.degrees(phase * 10))
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}
```

---

## 3. Transaction Flow with Credit Cards

### Core Concept

```
User Action          Budget Impact           Balance Impact
─────────────────────────────────────────────────────────────
Register CC          Immediately shows       Only on due date
transaction          in category spending    (as statement payment)
(Feb 10)             (Feb budget)
                            │                       │
                            ▼                       ▼
                     Category: Food            Statement closes
                     Feb spent: +R$50          (Feb 15)
                                                    │
                                                    ▼
                                              Due date (Feb 22)
                                              Balance: -R$50
                                              (Statement transaction)
```

### Why This Approach?

1. **Budget accuracy**: User sees spending in real-time for budgeting
2. **Balance accuracy**: Cash flow reflects when money actually leaves account
3. **Statement reconciliation**: Easy to match with bank statement
4. **Real-world matching**: This is exactly how credit cards work

### Data Model

```swift
// Extended Transaction model
struct Transaction {
    let id: UUID
    var title: String
    var amount: Decimal
    var date: Date                      // When transaction occurred
    var category: Category
    var type: TransactionType           // .income, .expense
    var isRecurring: Bool
    var installmentInfo: InstallmentInfo?

    // NEW: Credit card fields
    var creditCardId: UUID?             // nil = cash/debit transaction
    var statementId: UUID?              // Which statement this belongs to
    var isCreditCardStatement: Bool     // true = this is a statement payment

    let userId: String
    let createdAt: Date
    var updatedAt: Date
}

// Statement model
struct CreditCardStatement {
    let id: UUID
    let creditCardId: UUID
    let closingDate: Date               // When statement closed
    let dueDate: Date                   // When payment is due
    var totalAmount: Decimal            // Sum of all transactions
    var isPaid: Bool                    // User marked as paid
    var paidDate: Date?                 // When user paid
    var paidAmount: Decimal?            // Partial payment support
    let userId: String
    let createdAt: Date
    var updatedAt: Date

    // Computed
    var transactions: [Transaction]     // Fetched via statementId
    var status: StatementStatus {
        if isPaid { return .paid }
        if Date() > dueDate { return .overdue }
        if Date() > closingDate { return .closed }
        return .open
    }
}

enum StatementStatus {
    case open       // Still accepting transactions
    case closed     // Statement closed, awaiting payment
    case paid       // Fully paid
    case overdue    // Past due date, not paid
}
```

### Statement Calculation Logic

```swift
class CreditCardService {

    /// Determines which statement a transaction belongs to
    func statementForTransaction(card: CreditCard, transactionDate: Date) -> StatementPeriod {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: transactionDate)

        // If transaction is before closing day, it goes to current month's statement
        // If after closing day, it goes to next month's statement

        if day <= card.closingDay {
            // Current month statement
            let closingDate = calendar.date(
                bySetting: .day,
                value: card.closingDay,
                of: transactionDate
            )!
            let dueDate = calculateDueDate(from: closingDate, dueDay: card.dueDay)
            return StatementPeriod(closingDate: closingDate, dueDate: dueDate)
        } else {
            // Next month statement
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: transactionDate)!
            let closingDate = calendar.date(
                bySetting: .day,
                value: card.closingDay,
                of: nextMonth
            )!
            let dueDate = calculateDueDate(from: closingDate, dueDay: card.dueDay)
            return StatementPeriod(closingDate: closingDate, dueDate: dueDate)
        }
    }

    /// Due date is always after closing date
    private func calculateDueDate(from closingDate: Date, dueDay: Int) -> Date {
        let calendar = Calendar.current

        // If due day > closing day, same month
        // If due day <= closing day, next month
        let closingDay = calendar.component(.day, from: closingDate)

        if dueDay > closingDay {
            return calendar.date(bySetting: .day, value: dueDay, of: closingDate)!
        } else {
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: closingDate)!
            return calendar.date(bySetting: .day, value: dueDay, of: nextMonth)!
        }
    }
}
```

### User Flow: Adding a Credit Card Transaction

```
┌─────────────────────────────────────────────────────────────────┐
│                    Add Transaction                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Amount                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  R$ 150,00                                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Description                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Dinner at Restaurant                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Category                                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  🍔 Food                                           ▼    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Date                                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Today, Feb 10, 2026                               ▼    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Payment Method                          ← NEW SECTION          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ○ Cash / Debit                                         │   │
│  │  ● Credit Card                                          │   │
│  │     ┌─────────────────────────────────────────────────┐ │   │
│  │     │  Nubank •••• 1234                          ▼   │ │   │
│  │     └─────────────────────────────────────────────────┘ │   │
│  │                                                         │   │
│  │     ℹ️ This will be added to your Feb statement         │   │
│  │        Due: Feb 22, 2026                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                      Add Transaction                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Statement View (When Tapping a Statement Transaction)

```
┌─────────────────────────────────────────────────────────────────┐
│  ←  Nubank Statement                                    •••    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │     ┌─────────────────────────────────────────────┐       │  │
│  │     │  NUBANK           •••• 1234        [VISA]  │       │  │
│  │     │                                             │       │  │
│  │     │     February 2026 Statement                 │       │  │
│  │     └─────────────────────────────────────────────┘       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Statement Period                                               │
│  Jan 16 - Feb 15, 2026                                         │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Total                                      R$ 1.250,00   │  │
│  │  Due Date                                      Feb 22     │  │
│  │  Status                              ● Awaiting Payment   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Transactions (12)                                              │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  Feb 10                                                         │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  🍔  Dinner at Restaurant                      R$ 150,00  │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │  🛒  Supermarket                               R$ 280,00  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Feb 8                                                          │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  ⛽  Gas Station                               R$ 200,00  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Feb 5                                                          │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  🎬  Netflix                                    R$ 55,90  │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │  🎵  Spotify                                    R$ 21,90  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ...more transactions...                                        │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    Mark as Paid                           │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Balance Calculation Logic

### How Balances Work

```
Dashboard Balance Calculation:
──────────────────────────────

Current Balance =
    Starting Balance
    + All Income (cash/debit)
    - All Expenses (cash/debit)
    - Paid Credit Card Statements

NOT included in current balance:
    - Unpaid credit card statements (they appear as transactions on due date)
    - Future dated transactions


Category Budget Calculation:
────────────────────────────

Category Spent =
    All expenses in category this month
    INCLUDING credit card transactions (by transaction date)

This means:
- User sees real spending in budget immediately
- Can track if over budget before statement is due
```

### Dashboard: Statement in Transaction List

Statements appear as **regular transactions** in the transaction list on their due date. No separate "upcoming bills" section needed—keeps the UI clean and consistent.

```
┌─────────────────────────────────────────────────────────────────┐
│  Current Balance                                                │
│  R$ 3.450,00                                                   │
│                                                                 │
│  February 2026                                                  │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  Feb 25                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  💳  Itaú Statement •••• 5678                R$ 890,00  │   │
│  │      12 transactions · Tap to view                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Feb 22                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  💳  Nubank Statement •••• 1234            R$ 1.250,00  │   │
│  │      8 transactions · Tap to view                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Feb 15                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  💰  Salary                               +R$ 5.000,00  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Feb 10                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  🛒  Grocery Store (Cash)                    R$ 150,00  │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │  ⛽  Gas Station (Cash)                      R$ 200,00  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Key Points:**
- Statement transactions are visually distinct (💳 icon + card info)
- Shows transaction count as secondary info
- Tapping opens Statement Details view with all transactions
- Cash/debit transactions show "(Cash)" label for clarity when cards exist

---

## 5. Credit Card Management: Entry Points

### Where to Access Credit Cards

**Option A: Settings Screen (Recommended)**

```
┌─────────────────────────────────────────────────────────────────┐
│  ←  Settings                                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ACCOUNT                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  👤  Profile                                        >   │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │  🔐  Security & Biometrics                          >   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  FINANCIAL                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  💳  Credit Cards                                   >   │   │  ← NEW
│  ├─────────────────────────────────────────────────────────┤   │
│  │  📊  Categories                                     >   │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │  🔄  Recurring Transactions                         >   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  NOTIFICATIONS                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  🔔  Notification Settings                          >   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Credit Cards List Screen

```
┌─────────────────────────────────────────────────────────────────┐
│  ←  Credit Cards                                          +     │  ← Add button
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  ██████████████████████████████████████████████████ │  │  │
│  │  │  ██  NUBANK                              [VISA] ██ │  │  │
│  │  │  ██  •••• •••• •••• 1234                        ██ │  │  │
│  │  │  ██████████████████████████████████████████████████ │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  │                                                           │  │
│  │  Closes: 15th  ·  Due: 22nd  ·  Limit: R$ 5.000          │  │
│  │  Current statement: R$ 1.250,00                          │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  ██████████████████████████████████████████████████ │  │  │
│  │  │  ██  ITAÚ                         [MASTERCARD] ██ │  │  │
│  │  │  ██  •••• •••• •••• 5678                        ██ │  │  │
│  │  │  ██████████████████████████████████████████████████ │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  │                                                           │  │
│  │  Closes: 20th  ·  Due: 27th  ·  Limit: R$ 3.000          │  │
│  │  Current statement: R$ 890,00                            │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │               +  Add New Credit Card                      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Add/Edit Credit Card Screen

```
┌─────────────────────────────────────────────────────────────────┐
│  ←  Add Credit Card                                      Save   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  ██████████████████████████████████████████████████ │  │  │
│  │  │  ██  [Card Name]                         [Brand] ██ │  │  │  ← Live preview
│  │  │  ██  •••• •••• •••• [____]                      ██ │  │  │
│  │  │  ██████████████████████████████████████████████████ │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Card Name *                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Nubank Ultravioleta                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Last 4 Digits *                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1234                                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│  Helps identify this card in statements                         │
│                                                                 │
│  Card Brand                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  [VISA] [MC] [AMEX] [ELO] [HIPER] [OTHER]              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Statement Closing Day *                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  15                                                 ▼   │   │
│  └─────────────────────────────────────────────────────────┘   │
│  Day of month when your statement closes                        │
│                                                                 │
│  Payment Due Day *                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  22                                                 ▼   │   │
│  └─────────────────────────────────────────────────────────┘   │
│  Day of month when payment is due                               │
│                                                                 │
│  Credit Limit (optional)                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  R$ 5.000,00                                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Card Color                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  [⚫] [🟣] [🔵] [🟢] [🟡] [⚪] [🔴] [🟠]              │   │
│  │   ↑ Selected                                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. Add Transaction Modal: Complete Flow

### Current Modal vs Updated Modal

```
CURRENT (v1.4.0)                    UPDATED (v1.5.0)
─────────────────────               ─────────────────────
┌─────────────────┐                 ┌─────────────────┐
│ Amount          │                 │ Amount          │
│ Description     │                 │ Description     │
│ Category        │                 │ Category        │
│ Date            │                 │ Date            │
│ Type (Inc/Exp)  │                 │ Type (Inc/Exp)  │
│ Recurring?      │                 │ Recurring?      │
│                 │                 │ ─────────────── │
│                 │                 │ Payment Method  │  ← NEW
│                 │                 │   ○ Cash/Debit  │
│                 │                 │   ○ Credit Card │
│                 │                 │     [Select]    │
└─────────────────┘                 └─────────────────┘
```

### Full Add Transaction Modal (v1.5.0)

```
┌─────────────────────────────────────────────────────────────────┐
│                         Add Transaction                     X   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                     R$ 0,00                              │   │  ← Large amount input
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌───────────────────────┐  ┌───────────────────────┐          │
│  │      ▼ Expense        │  │      △ Income         │          │  ← Toggle
│  │      (selected)       │  │                       │          │
│  └───────────────────────┘  └───────────────────────┘          │
│                                                                 │
│  Description                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  What did you spend on?                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Category                                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  🍔 Food                                            >   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Date                                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  📅 Today, Feb 10, 2026                             >   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  Payment Method                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │  ● 💵  Cash / Debit                             │   │   │  ← Default selected
│  │  │        Affects balance immediately              │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                                                         │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │  ○ 💳  Credit Card                              │   │   │
│  │  │        Goes to card statement                   │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  🔄  Make this recurring                            ○   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Add Transaction                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### When "Credit Card" is Selected

```
┌─────────────────────────────────────────────────────────────────┐
│                         Add Transaction                     X   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                     R$ 150,00                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌───────────────────────┐  ┌───────────────────────┐          │
│  │      ▼ Expense        │  │      △ Income         │          │
│  │      (selected)       │  │                       │          │
│  └───────────────────────┘  └───────────────────────┘          │
│                                                                 │
│  Description                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Dinner at Restaurant                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Category                                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  🍔 Food                                            >   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Date                                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  📅 Today, Feb 10, 2026                             >   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  Payment Method                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │  ○ 💵  Cash / Debit                             │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                                                         │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │  ● 💳  Credit Card                              │   │   │  ← Selected
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                                                         │   │
│  │  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐   │   │
│  │    Select Card                                     ▼       │  ← Appears when CC selected
│  │  │ ┌───────────────────────────────────────────┐ │   │   │
│  │    │ ██ NUBANK ████  •••• 1234  [VISA] ██████ │       │   │
│  │  │ └───────────────────────────────────────────┘ │   │   │
│  │  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘   │   │
│  │                                                         │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │  ℹ️  Goes to February statement                  │   │   │  ← Info banner
│  │  │      Due: Feb 22, 2026                          │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  🔄  Make this recurring                            ○   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Add Transaction                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Card Selection Dropdown (When Multiple Cards)

```
┌─────────────────────────────────────────────────────────────────┐
│  Select Card                                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │ ██ NUBANK ████████  •••• 1234  [VISA] ████████ │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │  Closes: 15th · Due: 22nd                          ✓    │   │  ← Selected
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │ ██ ITAÚ █████████  •••• 5678  [MC] ███████████ │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │  Closes: 20th · Due: 27th                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │ ██ INTER ████████  •••• 9012  [MC] ███████████ │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │  Closes: 1st · Due: 8th                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  + Add New Card                                         │   │  ← Quick add
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### No Cards Registered State

```
┌─────────────────────────────────────────────────────────────────┐
│  Payment Method                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │  ● 💵  Cash / Debit                             │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                                                         │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │  ○ 💳  Credit Card                              │   │   │
│  │  │        No cards registered                      │   │   │  ← Grayed out
│  │  │        Tap to add a card                        │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

When tapped → Opens Add Credit Card modal
```

---

## 7. Database Schema Changes

### New Tables

```sql
-- Credit Cards table
CREATE TABLE IF NOT EXISTS CreditCards (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    last_four_digits TEXT NOT NULL,
    card_brand TEXT NOT NULL,
    closing_day INTEGER NOT NULL CHECK (closing_day BETWEEN 1 AND 28),
    due_day INTEGER NOT NULL CHECK (due_day BETWEEN 1 AND 28),
    credit_limit REAL,
    card_color TEXT NOT NULL DEFAULT 'blue',
    user_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- Credit Card Statements table
CREATE TABLE IF NOT EXISTS CreditCardStatements (
    id TEXT PRIMARY KEY,
    credit_card_id TEXT NOT NULL,
    closing_date TEXT NOT NULL,
    due_date TEXT NOT NULL,
    total_amount REAL NOT NULL DEFAULT 0,
    is_paid INTEGER NOT NULL DEFAULT 0,
    paid_date TEXT,
    paid_amount REAL,
    user_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (credit_card_id) REFERENCES CreditCards(id) ON DELETE CASCADE
);

-- Add to existing Transactions table
ALTER TABLE Transactions ADD COLUMN credit_card_id TEXT REFERENCES CreditCards(id);
ALTER TABLE Transactions ADD COLUMN statement_id TEXT REFERENCES CreditCardStatements(id);
ALTER TABLE Transactions ADD COLUMN is_credit_card_statement INTEGER DEFAULT 0;

-- Indexes for performance
CREATE INDEX idx_transactions_credit_card ON Transactions(credit_card_id);
CREATE INDEX idx_transactions_statement ON Transactions(statement_id);
CREATE INDEX idx_statements_credit_card ON CreditCardStatements(credit_card_id);
CREATE INDEX idx_statements_due_date ON CreditCardStatements(due_date);
```

---

## 8. Architecture: New Files

```
Sources/
├── Core/
│   ├── Models/
│   │   ├── CreditCard.swift              # Card model + enums
│   │   └── CreditCardStatement.swift     # Statement model
│   ├── Repositories/
│   │   ├── CreditCardRepository.swift    # CRUD for cards
│   │   └── StatementRepository.swift     # CRUD for statements
│   ├── Services/
│   │   └── CreditCardService.swift       # Business logic
│   └── Database/
│       └── Migrations/
│           └── V1_5_0_CreditCards.swift  # Schema migration
├── Scenes/
│   ├── CreditCards/                      # Card list scene
│   │   ├── CreditCardsViewController.swift
│   │   ├── CreditCardsViewModel.swift
│   │   └── Views/
│   │       └── CreditCardCell.swift
│   ├── AddCreditCard/                    # Add/edit card scene
│   │   ├── AddCreditCardViewController.swift
│   │   ├── AddCreditCardViewModel.swift
│   │   └── Views/
│   │       └── CardColorPicker.swift
│   └── StatementDetails/                 # Statement view scene
│       ├── StatementDetailsViewController.swift
│       ├── StatementDetailsViewModel.swift
│       └── Views/
│           └── StatementTransactionCell.swift
└── SwiftUI/
    └── CreditCard/
        ├── CreditCardView.swift          # Animated card component
        ├── CardFrontView.swift
        └── CardBackView.swift
```

---

## 9. Edge Cases to Handle

### Statement Period Edge Cases

| Scenario | Handling |
|----------|----------|
| Closing day 31 but month has 30 days | Use last day of month |
| Closing day 29/30/31 in February | Use Feb 28 (or 29 in leap year) |
| Transaction on closing day | Include in current statement |
| Card created mid-cycle | Create partial first statement |

### Transaction Edge Cases

| Scenario | Handling |
|----------|----------|
| Edit transaction date to different statement period | Move to correct statement, recalculate both |
| Delete credit card with transactions | Keep transactions, mark card as deleted (soft delete) |
| Refund on credit card | Negative amount in statement |
| Installment purchase on credit card | Create recurring transactions across statements |

---

## 10. Future Enhancements (v1.6.0+)

- [ ] Import statements via PDF (AI feature)
- [ ] Push notifications for due dates
- [ ] Spending limit warnings
- [ ] Multiple statement views (last 6 months)
- [ ] Credit utilization tracking
- [ ] Minimum payment tracking
- [ ] Interest calculation for carried balance
