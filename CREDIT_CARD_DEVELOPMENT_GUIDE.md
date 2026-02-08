# Credit Card Feature — Full Implementation Code

> **Methodology:** Build & Verify at every step. Create skeleton → build app → add component → build app → repeat.
> **Pattern reference:** 100% Programmatic UIKit, MVVM + FlowDelegate + Factory. Amounts in cents (Int). SQLite via DBHelper.shared.

---

## Localization Keys Reference

Add all keys below to `Finova/Resources/Localizable.xcstrings` with EN and PT-BR translations before starting.

<details>
<summary>Click to expand full localization table</summary>

### Settings Screen
| Key | EN | PT-BR |
|---|---|---|
| `settings.section.financial` | Financial | Financeiro |
| `settings.creditCards.title` | Credit Cards | Cartões de Crédito |

### Credit Cards List Screen
| Key | EN | PT-BR |
|---|---|---|
| `creditCards.header.title` | Credit Cards | Cartões de Crédito |
| `creditCards.empty.title` | No credit cards yet | Nenhum cartão cadastrado |
| `creditCards.empty.subtitle` | Add your first card to start tracking | Adicione seu primeiro cartão para começar |
| `creditCards.cell.closes` | Closes: %@ | Fecha: %@ |
| `creditCards.cell.due` | Due: %@ | Vence: %@ |
| `creditCards.cell.limit` | Limit: %@ | Limite: %@ |
| `creditCards.cell.currentStatement` | Current: %@ | Atual: %@ |
| `creditCards.delete.title` | Delete Card | Excluir Cartão |
| `creditCards.delete.message` | Are you sure you want to delete this card? Existing transactions will be preserved. | Tem certeza que deseja excluir este cartão? As transações existentes serão preservadas. |

### Add/Edit Credit Card Screen
| Key | EN | PT-BR |
|---|---|---|
| `addCreditCard.header.title` | Add Credit Card | Adicionar Cartão |
| `editCreditCard.header.title` | Edit Credit Card | Editar Cartão |
| `addCreditCard.input.name` | Card Name | Nome do Cartão |
| `addCreditCard.input.name.placeholder` | e.g. Nubank Ultravioleta | ex: Nubank Ultravioleta |
| `addCreditCard.input.lastFourDigits` | Last 4 Digits | Últimos 4 Dígitos |
| `addCreditCard.input.lastFourDigits.hint` | Helps identify this card in statements | Ajuda a identificar este cartão nas faturas |
| `addCreditCard.input.brand` | Card Brand | Bandeira |
| `addCreditCard.input.closingDay` | Closing Day | Dia de Fechamento |
| `addCreditCard.input.closingDay.hint` | Day of month when your statement closes | Dia do mês em que sua fatura fecha |
| `addCreditCard.input.dueDay` | Due Day | Dia de Vencimento |
| `addCreditCard.input.dueDay.hint` | Day of month when payment is due | Dia do mês em que o pagamento vence |
| `addCreditCard.input.creditLimit` | Credit Limit (optional) | Limite de Crédito (opcional) |
| `addCreditCard.input.color` | Card Color | Cor do Cartão |
| `addCreditCard.button.save` | Save | Salvar |
| `editCreditCard.button.save` | Update | Atualizar |

### Card Brand Display Names
| Key | EN | PT-BR |
|---|---|---|
| `cardBrand.visa` | Visa | Visa |
| `cardBrand.mastercard` | Mastercard | Mastercard |
| `cardBrand.amex` | American Express | American Express |
| `cardBrand.elo` | Elo | Elo |
| `cardBrand.hipercard` | Hipercard | Hipercard |
| `cardBrand.other` | Other | Outro |

### Add Transaction Modal - Payment Method
| Key | EN | PT-BR |
|---|---|---|
| `addTransactionModal.paymentMethod.title` | Payment Method | Método de Pagamento |
| `addTransactionModal.paymentMethod.cashDebit` | Cash / Debit | Dinheiro / Débito |
| `addTransactionModal.paymentMethod.cashDebit.subtitle` | Affects balance immediately | Afeta o saldo imediatamente |
| `addTransactionModal.paymentMethod.creditCard` | Credit Card | Cartão de Crédito |
| `addTransactionModal.paymentMethod.creditCard.subtitle` | Goes to card statement | Vai para a fatura do cartão |
| `addTransactionModal.paymentMethod.selectCard` | Select Card | Selecionar Cartão |
| `addTransactionModal.paymentMethod.statementInfo` | Goes to %@ statement — Due: %@ | Vai para a fatura de %@ — Vence: %@ |
| `addTransactionModal.paymentMethod.noCards` | No cards registered | Nenhum cartão cadastrado |
| `addTransactionModal.paymentMethod.noCards.hint` | Tap to add a card | Toque para adicionar um cartão |

### Dashboard - Statement Transaction
| Key | EN | PT-BR |
|---|---|---|
| `creditCard.statement.title` | %@ Statement ****%@ | Fatura %@ ****%@ |
| `creditCard.statement.subtitle` | %d transactions · Tap to view | %d transações · Toque para ver |
| `creditCard.statement.subtitle.singular` | %d transaction · Tap to view | %d transação · Toque para ver |

### Statement Details Screen
| Key | EN | PT-BR |
|---|---|---|
| `statementDetails.header.title` | %@ Statement | Fatura %@ |
| `statementDetails.header.subtitle` | Statement details | Detalhes da fatura |
| `statementDetails.period` | Statement Period | Período da Fatura |
| `statementDetails.total` | Total | Total |
| `statementDetails.dueDate` | Due Date | Data de Vencimento |
| `statementDetails.status` | Status | Status |
| `statementDetails.transactions` | Transactions (%d) | Transações (%d) |
| `statementDetails.button.markAsPaid` | Mark as Paid | Marcar como Paga |
| `statementDetails.paidOn` | Paid on %@ | Paga em %@ |

### Statement Status Labels
| Key | EN | PT-BR |
|---|---|---|
| `statementStatus.open` | Open | Aberta |
| `statementStatus.closed` | Awaiting Payment | Aguardando Pagamento |
| `statementStatus.paid` | Paid | Paga |
| `statementStatus.overdue` | Overdue | Vencida |

</details>

---

# PHASE 1 — Data Layer

> No UI changes. Build after each step to confirm compilation.

---

## Step 1.1 — CreditCard Model

**NEW FILE:** `Finova/Sources/Core/Models/CreditCard.swift`

```swift
//
//  CreditCard.swift
//  Finova
//

import Foundation
import UIKit

struct CreditCard: Codable {
  var id: Int?
  var name: String
  var lastFourDigits: String
  var cardBrand: CardBrand
  var closingDay: Int
  var dueDay: Int
  var creditLimit: Int?
  var cardColor: CardColor
  var userId: String
  var isDeleted: Bool
  var createdAt: Date
  var updatedAt: Date
}

enum CardBrand: String, Codable, CaseIterable {
  case visa, mastercard, amex, elo, hipercard, other

  var displayName: String {
    "cardBrand.\(rawValue)".localized
  }

  var iconName: String {
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

  var startColor: UIColor {
    switch self {
    case .black: return .black
    case .purple: return UIColor(hex: "#8B5CF6")
    case .blue: return UIColor(hex: "#3B82F6")
    case .green: return UIColor(hex: "#10B981")
    case .gold: return UIColor(hex: "#F59E0B")
    case .platinum: return UIColor(hex: "#94A3B8")
    case .red: return UIColor(hex: "#EF4444")
    case .orange: return UIColor(hex: "#F97316")
    }
  }

  var endColor: UIColor {
    switch self {
    case .black: return .darkGray
    case .purple: return UIColor(hex: "#6D28D9")
    case .blue: return UIColor(hex: "#1D4ED8")
    case .green: return UIColor(hex: "#059669")
    case .gold: return UIColor(hex: "#D97706")
    case .platinum: return UIColor(hex: "#64748B")
    case .red: return UIColor(hex: "#DC2626")
    case .orange: return UIColor(hex: "#EA580C")
    }
  }
}
```

**BUILD & VERIFY:** Compiles. No visible change.

---

## Step 1.2 — CreditCardStatement Model

**NEW FILE:** `Finova/Sources/Core/Models/CreditCardStatement.swift`

```swift
//
//  CreditCardStatement.swift
//  Finova
//

import Foundation

struct CreditCardStatement: Codable {
  var id: Int?
  var creditCardId: Int
  var closingDate: Date
  var dueDate: Date
  var totalAmount: Int
  var isPaid: Bool
  var paidDate: Date?
  var paidAmount: Int?
  var userId: String
  var createdAt: Date
  var updatedAt: Date

  var status: StatementStatus {
    if isPaid { return .paid }
    if Date() > dueDate { return .overdue }
    if Date() > closingDate { return .closed }
    return .open
  }
}

enum StatementStatus: String, Codable {
  case open, closed, paid, overdue

  var displayName: String {
    "statementStatus.\(rawValue)".localized
  }

  var color: UIColor {
    switch self {
    case .open: return Colors.mainGreen
    case .closed: return Colors.warningAmber
    case .paid: return Colors.gray500
    case .overdue: return Colors.mainRed
    }
  }
}
```

**BUILD & VERIFY:** Compiles.

---

## Step 1.3 — Database Migration

**EDIT FILE:** `Finova/Sources/Core/Database/DBHelper.swift`

Add to `initializeDatabase()`, after `try migrateTransactionsTable()`:

```swift
try createCreditCardsTable()
try createCreditCardStatementsTable()
try migrateCreditCardColumns()
```

Add these methods to the `DBHelper` class:

```swift
// MARK: - Credit Card Tables

private func createCreditCardsTable() throws {
  let query = """
    CREATE TABLE IF NOT EXISTS CreditCards (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        name            TEXT NOT NULL,
        last_four_digits TEXT NOT NULL,
        card_brand      TEXT NOT NULL,
        closing_day     INTEGER NOT NULL CHECK (closing_day BETWEEN 1 AND 28),
        due_day         INTEGER NOT NULL CHECK (due_day BETWEEN 1 AND 28),
        credit_limit    INTEGER,
        card_color      TEXT NOT NULL DEFAULT 'blue',
        user_id         TEXT NOT NULL,
        is_deleted      INTEGER NOT NULL DEFAULT 0,
        created_at      INTEGER NOT NULL,
        updated_at      INTEGER NOT NULL
    );
    """

  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }
  guard sqlite3_step(statement) == SQLITE_DONE else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.stepFailed(message: msg)
  }
}

private func createCreditCardStatementsTable() throws {
  let query = """
    CREATE TABLE IF NOT EXISTS CreditCardStatements (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        credit_card_id  INTEGER NOT NULL,
        closing_date    INTEGER NOT NULL,
        due_date        INTEGER NOT NULL,
        total_amount    INTEGER NOT NULL DEFAULT 0,
        is_paid         INTEGER NOT NULL DEFAULT 0,
        paid_date       INTEGER,
        paid_amount     INTEGER,
        user_id         TEXT NOT NULL,
        created_at      INTEGER NOT NULL,
        updated_at      INTEGER NOT NULL,
        FOREIGN KEY (credit_card_id) REFERENCES CreditCards(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_stmt_card_id ON CreditCardStatements(credit_card_id);
    CREATE INDEX IF NOT EXISTS idx_stmt_due_date ON CreditCardStatements(due_date);
    """

  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }
  guard sqlite3_step(statement) == SQLITE_DONE else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.stepFailed(message: msg)
  }
}

private func migrateCreditCardColumns() throws {
  let checkQuery = "PRAGMA table_info(Transactions);"
  var statement: OpaquePointer?

  guard sqlite3_prepare_v2(db, checkQuery, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }

  var existingColumns: Set<String> = []
  while sqlite3_step(statement) == SQLITE_ROW {
    let columnName = String(cString: sqlite3_column_text(statement, 1))
    existingColumns.insert(columnName)
  }

  let ccColumns: [String: String] = [
    "credit_card_id": "ALTER TABLE Transactions ADD COLUMN credit_card_id INTEGER;",
    "statement_id": "ALTER TABLE Transactions ADD COLUMN statement_id INTEGER;",
    "is_credit_card_statement": "ALTER TABLE Transactions ADD COLUMN is_credit_card_statement INTEGER DEFAULT 0;",
  ]

  for (column, alterQuery) in ccColumns {
    if !existingColumns.contains(column) {
      var alterStatement: OpaquePointer?
      guard sqlite3_prepare_v2(db, alterQuery, -1, &alterStatement, nil) == SQLITE_OK else {
        let msg = String(cString: sqlite3_errmsg(db))
        throw DBError.prepareFailed(message: msg)
      }
      defer { sqlite3_finalize(alterStatement) }
      guard sqlite3_step(alterStatement) == SQLITE_DONE else {
        let msg = String(cString: sqlite3_errmsg(db))
        throw DBError.stepFailed(message: msg)
      }
    }
  }
}

// MARK: - Credit Card CRUD

func insertCreditCard(
  name: String, lastFourDigits: String, cardBrand: String,
  closingDay: Int, dueDay: Int, creditLimit: Int?,
  cardColor: String, userId: String
) throws -> Int {
  guard isInitialized else { return 0 }

  let query = """
    INSERT INTO CreditCards (
      name, last_four_digits, card_brand, closing_day, due_day,
      credit_limit, card_color, user_id, is_deleted, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?);
    """

  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }

  let now = Int64(Date().timeIntervalSince1970)

  sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
  sqlite3_bind_text(statement, 2, lastFourDigits, -1, SQLITE_TRANSIENT)
  sqlite3_bind_text(statement, 3, cardBrand, -1, SQLITE_TRANSIENT)
  sqlite3_bind_int(statement, 4, Int32(closingDay))
  sqlite3_bind_int(statement, 5, Int32(dueDay))
  if let limit = creditLimit {
    sqlite3_bind_int64(statement, 6, Int64(limit))
  } else {
    sqlite3_bind_null(statement, 6)
  }
  sqlite3_bind_text(statement, 7, cardColor, -1, SQLITE_TRANSIENT)
  sqlite3_bind_text(statement, 8, userId, -1, SQLITE_TRANSIENT)
  sqlite3_bind_int64(statement, 9, now)
  sqlite3_bind_int64(statement, 10, now)

  guard sqlite3_step(statement) == SQLITE_DONE else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.stepFailed(message: msg)
  }

  return Int(sqlite3_last_insert_rowid(db))
}

func getCreditCards(userId: String) throws -> [(id: Int, name: String, lastFourDigits: String, cardBrand: String, closingDay: Int, dueDay: Int, creditLimit: Int?, cardColor: String, isDeleted: Bool, createdAt: Int, updatedAt: Int)] {
  guard isInitialized else { return [] }

  let query = """
    SELECT id, name, last_four_digits, card_brand, closing_day, due_day,
           credit_limit, card_color, is_deleted, created_at, updated_at
    FROM CreditCards WHERE user_id = ? AND is_deleted = 0
    ORDER BY created_at DESC;
    """

  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }
  sqlite3_bind_text(statement, 1, userId, -1, SQLITE_TRANSIENT)

  var results: [(id: Int, name: String, lastFourDigits: String, cardBrand: String, closingDay: Int, dueDay: Int, creditLimit: Int?, cardColor: String, isDeleted: Bool, createdAt: Int, updatedAt: Int)] = []

  while sqlite3_step(statement) == SQLITE_ROW {
    let id = Int(sqlite3_column_int64(statement, 0))
    let name = String(cString: sqlite3_column_text(statement, 1))
    let lastFour = String(cString: sqlite3_column_text(statement, 2))
    let brand = String(cString: sqlite3_column_text(statement, 3))
    let closing = Int(sqlite3_column_int(statement, 4))
    let due = Int(sqlite3_column_int(statement, 5))
    let limit: Int? = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 6))
    let color = String(cString: sqlite3_column_text(statement, 7))
    let deleted = sqlite3_column_int(statement, 8) == 1
    let createdAt = Int(sqlite3_column_int64(statement, 9))
    let updatedAt = Int(sqlite3_column_int64(statement, 10))

    results.append((id, name, lastFour, brand, closing, due, limit, color, deleted, createdAt, updatedAt))
  }

  return results
}

func getCreditCard(id: Int) throws -> (id: Int, name: String, lastFourDigits: String, cardBrand: String, closingDay: Int, dueDay: Int, creditLimit: Int?, cardColor: String, userId: String, isDeleted: Bool, createdAt: Int, updatedAt: Int)? {
  guard isInitialized else { return nil }

  let query = "SELECT id, name, last_four_digits, card_brand, closing_day, due_day, credit_limit, card_color, user_id, is_deleted, created_at, updated_at FROM CreditCards WHERE id = ?;"
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }
  sqlite3_bind_int64(statement, 1, Int64(id))

  guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

  return (
    Int(sqlite3_column_int64(statement, 0)),
    String(cString: sqlite3_column_text(statement, 1)),
    String(cString: sqlite3_column_text(statement, 2)),
    String(cString: sqlite3_column_text(statement, 3)),
    Int(sqlite3_column_int(statement, 4)),
    Int(sqlite3_column_int(statement, 5)),
    sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 6)),
    String(cString: sqlite3_column_text(statement, 7)),
    String(cString: sqlite3_column_text(statement, 8)),
    sqlite3_column_int(statement, 9) == 1,
    Int(sqlite3_column_int64(statement, 10)),
    Int(sqlite3_column_int64(statement, 11))
  )
}

func updateCreditCard(id: Int, name: String, lastFourDigits: String, cardBrand: String, closingDay: Int, dueDay: Int, creditLimit: Int?, cardColor: String) throws {
  guard isInitialized else { return }

  let query = """
    UPDATE CreditCards SET name = ?, last_four_digits = ?, card_brand = ?,
    closing_day = ?, due_day = ?, credit_limit = ?, card_color = ?, updated_at = ?
    WHERE id = ?;
    """
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }

  sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
  sqlite3_bind_text(statement, 2, lastFourDigits, -1, SQLITE_TRANSIENT)
  sqlite3_bind_text(statement, 3, cardBrand, -1, SQLITE_TRANSIENT)
  sqlite3_bind_int(statement, 4, Int32(closingDay))
  sqlite3_bind_int(statement, 5, Int32(dueDay))
  if let limit = creditLimit { sqlite3_bind_int64(statement, 6, Int64(limit)) } else { sqlite3_bind_null(statement, 6) }
  sqlite3_bind_text(statement, 7, cardColor, -1, SQLITE_TRANSIENT)
  sqlite3_bind_int64(statement, 8, Int64(Date().timeIntervalSince1970))
  sqlite3_bind_int64(statement, 9, Int64(id))

  guard sqlite3_step(statement) == SQLITE_DONE else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.stepFailed(message: msg)
  }
}

func softDeleteCreditCard(id: Int) throws {
  guard isInitialized else { return }
  let query = "UPDATE CreditCards SET is_deleted = 1, updated_at = ? WHERE id = ?;"
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }
  sqlite3_bind_int64(statement, 1, Int64(Date().timeIntervalSince1970))
  sqlite3_bind_int64(statement, 2, Int64(id))
  guard sqlite3_step(statement) == SQLITE_DONE else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.stepFailed(message: msg)
  }
}

// MARK: - Statement CRUD

func insertStatement(creditCardId: Int, closingDate: Int, dueDate: Int, totalAmount: Int, userId: String) throws -> Int {
  guard isInitialized else { return 0 }
  let query = """
    INSERT INTO CreditCardStatements (
      credit_card_id, closing_date, due_date, total_amount, is_paid, user_id, created_at, updated_at
    ) VALUES (?, ?, ?, ?, 0, ?, ?, ?);
    """
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }

  let now = Int64(Date().timeIntervalSince1970)
  sqlite3_bind_int64(statement, 1, Int64(creditCardId))
  sqlite3_bind_int64(statement, 2, Int64(closingDate))
  sqlite3_bind_int64(statement, 3, Int64(dueDate))
  sqlite3_bind_int64(statement, 4, Int64(totalAmount))
  sqlite3_bind_text(statement, 5, userId, -1, SQLITE_TRANSIENT)
  sqlite3_bind_int64(statement, 6, now)
  sqlite3_bind_int64(statement, 7, now)

  guard sqlite3_step(statement) == SQLITE_DONE else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.stepFailed(message: msg)
  }
  return Int(sqlite3_last_insert_rowid(db))
}

func getStatements(creditCardId: Int) throws -> [(id: Int, creditCardId: Int, closingDate: Int, dueDate: Int, totalAmount: Int, isPaid: Bool, paidDate: Int?, paidAmount: Int?, userId: String, createdAt: Int, updatedAt: Int)] {
  guard isInitialized else { return [] }
  let query = "SELECT id, credit_card_id, closing_date, due_date, total_amount, is_paid, paid_date, paid_amount, user_id, created_at, updated_at FROM CreditCardStatements WHERE credit_card_id = ? ORDER BY due_date DESC;"
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }
  sqlite3_bind_int64(statement, 1, Int64(creditCardId))

  var results: [(id: Int, creditCardId: Int, closingDate: Int, dueDate: Int, totalAmount: Int, isPaid: Bool, paidDate: Int?, paidAmount: Int?, userId: String, createdAt: Int, updatedAt: Int)] = []
  while sqlite3_step(statement) == SQLITE_ROW {
    results.append((
      Int(sqlite3_column_int64(statement, 0)),
      Int(sqlite3_column_int64(statement, 1)),
      Int(sqlite3_column_int64(statement, 2)),
      Int(sqlite3_column_int64(statement, 3)),
      Int(sqlite3_column_int64(statement, 4)),
      sqlite3_column_int(statement, 5) == 1,
      sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 6)),
      sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 7)),
      String(cString: sqlite3_column_text(statement, 8)),
      Int(sqlite3_column_int64(statement, 9)),
      Int(sqlite3_column_int64(statement, 10))
    ))
  }
  return results
}

func findStatement(creditCardId: Int, closingDate: Int) throws -> Int? {
  guard isInitialized else { return nil }
  let query = "SELECT id FROM CreditCardStatements WHERE credit_card_id = ? AND closing_date = ?;"
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }
  sqlite3_bind_int64(statement, 1, Int64(creditCardId))
  sqlite3_bind_int64(statement, 2, Int64(closingDate))
  guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
  return Int(sqlite3_column_int64(statement, 0))
}

func updateStatementTotal(statementId: Int, totalAmount: Int) throws {
  guard isInitialized else { return }
  let query = "UPDATE CreditCardStatements SET total_amount = ?, updated_at = ? WHERE id = ?;"
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }
  sqlite3_bind_int64(statement, 1, Int64(totalAmount))
  sqlite3_bind_int64(statement, 2, Int64(Date().timeIntervalSince1970))
  sqlite3_bind_int64(statement, 3, Int64(statementId))
  guard sqlite3_step(statement) == SQLITE_DONE else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.stepFailed(message: msg)
  }
}

func markStatementAsPaid(statementId: Int, paidAmount: Int?, paidDate: Int) throws {
  guard isInitialized else { return }
  let query = "UPDATE CreditCardStatements SET is_paid = 1, paid_amount = ?, paid_date = ?, updated_at = ? WHERE id = ?;"
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }
  if let amount = paidAmount { sqlite3_bind_int64(statement, 1, Int64(amount)) } else { sqlite3_bind_null(statement, 1) }
  sqlite3_bind_int64(statement, 2, Int64(paidDate))
  sqlite3_bind_int64(statement, 3, Int64(Date().timeIntervalSince1970))
  sqlite3_bind_int64(statement, 4, Int64(statementId))
  guard sqlite3_step(statement) == SQLITE_DONE else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.stepFailed(message: msg)
  }
}

func getTransactionSumForStatement(statementId: Int) throws -> Int {
  guard isInitialized else { return 0 }
  let query = "SELECT COALESCE(SUM(amount), 0) FROM Transactions WHERE statement_id = ? AND is_credit_card_statement = 0;"
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }
  sqlite3_bind_int64(statement, 1, Int64(statementId))
  guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
  return Int(sqlite3_column_int64(statement, 0))
}
```

**BUILD & VERIFY:** App runs. Dashboard works normally. Check console for no migration errors.

---

## Step 1.4 — Extend Transaction Model

**EDIT FILE:** `Finova/Sources/Core/Repositories/TransactionRepository/TransactionData.swift`

Add 3 fields to `TransactionData`:

```swift
struct TransactionData<C, T>: Codable where C: Codable, T: Codable {
  let id: Int?
  let title: String
  let amount: Int
  let dateTimestamp: Int
  let budgetMonthDate: Int
  let isRecurring: Bool?
  let hasInstallments: Bool?
  let parentTransactionId: Int?
  let installmentNumber: Int?
  let totalInstallments: Int?
  let originalAmount: Int?

  // NEW: Credit card fields
  let creditCardId: Int?
  let statementId: Int?
  let isCreditCardStatement: Bool?

  let category: C
  let type: T
}
```

**EDIT FILE:** `Finova/Sources/Core/Repositories/TransactionRepository/TransactionModel.swift`

Add to `Transaction`:
```swift
var creditCardId: Int? { data.creditCardId }
var statementId: Int? { data.statementId }
var isCreditCardStatement: Bool? { data.isCreditCardStatement }
```

Update `TransactionModel.init` to accept the 3 new fields:
```swift
init(
  id: Int? = nil,
  title: String,
  category: String,
  amount: Int,
  type: String,
  dateTimestamp: Int,
  budgetMonthDate: Int,
  isRecurring: Bool? = nil,
  hasInstallments: Bool? = nil,
  parentTransactionId: Int? = nil,
  originalAmount: Int? = nil,
  installmentNumber: Int? = nil,
  totalInstallments: Int? = nil,
  creditCardId: Int? = nil,
  statementId: Int? = nil,
  isCreditCardStatement: Bool? = nil
) {
  self.data = DBTransactionData(
    id: id,
    title: title,
    amount: amount,
    dateTimestamp: dateTimestamp,
    budgetMonthDate: budgetMonthDate,
    isRecurring: isRecurring,
    hasInstallments: hasInstallments,
    parentTransactionId: parentTransactionId,
    installmentNumber: installmentNumber,
    totalInstallments: totalInstallments,
    originalAmount: originalAmount,
    creditCardId: creditCardId,
    statementId: statementId,
    isCreditCardStatement: isCreditCardStatement,
    category: category,
    type: type
  )
}
```

Update `UITransactionData.init(from db:)` to pass through the new fields:
```swift
self = .init(
  id: db.id,
  title: db.title,
  amount: db.amount,
  dateTimestamp: db.dateTimestamp,
  budgetMonthDate: db.budgetMonthDate,
  isRecurring: db.isRecurring,
  hasInstallments: db.hasInstallments,
  parentTransactionId: db.parentTransactionId,
  installmentNumber: db.installmentNumber,
  totalInstallments: db.totalInstallments,
  originalAmount: db.originalAmount,
  creditCardId: db.creditCardId,
  statementId: db.statementId,
  isCreditCardStatement: db.isCreditCardStatement,
  category: finalCategory,
  type: finalType
)
```

Update `Transaction.CodingKeys` and `init(from decoder:)` and `encode(to:)` to handle the 3 new fields.

Update **all** `DBTransactionData(...)` construction sites in `DBHelper.swift` (the `getTransactions`, `executeTransactionQuery`, `parseTransactionFromStatement` methods) to include:
```swift
creditCardId: sqlite3_column_type(statement, OFFSET) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, OFFSET)),
statementId: sqlite3_column_type(statement, OFFSET+1) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, OFFSET+1)),
isCreditCardStatement: sqlite3_column_type(statement, OFFSET+2) == SQLITE_NULL ? nil : (sqlite3_column_int(statement, OFFSET+2) == 1),
```

And update the SELECT queries to include `credit_card_id, statement_id, is_credit_card_statement`.

Update `insertTransaction` to bind the 3 new columns.
Update `updateTransaction` to set the 3 new columns.

> This is a large but mechanical change. Every SELECT must include the new columns and every INSERT/UPDATE must bind them.

**BUILD & VERIFY:** App compiles. Existing transactions still work (new fields default to nil/0).

---

## Step 1.5 — CreditCardRepository

**NEW FILE:** `Finova/Sources/Core/Repositories/CreditCardRepository.swift`

```swift
//
//  CreditCardRepository.swift
//  Finova
//

import Foundation

class CreditCardRepository {

  func insertCard(_ card: CreditCard) -> Int? {
    do {
      let id = try DBHelper.shared.insertCreditCard(
        name: card.name,
        lastFourDigits: card.lastFourDigits,
        cardBrand: card.cardBrand.rawValue,
        closingDay: card.closingDay,
        dueDay: card.dueDay,
        creditLimit: card.creditLimit,
        cardColor: card.cardColor.rawValue,
        userId: card.userId
      )
      return id > 0 ? id : nil
    } catch {
      logError("Failed to insert credit card: \(error)")
      return nil
    }
  }

  func fetchAllCards(userId: String) -> [CreditCard] {
    do {
      let rows = try DBHelper.shared.getCreditCards(userId: userId)
      return rows.map { row in
        CreditCard(
          id: row.id,
          name: row.name,
          lastFourDigits: row.lastFourDigits,
          cardBrand: CardBrand(rawValue: row.cardBrand) ?? .other,
          closingDay: row.closingDay,
          dueDay: row.dueDay,
          creditLimit: row.creditLimit,
          cardColor: CardColor(rawValue: row.cardColor) ?? .blue,
          userId: userId,
          isDeleted: row.isDeleted,
          createdAt: Date(timeIntervalSince1970: TimeInterval(row.createdAt)),
          updatedAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt))
        )
      }
    } catch {
      logError("Failed to fetch credit cards: \(error)")
      return []
    }
  }

  func fetchCard(byId id: Int) -> CreditCard? {
    do {
      guard let row = try DBHelper.shared.getCreditCard(id: id) else { return nil }
      return CreditCard(
        id: row.id,
        name: row.name,
        lastFourDigits: row.lastFourDigits,
        cardBrand: CardBrand(rawValue: row.cardBrand) ?? .other,
        closingDay: row.closingDay,
        dueDay: row.dueDay,
        creditLimit: row.creditLimit,
        cardColor: CardColor(rawValue: row.cardColor) ?? .blue,
        userId: row.userId,
        isDeleted: row.isDeleted,
        createdAt: Date(timeIntervalSince1970: TimeInterval(row.createdAt)),
        updatedAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt))
      )
    } catch {
      logError("Failed to fetch credit card: \(error)")
      return nil
    }
  }

  func updateCard(_ card: CreditCard) -> Bool {
    guard let id = card.id else { return false }
    do {
      try DBHelper.shared.updateCreditCard(
        id: id, name: card.name, lastFourDigits: card.lastFourDigits,
        cardBrand: card.cardBrand.rawValue, closingDay: card.closingDay,
        dueDay: card.dueDay, creditLimit: card.creditLimit,
        cardColor: card.cardColor.rawValue
      )
      return true
    } catch {
      logError("Failed to update credit card: \(error)")
      return false
    }
  }

  func deleteCard(id: Int) -> Bool {
    do {
      try DBHelper.shared.softDeleteCreditCard(id: id)
      return true
    } catch {
      logError("Failed to delete credit card: \(error)")
      return false
    }
  }
}
```

**BUILD & VERIFY:** Compiles.

---

## Step 1.6 — StatementRepository

**NEW FILE:** `Finova/Sources/Core/Repositories/StatementRepository.swift`

```swift
//
//  StatementRepository.swift
//  Finova
//

import Foundation

class StatementRepository {

  func insertStatement(_ stmt: CreditCardStatement) -> Int? {
    do {
      let id = try DBHelper.shared.insertStatement(
        creditCardId: stmt.creditCardId,
        closingDate: Int(stmt.closingDate.timeIntervalSince1970),
        dueDate: Int(stmt.dueDate.timeIntervalSince1970),
        totalAmount: stmt.totalAmount,
        userId: stmt.userId
      )
      return id > 0 ? id : nil
    } catch {
      logError("Failed to insert statement: \(error)")
      return nil
    }
  }

  func fetchStatements(forCardId cardId: Int) -> [CreditCardStatement] {
    do {
      let rows = try DBHelper.shared.getStatements(creditCardId: cardId)
      return rows.map { row in
        CreditCardStatement(
          id: row.id,
          creditCardId: row.creditCardId,
          closingDate: Date(timeIntervalSince1970: TimeInterval(row.closingDate)),
          dueDate: Date(timeIntervalSince1970: TimeInterval(row.dueDate)),
          totalAmount: row.totalAmount,
          isPaid: row.isPaid,
          paidDate: row.paidDate.map { Date(timeIntervalSince1970: TimeInterval($0)) },
          paidAmount: row.paidAmount,
          userId: row.userId,
          createdAt: Date(timeIntervalSince1970: TimeInterval(row.createdAt)),
          updatedAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt))
        )
      }
    } catch {
      logError("Failed to fetch statements: \(error)")
      return []
    }
  }

  func findStatement(creditCardId: Int, closingDate: Date) -> Int? {
    do {
      return try DBHelper.shared.findStatement(
        creditCardId: creditCardId,
        closingDate: Int(closingDate.timeIntervalSince1970)
      )
    } catch {
      logError("Failed to find statement: \(error)")
      return nil
    }
  }

  func recalculateTotal(statementId: Int) {
    do {
      let total = try DBHelper.shared.getTransactionSumForStatement(statementId: statementId)
      try DBHelper.shared.updateStatementTotal(statementId: statementId, totalAmount: total)
    } catch {
      logError("Failed to recalculate statement total: \(error)")
    }
  }

  func markAsPaid(statementId: Int, paidAmount: Int?, paidDate: Date) -> Bool {
    do {
      try DBHelper.shared.markStatementAsPaid(
        statementId: statementId,
        paidAmount: paidAmount,
        paidDate: Int(paidDate.timeIntervalSince1970)
      )
      return true
    } catch {
      logError("Failed to mark statement as paid: \(error)")
      return false
    }
  }
}
```

**BUILD & VERIFY:** Compiles.

---

## Step 1.7 — CreditCardService

**NEW FILE:** `Finova/Sources/Core/Services/CreditCardService.swift`

```swift
//
//  CreditCardService.swift
//  Finova
//

import Foundation

class CreditCardService {
  private let cardRepo = CreditCardRepository()
  private let stmtRepo = StatementRepository()

  /// Returns the closing date for a transaction on a given card.
  /// If transactionDay <= closingDay → current month closing.
  /// If transactionDay > closingDay → next month closing.
  func calculateClosingDate(card: CreditCard, transactionDate: Date) -> Date {
    let calendar = Calendar.current
    let day = calendar.component(.day, from: transactionDate)
    let month = calendar.component(.month, from: transactionDate)
    let year = calendar.component(.year, from: transactionDate)

    if day <= card.closingDay {
      // Current month statement
      let closingDay = min(card.closingDay, daysInMonth(month: month, year: year))
      return calendar.date(from: DateComponents(year: year, month: month, day: closingDay))!
    } else {
      // Next month statement
      var nextMonth = month + 1
      var nextYear = year
      if nextMonth > 12 { nextMonth = 1; nextYear += 1 }
      let closingDay = min(card.closingDay, daysInMonth(month: nextMonth, year: nextYear))
      return calendar.date(from: DateComponents(year: nextYear, month: nextMonth, day: closingDay))!
    }
  }

  /// Calculates due date from a closing date.
  func calculateDueDate(closingDate: Date, card: CreditCard) -> Date {
    let calendar = Calendar.current
    let closingDay = calendar.component(.day, from: closingDate)
    let closingMonth = calendar.component(.month, from: closingDate)
    let closingYear = calendar.component(.year, from: closingDate)

    if card.dueDay > closingDay {
      // Due date same month as closing
      let dueDay = min(card.dueDay, daysInMonth(month: closingMonth, year: closingYear))
      return calendar.date(from: DateComponents(year: closingYear, month: closingMonth, day: dueDay))!
    } else {
      // Due date next month after closing
      var dueMonth = closingMonth + 1
      var dueYear = closingYear
      if dueMonth > 12 { dueMonth = 1; dueYear += 1 }
      let dueDay = min(card.dueDay, daysInMonth(month: dueMonth, year: dueYear))
      return calendar.date(from: DateComponents(year: dueYear, month: dueMonth, day: dueDay))!
    }
  }

  /// Gets or creates a statement for a transaction on a given card/date.
  func getOrCreateStatement(for card: CreditCard, transactionDate: Date, userId: String) -> CreditCardStatement? {
    let closingDate = calculateClosingDate(card: card, transactionDate: transactionDate)
    let dueDate = calculateDueDate(closingDate: closingDate, card: card)

    // Check if statement already exists
    if let existingId = stmtRepo.findStatement(creditCardId: card.id!, closingDate: closingDate) {
      let statements = stmtRepo.fetchStatements(forCardId: card.id!)
      return statements.first(where: { $0.id == existingId })
    }

    // Create new statement
    let newStatement = CreditCardStatement(
      id: nil,
      creditCardId: card.id!,
      closingDate: closingDate,
      dueDate: dueDate,
      totalAmount: 0,
      isPaid: false,
      paidDate: nil,
      paidAmount: nil,
      userId: userId,
      createdAt: Date(),
      updatedAt: Date()
    )

    guard let newId = stmtRepo.insertStatement(newStatement) else { return nil }

    var created = newStatement
    created.id = newId
    return created
  }

  func recalculateStatementTotal(statementId: Int) {
    stmtRepo.recalculateTotal(statementId: statementId)
  }

  private func daysInMonth(month: Int, year: Int) -> Int {
    let calendar = Calendar.current
    let components = DateComponents(year: year, month: month)
    guard let date = calendar.date(from: components),
          let range = calendar.range(of: .day, in: .month, for: date)
    else { return 28 }
    return range.count
  }
}
```

**BUILD & VERIFY:** Compiles. Phase 1 complete. App runs identically.

---

# PHASE 2 — Credit Card Management (Settings Flow)

---

## Step 2.1a — Add "Financial" section to SettingsView

**EDIT FILE:** `Finova/Sources/Scenes/Settings/SettingsView.swift`

Add these properties after the Preferences section properties (after `currencyChevron`):

```swift
// Financial Section
private let financialHeaderView = createSectionHeader(title: "settings.section.financial".localized)

private let creditCardsContainer: UIView = {
  let container = createSettingContainer()
  container.isUserInteractionEnabled = true
  return container
}()
private let creditCardsIconView = createIconView(imageName: "creditcard.fill")
private let creditCardsLabel = createSettingLabel(text: "settings.creditCards.title".localized)
private let creditCardsChevron = createChevronView()
```

In `setupSections()`, insert the Financial section **between** Preferences and Notifications:

```swift
// Preferences section
contentStackView.addArrangedSubview(preferencesHeaderView)
setupCurrencyContainer()
contentStackView.addArrangedSubview(currencyContainer)

// Financial section (NEW)
contentStackView.addArrangedSubview(financialHeaderView)
setupCreditCardsContainer()
contentStackView.addArrangedSubview(creditCardsContainer)

// Notifications section
contentStackView.addArrangedSubview(notificationsHeaderView)
setupNotificationsContainer()
contentStackView.addArrangedSubview(notificationsContainer)

// About section
contentStackView.addArrangedSubview(aboutHeaderView)
setupVersionContainer()
contentStackView.addArrangedSubview(versionContainer)

// Account Section
contentStackView.addArrangedSubview(accountHeaderView)
setupDeleteAccountContainer()
contentStackView.addArrangedSubview(deleteAccountContainer)
setupLogoutContainer()
contentStackView.addArrangedSubview(logoutContainer)
```

Add the setup method:

```swift
private func setupCreditCardsContainer() {
  creditCardsContainer.addSubview(creditCardsIconView)
  creditCardsContainer.addSubview(creditCardsLabel)
  creditCardsContainer.addSubview(creditCardsChevron)

  NSLayoutConstraint.activate([
    creditCardsIconView.leadingAnchor.constraint(equalTo: creditCardsContainer.leadingAnchor, constant: Metrics.spacing4),
    creditCardsIconView.centerYAnchor.constraint(equalTo: creditCardsContainer.centerYAnchor),

    creditCardsLabel.leadingAnchor.constraint(equalTo: creditCardsIconView.trailingAnchor, constant: Metrics.spacing3),
    creditCardsLabel.centerYAnchor.constraint(equalTo: creditCardsContainer.centerYAnchor),

    creditCardsChevron.trailingAnchor.constraint(equalTo: creditCardsContainer.trailingAnchor, constant: -Metrics.spacing4),
    creditCardsChevron.centerYAnchor.constraint(equalTo: creditCardsContainer.centerYAnchor),
  ])
}
```

In `setupActions()`, add:

```swift
let creditCardsTap = UITapGestureRecognizer(target: self, action: #selector(creditCardsTapped))
creditCardsContainer.addGestureRecognizer(creditCardsTap)
```

Add the action:

```swift
@objc
private func creditCardsTapped() {
  delegate?.didTapCreditCards()
}
```

**EDIT FILE:** `Finova/Sources/Scenes/Settings/SettingsViewDelegate.swift`

Add:

```swift
func didTapCreditCards()
```

**BUILD & VERIFY:** Go to Settings → see "FINANCIAL" section with "Credit Cards" row between Preferences and Notifications. Tapping crashes (delegate not wired yet).

---

## Step 2.1b — Wire navigation

**EDIT FILE:** `Finova/Sources/Scenes/Settings/SettingsFlowDelegate.swift`

```swift
public protocol SettingsFlowDelegate: AnyObject {
  func dismissSettings()
  func logout()
  func navigateToNotificationSettings()
  func navigateToCreditCards()  // NEW
}
```

**EDIT FILE:** `Finova/Sources/Scenes/Settings/SettingsViewController.swift`

In the `SettingsViewDelegate` extension, add:

```swift
func didTapCreditCards() {
  flowDelegate?.navigateToCreditCards()
}
```

**BUILD & VERIFY:** Compiles. Tapping "Credit Cards" row will crash at runtime because `AppFlowController` doesn't implement `navigateToCreditCards()` yet. That's OK — next step fixes it.

---

## Step 2.2a — CreditCards FlowDelegate + ViewDelegate

**NEW FILE:** `Finova/Sources/Scenes/CreditCards/CreditCardsFlowDelegate.swift`

```swift
//
//  CreditCardsFlowDelegate.swift
//  Finova
//

public protocol CreditCardsFlowDelegate: AnyObject {
  func dismissCreditCards()
  func navigateToAddCreditCard()
  func navigateToEditCreditCard(_ card: CreditCard)
}
```

**NEW FILE:** `Finova/Sources/Scenes/CreditCards/CreditCardsViewDelegate.swift`

```swift
//
//  CreditCardsViewDelegate.swift
//  Finova
//

protocol CreditCardsViewDelegate: AnyObject {
  func didTapBack()
  func didTapAdd()
  func didTapCard(_ card: CreditCard)
  func didTapDeleteCard(_ card: CreditCard)
}
```

---

## Step 2.2b — CreditCardsView (header + empty state)

**NEW FILE:** `Finova/Sources/Scenes/CreditCards/CreditCardsView.swift`

```swift
//
//  CreditCardsView.swift
//  Finova
//

import UIKit

final class CreditCardsView: UIView {
  weak var delegate: CreditCardsViewDelegate?

  // MARK: - Header
  private let headerContainerView: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray100
    view.translatesAutoresizingMaskIntoConstraints = false
    view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight - 12).isActive = true
    return view
  }()

  private let headerItemsView: UIView = {
    let view = UIView()
    view.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: Metrics.spacing4, leading: Metrics.spacing5,
      bottom: Metrics.spacing5, trailing: Metrics.spacing5)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let backButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
    button.imageView?.contentMode = .scaleAspectFit
    button.translatesAutoresizingMaskIntoConstraints = false
    if #available(iOS 26.0, *) { button.tintColor = Colors.gray700 }
    else { button.tintColor = Colors.gray500 }
    return button
  }()

  private lazy var backButtonGlassContainer: UIView = {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    return container
  }()

  private let headerTitleLabel: UILabel = {
    let label = UILabel()
    label.fontStyle = Fonts.titleSM
    label.text = "creditCards.header.title".localized
    label.applyStyle()
    label.textColor = Colors.gray700
    label.textAlignment = .left
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let addButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "plus")?.withRenderingMode(.alwaysTemplate), for: .normal)
    button.tintColor = Colors.mainMagenta
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }()

  // MARK: - Content
  private let scrollView: UIScrollView = {
    let sv = UIScrollView()
    sv.showsVerticalScrollIndicator = false
    sv.translatesAutoresizingMaskIntoConstraints = false
    return sv
  }()

  let contentStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = Metrics.spacing4
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  // MARK: - Empty State
  private let emptyStateView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let emptyTitleLabel: UILabel = {
    let label = UILabel()
    label.text = "creditCards.empty.title".localized
    label.font = Fonts.titleMD.font
    label.textColor = Colors.gray500
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let emptySubtitleLabel: UILabel = {
    let label = UILabel()
    label.text = "creditCards.empty.subtitle".localized
    label.font = Fonts.textSM.font
    label.textColor = Colors.gray400
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  // MARK: - Init
  override init(frame: CGRect) {
    super.init(frame: .zero)
    setupView()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Setup
  private func setupView() {
    backgroundColor = Colors.gray200

    addSubview(scrollView)
    scrollView.addSubview(headerContainerView)
    headerContainerView.addSubview(headerItemsView)
    headerItemsView.addSubview(backButtonGlassContainer)
    backButtonGlassContainer.addSubview(backButton)
    setupBackButtonGlassEffect()
    headerItemsView.addSubview(headerTitleLabel)
    headerItemsView.addSubview(addButton)

    scrollView.addSubview(contentStackView)

    // Empty state
    emptyStateView.addSubview(emptyTitleLabel)
    emptyStateView.addSubview(emptySubtitleLabel)

    NSLayoutConstraint.activate([
      emptyTitleLabel.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
      emptyTitleLabel.topAnchor.constraint(equalTo: emptyStateView.topAnchor, constant: Metrics.spacing12),
      emptySubtitleLabel.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
      emptySubtitleLabel.topAnchor.constraint(equalTo: emptyTitleLabel.bottomAnchor, constant: Metrics.spacing2),
      emptySubtitleLabel.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor),
    ])

    contentStackView.addArrangedSubview(emptyStateView)

    setupConstraints()
    setupActions()
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

      headerContainerView.topAnchor.constraint(equalTo: topAnchor),
      headerContainerView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      headerContainerView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),

      headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
      headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
      headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

      backButtonGlassContainer.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
      backButtonGlassContainer.leadingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
      backButtonGlassContainer.widthAnchor.constraint(equalToConstant: 36),
      backButtonGlassContainer.heightAnchor.constraint(equalToConstant: 36),

      backButton.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
      backButton.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
      backButton.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
      backButton.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),

      headerTitleLabel.leadingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
      headerTitleLabel.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),

      addButton.trailingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.trailingAnchor),
      addButton.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),
      addButton.widthAnchor.constraint(equalToConstant: 36),
      addButton.heightAnchor.constraint(equalToConstant: 36),

      contentStackView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing4),
      contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Metrics.spacing4),
      contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing4),
      contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Metrics.spacing4),
      contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * Metrics.spacing4),
    ])
  }

  private func setupBackButtonGlassEffect() {
    if #available(iOS 26.0, *) {
      let glassEffect = UIGlassEffect()
      glassEffect.isInteractive = true
      let glassView = UIVisualEffectView(effect: glassEffect)
      glassView.translatesAutoresizingMaskIntoConstraints = false
      backButtonGlassContainer.insertSubview(glassView, at: 0)
      backButtonGlassContainer.layer.cornerRadius = 18
      backButtonGlassContainer.clipsToBounds = true
      NSLayoutConstraint.activate([
        glassView.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
        glassView.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
        glassView.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
        glassView.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),
      ])
    }
  }

  private func setupActions() {
    backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
    let backTapGesture = UITapGestureRecognizer(target: self, action: #selector(backTapped))
    backButtonGlassContainer.addGestureRecognizer(backTapGesture)
    addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
  }

  @objc private func backTapped() { delegate?.didTapBack() }
  @objc private func addTapped() { delegate?.didTapAdd() }

  // MARK: - Public

  func showEmptyState(_ show: Bool) {
    emptyStateView.isHidden = !show
  }

  func reloadCards(_ cards: [CreditCard]) {
    // Remove old card cells (keep empty state)
    contentStackView.arrangedSubviews.forEach { view in
      if view !== emptyStateView {
        contentStackView.removeArrangedSubview(view)
        view.removeFromSuperview()
      }
    }

    showEmptyState(cards.isEmpty)

    for card in cards {
      let cell = CreditCardCell()
      cell.configure(with: card)
      cell.onTap = { [weak self] in self?.delegate?.didTapCard(card) }
      cell.onDelete = { [weak self] in self?.delegate?.didTapDeleteCard(card) }
      contentStackView.addArrangedSubview(cell)
    }
  }
}
```

---

## Step 2.2c — CreditCardsViewController

**NEW FILE:** `Finova/Sources/Scenes/CreditCards/CreditCardsViewController.swift`

```swift
//
//  CreditCardsViewController.swift
//  Finova
//

import UIKit

final class CreditCardsViewController: UIViewController {
  let contentView: CreditCardsView
  private let viewModel: CreditCardsViewModel
  weak var flowDelegate: CreditCardsFlowDelegate?

  init(contentView: CreditCardsView, viewModel: CreditCardsViewModel, flowDelegate: CreditCardsFlowDelegate) {
    self.contentView = contentView
    self.viewModel = viewModel
    self.flowDelegate = flowDelegate
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setup()
    viewModel.loadCards()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    viewModel.loadCards()
  }

  private func setup() {
    view.addSubview(contentView)
    setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
    contentView.delegate = self
    viewModel.delegate = self
  }
}

extension CreditCardsViewController: CreditCardsViewDelegate {
  func didTapBack() {
    flowDelegate?.dismissCreditCards()
  }

  func didTapAdd() {
    flowDelegate?.navigateToAddCreditCard()
  }

  func didTapCard(_ card: CreditCard) {
    flowDelegate?.navigateToEditCreditCard(card)
  }

  func didTapDeleteCard(_ card: CreditCard) {
    showConfirmation(
      title: "creditCards.delete.title".localized,
      message: "creditCards.delete.message".localized,
      onOk: { [weak self] in
        self?.viewModel.deleteCard(card)
      }
    )
  }
}

extension CreditCardsViewController: CreditCardsViewModelDelegate {
  func didLoadCards(_ cards: [CreditCard]) {
    contentView.reloadCards(cards)
  }
}
```

---

## Step 2.2d — CreditCardsViewModel

**NEW FILE:** `Finova/Sources/Scenes/CreditCards/CreditCardsViewModel.swift`

```swift
//
//  CreditCardsViewModel.swift
//  Finova
//

import Foundation

protocol CreditCardsViewModelDelegate: AnyObject {
  func didLoadCards(_ cards: [CreditCard])
}

final class CreditCardsViewModel {
  weak var delegate: CreditCardsViewModelDelegate?
  private let cardRepo = CreditCardRepository()
  private(set) var cards: [CreditCard] = []

  func loadCards() {
    guard let uid = AuthenticationManager.shared.currentUser?.uid else { return }
    cards = cardRepo.fetchAllCards(userId: uid)
    delegate?.didLoadCards(cards)
  }

  func deleteCard(_ card: CreditCard) {
    guard let id = card.id else { return }
    if cardRepo.deleteCard(id: id) {
      loadCards()
    }
  }
}
```

---

## Step 2.2e — CreditCardCell (basic)

**NEW FILE:** `Finova/Sources/Scenes/CreditCards/Views/CreditCardCell.swift`

```swift
//
//  CreditCardCell.swift
//  Finova
//

import UIKit

final class CreditCardCell: UIView {
  var onTap: (() -> Void)?
  var onDelete: (() -> Void)?

  private let cardPreview: UIView = {
    let view = UIView()
    view.layer.cornerRadius = CornerRadius.extraLarge
    view.clipsToBounds = true
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let cardNameLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.titleSM.font
    label.textColor = .white
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let lastFourLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textSM.font
    label.textColor = UIColor.white.withAlphaComponent(0.8)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let brandLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textXS.font
    label.textColor = UIColor.white.withAlphaComponent(0.7)
    label.textAlignment = .right
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let infoLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray500
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    backgroundColor = Colors.gray100
    layer.cornerRadius = CornerRadius.extraLarge
    translatesAutoresizingMaskIntoConstraints = false

    addSubview(cardPreview)
    cardPreview.addSubview(cardNameLabel)
    cardPreview.addSubview(lastFourLabel)
    cardPreview.addSubview(brandLabel)
    addSubview(infoLabel)

    NSLayoutConstraint.activate([
      cardPreview.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.spacing3),
      cardPreview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing3),
      cardPreview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing3),
      cardPreview.heightAnchor.constraint(equalToConstant: 100),

      cardNameLabel.topAnchor.constraint(equalTo: cardPreview.topAnchor, constant: Metrics.spacing4),
      cardNameLabel.leadingAnchor.constraint(equalTo: cardPreview.leadingAnchor, constant: Metrics.spacing4),

      lastFourLabel.bottomAnchor.constraint(equalTo: cardPreview.bottomAnchor, constant: -Metrics.spacing4),
      lastFourLabel.leadingAnchor.constraint(equalTo: cardPreview.leadingAnchor, constant: Metrics.spacing4),

      brandLabel.bottomAnchor.constraint(equalTo: cardPreview.bottomAnchor, constant: -Metrics.spacing4),
      brandLabel.trailingAnchor.constraint(equalTo: cardPreview.trailingAnchor, constant: -Metrics.spacing4),

      infoLabel.topAnchor.constraint(equalTo: cardPreview.bottomAnchor, constant: Metrics.spacing3),
      infoLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
      infoLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
      infoLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.spacing3),
    ])

    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
    addGestureRecognizer(tapGesture)

    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
    addGestureRecognizer(longPress)
  }

  func configure(with card: CreditCard) {
    cardNameLabel.text = card.name.uppercased()
    lastFourLabel.text = "**** **** **** \(card.lastFourDigits)"
    brandLabel.text = card.cardBrand.displayName

    // Gradient background
    let gradient = CAGradientLayer()
    gradient.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width - 2 * (Metrics.spacing4 + Metrics.spacing3), height: 100)
    gradient.colors = [card.cardColor.startColor.cgColor, card.cardColor.endColor.cgColor]
    gradient.startPoint = CGPoint(x: 0, y: 0)
    gradient.endPoint = CGPoint(x: 1, y: 1)
    gradient.cornerRadius = CornerRadius.extraLarge
    cardPreview.layer.sublayers?.removeAll(where: { $0 is CAGradientLayer })
    cardPreview.layer.insertSublayer(gradient, at: 0)

    let closesText = String(format: "creditCards.cell.closes".localized, "\(card.closingDay)")
    let dueText = String(format: "creditCards.cell.due".localized, "\(card.dueDay)")
    var info = "\(closesText) · \(dueText)"
    if let limit = card.creditLimit {
      let limitText = String(format: "creditCards.cell.limit".localized, CurrencyFormatter.shared.format(cents: limit))
      info += " · \(limitText)"
    }
    infoLabel.text = info
  }

  @objc private func handleTap() { onTap?() }
  @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
    if gesture.state == .began { onDelete?() }
  }
}
```

---

## Step 2.2f — Wire Factory + AppFlowController

**EDIT FILE:** `Finova/Sources/Core/Factories/ViewControllersFactory/ViewControllersFactoryProtocol.swift`

Add:
```swift
func makeCreditCardsViewController(flowDelegate: CreditCardsFlowDelegate) -> CreditCardsViewController
```

**EDIT FILE:** `Finova/Sources/Core/Factories/ViewControllersFactory/ViewControllersFactory.swift`

Add:
```swift
func makeCreditCardsViewController(flowDelegate: CreditCardsFlowDelegate) -> CreditCardsViewController {
  let contentView = CreditCardsView()
  let viewModel = CreditCardsViewModel()
  let viewController = CreditCardsViewController(
    contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
  return viewController
}
```

**EDIT FILE:** `Finova/AppFlowController.swift`

In the `DashboardFlowDelegate, SettingsFlowDelegate` extension, add:

```swift
func navigateToCreditCards() {
  let viewController = viewControllersFactory.makeCreditCardsViewController(flowDelegate: self)
  navigationController?.pushViewController(viewController, animated: true)
}
```

Add `CreditCardsFlowDelegate` conformance:

```swift
// MARK: - Credit Cards Flow
extension AppFlowController: CreditCardsFlowDelegate {
  func dismissCreditCards() {
    navigationController?.popViewController(animated: true)
  }

  func navigateToAddCreditCard() {
    let viewController = viewControllersFactory.makeAddCreditCardViewController(flowDelegate: self)
    navigationController?.pushViewController(viewController, animated: true)
  }

  func navigateToEditCreditCard(_ card: CreditCard) {
    let viewController = viewControllersFactory.makeAddCreditCardViewController(flowDelegate: self, cardToEdit: card)
    navigationController?.pushViewController(viewController, animated: true)
  }
}
```

**BUILD & VERIFY:** Settings → Credit Cards → Empty state screen with back button + "+" button. Back navigates to Settings.

---

## Step 2.3 — Add Credit Card Screen

**NEW FILE:** `Finova/Sources/Scenes/AddCreditCard/AddCreditCardFlowDelegate.swift`

```swift
//
//  AddCreditCardFlowDelegate.swift
//  Finova
//

public protocol AddCreditCardFlowDelegate: AnyObject {
  func dismissAddCreditCard()
  func didSaveCreditCard()
}
```

**NEW FILE:** `Finova/Sources/Scenes/AddCreditCard/AddCreditCardViewDelegate.swift`

```swift
//
//  AddCreditCardViewDelegate.swift
//  Finova
//

protocol AddCreditCardViewDelegate: AnyObject {
  func didTapBack()
  func didTapSave()
}
```

**NEW FILE:** `Finova/Sources/Scenes/AddCreditCard/AddCreditCardView.swift`

```swift
//
//  AddCreditCardView.swift
//  Finova
//

import UIKit

final class AddCreditCardView: UIView {
  weak var delegate: AddCreditCardViewDelegate?

  // MARK: - Header (same pattern as Settings/CreditCards)
  private let headerContainerView: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray100
    view.translatesAutoresizingMaskIntoConstraints = false
    view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight - 12).isActive = true
    return view
  }()

  private let headerItemsView: UIView = {
    let view = UIView()
    view.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: Metrics.spacing4, leading: Metrics.spacing5,
      bottom: Metrics.spacing5, trailing: Metrics.spacing5)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let backButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
    button.imageView?.contentMode = .scaleAspectFit
    button.translatesAutoresizingMaskIntoConstraints = false
    if #available(iOS 26.0, *) { button.tintColor = Colors.gray700 }
    else { button.tintColor = Colors.gray500 }
    return button
  }()

  private lazy var backButtonGlassContainer: UIView = {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    return container
  }()

  let headerTitleLabel: UILabel = {
    let label = UILabel()
    label.fontStyle = Fonts.titleSM
    label.text = "addCreditCard.header.title".localized
    label.applyStyle()
    label.textColor = Colors.gray700
    label.textAlignment = .left
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  // MARK: - Scroll + Form
  private let scrollView: UIScrollView = {
    let sv = UIScrollView()
    sv.showsVerticalScrollIndicator = false
    sv.translatesAutoresizingMaskIntoConstraints = false
    return sv
  }()

  private let formStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = Metrics.spacing5
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  // MARK: - Form Fields
  let nameInput = Input(placeholder: "addCreditCard.input.name.placeholder".localized)
  let lastFourInput = Input(type: .number, placeholder: "1234")
  let closingDayInput = Input(type: .picker(values: (1...28).map { String($0) }), placeholder: "15")
  let dueDayInput = Input(type: .picker(values: (1...28).map { String($0) }), placeholder: "22")
  let creditLimitInput = Input(type: .currency, placeholder: "0,00")

  // MARK: - Brand Selector
  let brandSelector: UISegmentedControl = {
    let brands = CardBrand.allCases.map { $0.displayName }
    let sc = UISegmentedControl(items: brands)
    sc.selectedSegmentIndex = 0
    sc.translatesAutoresizingMaskIntoConstraints = false
    return sc
  }()

  // MARK: - Color Selector
  let colorStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = Metrics.spacing3
    stack.distribution = .fillEqually
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  var selectedColor: CardColor = .blue
  private var colorButtons: [UIButton] = []

  // MARK: - Save Button
  let saveButton = Button(variant: .base, label: "addCreditCard.button.save".localized)

  // MARK: - Init
  override init(frame: CGRect) {
    super.init(frame: .zero)
    setupView()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Setup
  private func setupView() {
    backgroundColor = Colors.gray200

    addSubview(scrollView)
    scrollView.addSubview(headerContainerView)
    headerContainerView.addSubview(headerItemsView)
    headerItemsView.addSubview(backButtonGlassContainer)
    backButtonGlassContainer.addSubview(backButton)
    setupBackButtonGlassEffect()
    headerItemsView.addSubview(headerTitleLabel)

    scrollView.addSubview(formStackView)

    // Add labeled fields
    formStackView.addArrangedSubview(createLabeledField(label: "addCreditCard.input.name".localized, field: nameInput))
    formStackView.addArrangedSubview(createLabeledField(label: "addCreditCard.input.lastFourDigits".localized, field: lastFourInput, hint: "addCreditCard.input.lastFourDigits.hint".localized))
    formStackView.addArrangedSubview(createLabeledField(label: "addCreditCard.input.brand".localized, field: brandSelector))
    formStackView.addArrangedSubview(createLabeledField(label: "addCreditCard.input.closingDay".localized, field: closingDayInput, hint: "addCreditCard.input.closingDay.hint".localized))
    formStackView.addArrangedSubview(createLabeledField(label: "addCreditCard.input.dueDay".localized, field: dueDayInput, hint: "addCreditCard.input.dueDay.hint".localized))
    formStackView.addArrangedSubview(createLabeledField(label: "addCreditCard.input.creditLimit".localized, field: creditLimitInput))
    setupColorSelector()
    formStackView.addArrangedSubview(createLabeledField(label: "addCreditCard.input.color".localized, field: colorStackView))
    formStackView.addArrangedSubview(saveButton)

    setupConstraints()
    setupActions()
  }

  private func setupColorSelector() {
    for color in CardColor.allCases {
      let button = UIButton()
      button.backgroundColor = color.startColor
      button.layer.cornerRadius = 16
      button.clipsToBounds = true
      button.translatesAutoresizingMaskIntoConstraints = false
      button.heightAnchor.constraint(equalToConstant: 32).isActive = true
      button.widthAnchor.constraint(equalToConstant: 32).isActive = true
      button.tag = CardColor.allCases.firstIndex(of: color) ?? 0
      button.addTarget(self, action: #selector(colorSelected(_:)), for: .touchUpInside)
      if color == selectedColor {
        button.layer.borderWidth = 3
        button.layer.borderColor = Colors.mainMagenta.cgColor
      }
      colorButtons.append(button)
      colorStackView.addArrangedSubview(button)
    }
  }

  @objc private func colorSelected(_ sender: UIButton) {
    selectedColor = CardColor.allCases[sender.tag]
    colorButtons.forEach {
      $0.layer.borderWidth = 0
      $0.layer.borderColor = nil
    }
    sender.layer.borderWidth = 3
    sender.layer.borderColor = Colors.mainMagenta.cgColor
  }

  private func createLabeledField(label: String, field: UIView, hint: String? = nil) -> UIStackView {
    let titleLabel = UILabel()
    titleLabel.text = label
    titleLabel.font = Fonts.textSM.font
    titleLabel.textColor = Colors.gray600
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    var views: [UIView] = [titleLabel, field]

    if let hint = hint {
      let hintLabel = UILabel()
      hintLabel.text = hint
      hintLabel.font = Fonts.textXS.font
      hintLabel.textColor = Colors.gray400
      hintLabel.translatesAutoresizingMaskIntoConstraints = false
      views.append(hintLabel)
    }

    let stack = UIStackView(arrangedSubviews: views)
    stack.axis = .vertical
    stack.spacing = Metrics.spacing1
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

      headerContainerView.topAnchor.constraint(equalTo: topAnchor),
      headerContainerView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      headerContainerView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),

      headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
      headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
      headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

      backButtonGlassContainer.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
      backButtonGlassContainer.leadingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
      backButtonGlassContainer.widthAnchor.constraint(equalToConstant: 36),
      backButtonGlassContainer.heightAnchor.constraint(equalToConstant: 36),

      backButton.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
      backButton.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
      backButton.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
      backButton.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),

      headerTitleLabel.leadingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
      headerTitleLabel.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),

      formStackView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing5),
      formStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Metrics.spacing5),
      formStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing5),
      formStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Metrics.spacing5),
      formStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * Metrics.spacing5),
    ])
  }

  private func setupBackButtonGlassEffect() {
    if #available(iOS 26.0, *) {
      let glassEffect = UIGlassEffect()
      glassEffect.isInteractive = true
      let glassView = UIVisualEffectView(effect: glassEffect)
      glassView.translatesAutoresizingMaskIntoConstraints = false
      backButtonGlassContainer.insertSubview(glassView, at: 0)
      backButtonGlassContainer.layer.cornerRadius = 18
      backButtonGlassContainer.clipsToBounds = true
      NSLayoutConstraint.activate([
        glassView.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
        glassView.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
        glassView.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
        glassView.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),
      ])
    }
  }

  private func setupActions() {
    backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
    let backTapGesture = UITapGestureRecognizer(target: self, action: #selector(backTapped))
    backButtonGlassContainer.addGestureRecognizer(backTapGesture)
    saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
  }

  @objc private func backTapped() { delegate?.didTapBack() }
  @objc private func saveTapped() { delegate?.didTapSave() }

  // MARK: - Edit Mode
  func configureForEdit(_ card: CreditCard) {
    headerTitleLabel.text = "editCreditCard.header.title".localized
    saveButton.setTitle("editCreditCard.button.save".localized, for: .normal)

    nameInput.text = card.name
    lastFourInput.text = card.lastFourDigits
    closingDayInput.text = "\(card.closingDay)"
    dueDayInput.text = "\(card.dueDay)"
    if let limit = card.creditLimit {
      creditLimitInput.text = CurrencyFormatter.shared.format(cents: limit)
    }

    if let brandIndex = CardBrand.allCases.firstIndex(of: card.cardBrand) {
      brandSelector.selectedSegmentIndex = brandIndex
    }

    selectedColor = card.cardColor
    colorButtons.forEach { $0.layer.borderWidth = 0 }
    if let colorIndex = CardColor.allCases.firstIndex(of: card.cardColor),
       colorIndex < colorButtons.count {
      colorButtons[colorIndex].layer.borderWidth = 3
      colorButtons[colorIndex].layer.borderColor = Colors.mainMagenta.cgColor
    }
  }
}
```

**NEW FILE:** `Finova/Sources/Scenes/AddCreditCard/AddCreditCardViewModel.swift`

```swift
//
//  AddCreditCardViewModel.swift
//  Finova
//

import Foundation

final class AddCreditCardViewModel {
  private let cardRepo = CreditCardRepository()
  var cardToEdit: CreditCard?

  var isEditMode: Bool { cardToEdit != nil }

  func saveCard(
    name: String, lastFour: String, brandIndex: Int,
    closingDay: Int, dueDay: Int, creditLimit: Int?,
    cardColor: CardColor
  ) -> Bool {
    guard let uid = AuthenticationManager.shared.currentUser?.uid else { return false }
    guard !name.isEmpty, lastFour.count == 4, closingDay >= 1, closingDay <= 28, dueDay >= 1, dueDay <= 28 else { return false }

    let brand = CardBrand.allCases[brandIndex]

    if var existing = cardToEdit {
      existing.name = name
      existing.lastFourDigits = lastFour
      existing.cardBrand = brand
      existing.closingDay = closingDay
      existing.dueDay = dueDay
      existing.creditLimit = creditLimit
      existing.cardColor = cardColor
      return cardRepo.updateCard(existing)
    } else {
      let card = CreditCard(
        id: nil, name: name, lastFourDigits: lastFour,
        cardBrand: brand, closingDay: closingDay, dueDay: dueDay,
        creditLimit: creditLimit, cardColor: cardColor,
        userId: uid, isDeleted: false,
        createdAt: Date(), updatedAt: Date()
      )
      return cardRepo.insertCard(card) != nil
    }
  }
}
```

**NEW FILE:** `Finova/Sources/Scenes/AddCreditCard/AddCreditCardViewController.swift`

```swift
//
//  AddCreditCardViewController.swift
//  Finova
//

import UIKit

final class AddCreditCardViewController: UIViewController {
  let contentView: AddCreditCardView
  private let viewModel: AddCreditCardViewModel
  weak var flowDelegate: AddCreditCardFlowDelegate?

  init(contentView: AddCreditCardView, viewModel: AddCreditCardViewModel, flowDelegate: AddCreditCardFlowDelegate) {
    self.contentView = contentView
    self.viewModel = viewModel
    self.flowDelegate = flowDelegate
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setup()
    if let card = viewModel.cardToEdit {
      contentView.configureForEdit(card)
    }
  }

  private func setup() {
    view.addSubview(contentView)
    setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
    contentView.delegate = self
    hideKeyboardWhenTappedAround()
  }
}

extension AddCreditCardViewController: AddCreditCardViewDelegate {
  func didTapBack() {
    flowDelegate?.dismissAddCreditCard()
  }

  func didTapSave() {
    let name = contentView.nameInput.text ?? ""
    let lastFour = contentView.lastFourInput.text ?? ""
    let brandIndex = contentView.brandSelector.selectedSegmentIndex
    let closingDay = Int(contentView.closingDayInput.text ?? "15") ?? 15
    let dueDay = Int(contentView.dueDayInput.text ?? "22") ?? 22

    var creditLimit: Int?
    if let limitText = contentView.creditLimitInput.text, !limitText.isEmpty {
      creditLimit = CurrencyFormatter.shared.parseCents(from: limitText)
    }

    let success = viewModel.saveCard(
      name: name, lastFour: lastFour, brandIndex: brandIndex,
      closingDay: closingDay, dueDay: dueDay,
      creditLimit: creditLimit, cardColor: contentView.selectedColor
    )

    if success {
      flowDelegate?.didSaveCreditCard()
    } else {
      showErrorAlert(title: "Error", message: "Please fill all required fields (name, last 4 digits).")
    }
  }

  private func showErrorAlert(title: String, message: String) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default))
    present(alert, animated: true)
  }
}
```

**EDIT FILE:** `Finova/Sources/Core/Factories/ViewControllersFactory/ViewControllersFactoryProtocol.swift`

Add:
```swift
func makeAddCreditCardViewController(flowDelegate: AddCreditCardFlowDelegate, cardToEdit: CreditCard?) -> AddCreditCardViewController
```

**EDIT FILE:** `Finova/Sources/Core/Factories/ViewControllersFactory/ViewControllersFactory.swift`

Add:
```swift
func makeAddCreditCardViewController(flowDelegate: AddCreditCardFlowDelegate, cardToEdit: CreditCard? = nil) -> AddCreditCardViewController {
  let contentView = AddCreditCardView()
  let viewModel = AddCreditCardViewModel()
  viewModel.cardToEdit = cardToEdit
  let viewController = AddCreditCardViewController(
    contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
  return viewController
}
```

**EDIT FILE:** `Finova/AppFlowController.swift`

Add `AddCreditCardFlowDelegate` conformance:

```swift
// MARK: - Add Credit Card Flow
extension AppFlowController: AddCreditCardFlowDelegate {
  func dismissAddCreditCard() {
    navigationController?.popViewController(animated: true)
  }

  func didSaveCreditCard() {
    navigationController?.popViewController(animated: true)
  }
}
```

**BUILD & VERIFY:** Settings → Credit Cards → "+" → Add Credit Card form → Fill fields → Save → Back to list → Card appears in list. Tap card → Edit form pre-filled → Update. Long-press → Delete confirmation → Card removed.

---

# PHASE 3 — Payment Method in Add Transaction

---

## Step 3.1a — PaymentMethod enum + Update data structs

**EDIT FILE:** `Finova/Sources/Scenes/AddTransaction/AddTransactionModalViewDelegate.swift`

Replace the entire file:

```swift
//
//  AddTransactionViewDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/05/25.
//

import Foundation

enum PaymentMethod: Equatable {
  case cashDebit
  case creditCard(cardId: Int)
}

public struct AddTransactionData {
  let title: String
  let amount: Int
  let date: String
  let category: String
  let transactionType: String
  let creditCardId: Int?

  init(title: String, amount: Int, date: String, category: String, transactionType: String, creditCardId: Int? = nil) {
    self.title = title
    self.amount = amount
    self.date = date
    self.category = category
    self.transactionType = transactionType
    self.creditCardId = creditCardId
  }
}

public struct InstallmentTransactionData {
  let title: String
  let totalAmount: Int
  let date: String
  let category: String
  let transactionType: String
  let installments: Int
  let creditCardId: Int?

  init(title: String, totalAmount: Int, date: String, category: String, transactionType: String, installments: Int, creditCardId: Int? = nil) {
    self.title = title
    self.totalAmount = totalAmount
    self.date = date
    self.category = category
    self.transactionType = transactionType
    self.installments = installments
    self.creditCardId = creditCardId
  }
}

protocol AddTransactionModalViewDelegate: AnyObject {
  func handleError(title: String, message: String)
  func sendTransactionData(_ data: AddTransactionData)
  func sendRecurringTransactionData(_ data: AddTransactionData)
  func sendInstallmentTransactionData(_ data: InstallmentTransactionData)
  func updateTransactionData(id: Int, _ data: AddTransactionData)
  func updateRecurringTransactionData(id: Int, _ data: AddTransactionData)
  func updateInstallmentTransactionData(id: Int, _ data: InstallmentTransactionData)
  func updateSingleRecurringTransactionData(id: Int, _ data: AddTransactionData)
  func updateSingleInstallmentTransactionData(id: Int, _ data: InstallmentTransactionData)
  func updateRecurringTransactionDataWithOption(
    id: Int, _ data: AddTransactionData, editOption: RecurringEditOption)
  func closeModal()
}
```

**BUILD & VERIFY:** Fix all callsites that construct `AddTransactionData(...)` or `InstallmentTransactionData(...)` — the existing ones will still compile because the new `creditCardId` parameter has a default of `nil`. Confirm app compiles.

---

## Step 3.1b — PaymentMethodOptionView component

**NEW FILE:** `Finova/Sources/Core/Components/PaymentMethodOptionView.swift`

```swift
//
//  PaymentMethodOptionView.swift
//  Finova
//

import UIKit

final class PaymentMethodOptionView: UIView {
  var onTap: (() -> Void)?

  private(set) var isSelectedOption: Bool = false

  private let radioView: UIView = {
    let view = UIView()
    view.layer.cornerRadius = 10
    view.layer.borderWidth = 2
    view.layer.borderColor = Colors.gray400.cgColor
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let radioFill: UIView = {
    let view = UIView()
    view.layer.cornerRadius = 5
    view.backgroundColor = Colors.mainMagenta
    view.isHidden = true
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textSMBold.font
    label.textColor = Colors.gray700
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let subtitleLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textXS.font
    label.textColor = Colors.gray500
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  init(title: String, subtitle: String) {
    super.init(frame: .zero)
    titleLabel.text = title
    subtitleLabel.text = subtitle
    setupView()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    backgroundColor = Colors.gray200
    layer.cornerRadius = CornerRadius.large
    layer.borderWidth = 1
    layer.borderColor = Colors.gray300.cgColor
    translatesAutoresizingMaskIntoConstraints = false

    addSubview(radioView)
    radioView.addSubview(radioFill)

    let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
    textStack.axis = .vertical
    textStack.spacing = 2
    textStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(textStack)

    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: Metrics.inputHeight),

      radioView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
      radioView.centerYAnchor.constraint(equalTo: centerYAnchor),
      radioView.widthAnchor.constraint(equalToConstant: 20),
      radioView.heightAnchor.constraint(equalToConstant: 20),

      radioFill.centerXAnchor.constraint(equalTo: radioView.centerXAnchor),
      radioFill.centerYAnchor.constraint(equalTo: radioView.centerYAnchor),
      radioFill.widthAnchor.constraint(equalToConstant: 10),
      radioFill.heightAnchor.constraint(equalToConstant: 10),

      textStack.leadingAnchor.constraint(equalTo: radioView.trailingAnchor, constant: Metrics.spacing3),
      textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
      textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
    ])

    let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
    addGestureRecognizer(tap)
  }

  @objc private func tapped() { onTap?() }

  func setSelected(_ selected: Bool) {
    isSelectedOption = selected
    radioFill.isHidden = !selected
    radioView.layer.borderColor = selected ? Colors.mainMagenta.cgColor : Colors.gray400.cgColor
    layer.borderColor = selected ? Colors.mainMagenta.cgColor : Colors.gray300.cgColor
  }
}
```

**BUILD & VERIFY:** Compiles. No visible change yet.

---

## Step 3.2a — Add Payment Method section to AddTransactionModalView

**EDIT FILE:** `Finova/Sources/Scenes/AddTransaction/AddTransactionModalView.swift`

Add these properties after the existing `transactionModeStackView`:

```swift
// MARK: - Payment Method Section (Credit Card)
private var selectedPaymentMethod: PaymentMethod = .cashDebit
private var availableCards: [CreditCard] = []
private var selectedCard: CreditCard?

private lazy var paymentMethodSection: UIStackView = {
  let stack = UIStackView(
    axis: .vertical, spacing: Metrics.spacing3,
    arrangedSubviews: [paymentMethodTitleLabel, paymentOptionsStack, cardSelectorContainer, statementInfoBanner])
  stack.isHidden = true  // Only show for expenses
  return stack
}()

private let paymentMethodTitleLabel: UILabel = {
  let label = UILabel()
  label.text = "addTransactionModal.paymentMethod.title".localized
  label.font = Fonts.textSMBold.font
  label.textColor = Colors.gray600
  label.translatesAutoresizingMaskIntoConstraints = false
  return label
}()

private lazy var paymentOptionsStack = UIStackView(
  axis: .horizontal, spacing: Metrics.spacing3, distribution: .fillEqually,
  arrangedSubviews: [cashDebitOption, creditCardOption])

private lazy var cashDebitOption: PaymentMethodOptionView = {
  let view = PaymentMethodOptionView(
    title: "addTransactionModal.paymentMethod.cashDebit".localized,
    subtitle: "addTransactionModal.paymentMethod.cashDebit.subtitle".localized)
  view.setSelected(true)
  view.onTap = { [weak self] in self?.selectPaymentMethod(.cashDebit) }
  return view
}()

private lazy var creditCardOption: PaymentMethodOptionView = {
  let view = PaymentMethodOptionView(
    title: "addTransactionModal.paymentMethod.creditCard".localized,
    subtitle: "addTransactionModal.paymentMethod.creditCard.subtitle".localized)
  view.onTap = { [weak self] in self?.selectPaymentMethod(.creditCard(cardId: 0)) }
  return view
}()

private lazy var cardSelectorContainer: UIStackView = {
  let stack = UIStackView(axis: .vertical, spacing: Metrics.spacing2,
    arrangedSubviews: [cardPickerInput])
  stack.isHidden = true
  return stack
}()

private let cardPickerInput = Input(
  type: .picker(values: []),
  placeholder: "addTransactionModal.paymentMethod.selectCard".localized,
  icon: UIImage(named: "lucide_iconCreditCard"), iconPosition: .left)

private let statementInfoBanner: UILabel = {
  let label = UILabel()
  label.font = Fonts.textXS.font
  label.textColor = Colors.gray500
  label.numberOfLines = 0
  label.isHidden = true
  label.translatesAutoresizingMaskIntoConstraints = false
  return label
}()
```

Add this method to the class:

```swift
// MARK: - Payment Method Logic

private func selectPaymentMethod(_ method: PaymentMethod) {
  cashDebitOption.setSelected(method == .cashDebit)
  creditCardOption.setSelected(method != .cashDebit)

  let showCardSelector = method != .cashDebit

  UIView.animate(withDuration: 0.25) {
    self.cardSelectorContainer.isHidden = !showCardSelector
    self.cardSelectorContainer.alpha = showCardSelector ? 1 : 0
    self.layoutIfNeeded()
    if let vc = self.findViewController() { vc.view.layoutIfNeeded() }
  }

  if case .creditCard = method, let firstCard = availableCards.first {
    selectedPaymentMethod = .creditCard(cardId: firstCard.id ?? 0)
    selectedCard = firstCard
    updateStatementInfoBanner()
  } else {
    selectedPaymentMethod = .cashDebit
    selectedCard = nil
    statementInfoBanner.isHidden = true
  }
}

func loadAvailableCards(_ cards: [CreditCard]) {
  availableCards = cards
  let names = cards.map { "\($0.name) ****\($0.lastFourDigits)" }

  // Rebuild picker with card names
  cardPickerInput.updatePickerValues(names)

  if cards.isEmpty {
    cardPickerInput.textField.text = "addTransactionModal.paymentMethod.noCards".localized
    cardPickerInput.isUserInteractionEnabled = false
  } else {
    cardPickerInput.isUserInteractionEnabled = true
  }

  // Listen for picker changes
  cardPickerInput.onPickerSelectionChanged = { [weak self] index in
    guard let self, index < self.availableCards.count else { return }
    let card = self.availableCards[index]
    self.selectedPaymentMethod = .creditCard(cardId: card.id ?? 0)
    self.selectedCard = card
    self.updateStatementInfoBanner()
  }
}

private func updateStatementInfoBanner() {
  guard let card = selectedCard else {
    statementInfoBanner.isHidden = true
    return
  }

  let service = CreditCardService()
  let closingDate = service.calculateClosingDate(card: card, transactionDate: Date())
  let dueDate = service.calculateDueDate(closingDate: closingDate, card: card)
  let monthName = DateFormatter.monthFormatter.string(from: closingDate)
  let dueDateStr = DateFormatter.fullDateFormatter.string(from: dueDate)
  statementInfoBanner.text = String(format: "addTransactionModal.paymentMethod.statementInfo".localized, monthName, dueDateStr)
  statementInfoBanner.isHidden = false
}

func getSelectedCreditCardId() -> Int? {
  if case .creditCard(let cardId) = selectedPaymentMethod, cardId > 0 {
    return cardId
  }
  return nil
}
```

Insert `paymentMethodSection` into the `contentStackView`. In `setupViews()`, after adding `contentStackView` as a subview and before `setupTransactionModeControl()`, add:

```swift
// Insert payment method section into input stack (after date, before mode)
inputStackView.addArrangedSubview(paymentMethodSection)
```

Or better — restructure `inputStackView` to include it. The simplest approach: in the `contentStackView` initializer, add `paymentMethodSection` after `inputStackView`:

```swift
private lazy var contentStackView: UIStackView = {
  let sv = UIStackView(
    axis: .vertical, spacing: Metrics.spacing7, distribution: .fill,
    arrangedSubviews: [
      headerStackView, inputStackView, paymentMethodSection,
      transactionButtonsStackView, separator, saveButton,
    ])
  sv.directionalLayoutMargins = NSDirectionalEdgeInsets(
    top: Metrics.spacing10, leading: Metrics.spacing8, bottom: Metrics.spacing4,
    trailing: Metrics.spacing8)
  sv.isLayoutMarginsRelativeArrangement = true

  sv.setContentHuggingPriority(UILayoutPriority(251), for: .vertical)
  sv.setContentCompressionResistancePriority(UILayoutPriority(751), for: .vertical)

  return sv
}()
```

Then show/hide the section based on expense selection:

In `didTapSaveTransaction()`, pass the credit card ID:

```swift
// In the add mode section where you construct AddTransactionData:
let creditCardId = getSelectedCreditCardId()

// For normal mode:
delegate?.sendTransactionData(
  AddTransactionData(
    title: title, amount: amount, date: date, category: categoryKey,
    transactionType: typeKey, creditCardId: creditCardId)
)

// For installments mode:
delegate?.sendInstallmentTransactionData(
  InstallmentTransactionData(
    title: title, totalAmount: amount, date: date, category: categoryKey,
    transactionType: typeKey, installments: installmentsCount, creditCardId: creditCardId))
```

**BUILD & VERIFY:** Open Add Transaction → see Payment Method section (after switching to expense). Cash/Debit selected by default. Selecting Credit Card shows card picker.

---

## Step 3.2b — Show/Hide Payment Method for Expenses only

Add to `AddTransactionModalView`, in the `transactionTypeSelectorDidSelect` handler (or wherever expense/income is toggled):

The `AddTransactionModalViewController` handles this in `transactionTypeSelectorDidSelect`. After toggling buttons, add:

```swift
// In AddTransactionModalViewController.transactionTypeSelectorDidSelect:
func transactionTypeSelectorDidSelect(_ selector: TransactionTypeSelector) {
  if selector.variant == .selected {
    contentView.incomeSelectorButton.variant = .normal
    contentView.expenseSelectorButton.variant = .normal
  } else {
    if selector.transactionType == .income {
      contentView.incomeSelectorButton.variant = .selected
      contentView.expenseSelectorButton.variant = .unselected
    } else {
      contentView.expenseSelectorButton.variant = .selected
      contentView.incomeSelectorButton.variant = .unselected
    }
  }

  // Show payment method section only for expenses
  let isExpense = contentView.expenseSelectorButton.variant == .selected
  contentView.showPaymentMethodSection(isExpense)
}
```

Add to `AddTransactionModalView`:

```swift
func showPaymentMethodSection(_ show: Bool) {
  UIView.animate(withDuration: 0.25) {
    self.paymentMethodSection.isHidden = !show
    self.paymentMethodSection.alpha = show ? 1 : 0
    self.layoutIfNeeded()
    if let vc = self.findViewController() { vc.view.layoutIfNeeded() }
  }

  if !show {
    // Reset to cash/debit when switching to income
    selectPaymentMethod(.cashDebit)
  }
}
```

**BUILD & VERIFY:** Select Income → payment section hidden. Select Expense → payment section appears.

---

## Step 3.3 — Load cards in ViewController + wire to ViewModel

**EDIT FILE:** `Finova/Sources/Scenes/AddTransaction/AddTransactionModalViewController.swift`

In `viewDidLoad()`, after `setupView()`, add:

```swift
loadCreditCards()
```

Add the method:

```swift
private func loadCreditCards() {
  guard let uid = AuthenticationManager.shared.currentUser?.uid else { return }
  let cardRepo = CreditCardRepository()
  let cards = cardRepo.fetchAllCards(userId: uid)
  contentView.loadAvailableCards(cards)
}
```

**BUILD & VERIFY:** Open Add Transaction as Expense → Credit Card option → card picker shows registered cards.

---

## Step 3.4 — Handle credit card transactions in ViewModel

**EDIT FILE:** `Finova/Sources/Scenes/AddTransaction/AddTransactionModalViewModel.swift`

Add property:

```swift
private let creditCardService = CreditCardService()
private let creditCardRepo = CreditCardRepository()
```

In `addTransaction()`, after creating `model` and calling `insertTransactionAndGetId`, add credit card logic:

```swift
func addTransaction(
  title: String,
  amount: Int,
  dateString: String,
  categoryKey: String,
  typeRaw: String,
  isRecurring: Bool? = nil,
  creditCardId: Int? = nil  // NEW parameter
) -> Result<Void, Error> {

  guard let date = DateFormatter.fullDateFormatter.date(from: dateString) else {
    return .failure(TransactionError.invalidDateFormat)
  }

  let timestamp = Int(date.timeIntervalSince1970)

  guard
    let category = TransactionCategory.allCases
      .first(where: { $0.key == categoryKey })
  else {
    return .failure(TransactionError.invalidCategory)
  }

  guard
    let type = TransactionType.allCases
      .first(where: { String(describing: $0) == typeRaw })
  else {
    return .failure(TransactionError.invalidType)
  }

  let anchor = date.monthAnchor

  let model = TransactionModel(
    title: title,
    category: category.key,
    amount: amount,
    type: type.key,
    dateTimestamp: timestamp,
    budgetMonthDate: anchor,
    isRecurring: isRecurring ?? false,
    creditCardId: creditCardId  // NEW
  )

  do {
    let insertedId = try transactionRepo.insertTransactionAndGetId(model)

    // Handle credit card statement assignment
    if let cardId = creditCardId, let card = creditCardRepo.fetchCard(byId: cardId) {
      guard let uid = AuthenticationManager.shared.currentUser?.uid else {
        return .success(())
      }
      if let statement = creditCardService.getOrCreateStatement(for: card, transactionDate: date, userId: uid) {
        try transactionRepo.updateCreditCardFields(
          transactionId: insertedId,
          creditCardId: cardId,
          statementId: statement.id!,
          isCreditCardStatement: false
        )
        creditCardService.recalculateStatementTotal(statementId: statement.id!)
      }
    }

    // Schedule notification for the new transaction with its ID
    scheduleNotificationForNewTransaction(insertedId, model)

    // Monitor negative balance after adding transaction
    monitorNegativeBalance()

    // Invalidate ledger cache since transactions changed
    invalidateLedgerCache()

    return .success(())
  } catch {
    return .failure(error)
  }
}
```

Similarly update `addTransactionWithInstallmentsAsync` to accept `creditCardId` and assign each installment to its respective statement (installment date → different closing dates):

```swift
func addTransactionWithInstallmentsAsync(
  _ data: InstallmentTransactionData,
  completion: @escaping (Result<Void, Error>) -> Void
) {
  let totalInstallments = data.installments
  guard totalInstallments > 1 else {
    completion(.failure(TransactionError.invalidInstallmentCount))
    return
  }

  guard let startDate = DateFormatter.fullDateFormatter.date(from: data.date) else {
    completion(.failure(TransactionError.invalidDateFormat))
    return
  }

  guard
    let category = TransactionCategory.allCases
      .first(where: { $0.key == data.category })
  else {
    completion(.failure(TransactionError.invalidCategory))
    return
  }

  guard
    let type = TransactionType.allCases
      .first(where: { String(describing: $0) == data.transactionType })
  else {
    completion(.failure(TransactionError.invalidType))
    return
  }

  let amountPerInstallment = data.totalAmount / totalInstallments
  let remainder = data.totalAmount % totalInstallments

  DispatchQueue.global(qos: .userInitiated).async { [weak self] in
    guard let self = self else {
      DispatchQueue.main.async { completion(.failure(TransactionError.repositoryUnavailable)) }
      return
    }

    do {
      // Create parent transaction
      let parentModel = TransactionModel(
        title: "\(data.title) - Installment Parent",
        category: category.key,
        amount: 0,
        type: type.key,
        dateTimestamp: Int(startDate.timeIntervalSince1970),
        budgetMonthDate: startDate.monthAnchor,
        hasInstallments: true,
        originalAmount: data.totalAmount,
        totalInstallments: totalInstallments
      )

      let parentId = try self.transactionRepo.insertTransactionAndGetId(parentModel)

      // Create immediate installments (first 3 months)
      let immediateInstallmentCount = min(3, totalInstallments)
      var allInstallments: [TransactionModel] = []

      for installmentNumber in 1...immediateInstallmentCount {
        let targetDate =
          self.calendar.date(byAdding: .month, value: installmentNumber - 1, to: startDate)
          ?? startDate
        let targetYear = self.calendar.component(.year, from: targetDate)
        let targetMonth = self.calendar.component(.month, from: targetDate)

        let installmentDate = self.generateValidDateForMonth(
          originalDate: startDate,
          targetMonth: targetMonth,
          targetYear: targetYear
        )

        let installmentAmount =
          installmentNumber == 1 ? amountPerInstallment + remainder : amountPerInstallment

        let installmentModel = TransactionModel(
          title: data.title,
          category: category.key,
          amount: installmentAmount,
          type: type.key,
          dateTimestamp: Int(installmentDate.timeIntervalSince1970),
          budgetMonthDate: installmentDate.monthAnchor,
          parentTransactionId: parentId,
          originalAmount: data.totalAmount,
          installmentNumber: installmentNumber,
          totalInstallments: totalInstallments
        )

        let insertedInstallmentId = try self.transactionRepo.insertTransactionAndGetId(installmentModel)
        allInstallments.append(installmentModel)

        // NEW: Assign installment to correct credit card statement
        if let cardId = data.creditCardId, let card = self.creditCardRepo.fetchCard(byId: cardId) {
          guard let uid = AuthenticationManager.shared.currentUser?.uid else { break }
          if let statement = self.creditCardService.getOrCreateStatement(for: card, transactionDate: installmentDate, userId: uid) {
            try self.transactionRepo.updateCreditCardFields(
              transactionId: insertedInstallmentId,
              creditCardId: cardId,
              statementId: statement.id!,
              isCreditCardStatement: false
            )
            self.creditCardService.recalculateStatementTotal(statementId: statement.id!)
          }
        }
      }

      // Schedule notifications
      self.scheduleOptimizedNotificationsForInstallments(allInstallments)
      self.monitorNegativeBalance()

      DispatchQueue.main.async {
        self.invalidateLedgerCache()
        completion(.success(()))
      }

    } catch {
      DispatchQueue.main.async {
        completion(.failure(error))
      }
    }
  }
}
```

You'll also need to add `updateCreditCardFields` to `TransactionRepository`:

**EDIT FILE:** `Finova/Sources/Core/Repositories/TransactionRepository/TransactionRepository.swift`

Add:

```swift
func updateCreditCardFields(transactionId: Int, creditCardId: Int, statementId: Int, isCreditCardStatement: Bool) throws {
  try DBHelper.shared.updateTransactionCreditCardFields(
    transactionId: transactionId,
    creditCardId: creditCardId,
    statementId: statementId,
    isCreditCardStatement: isCreditCardStatement
  )
}
```

**EDIT FILE:** `Finova/Sources/Core/Database/DBHelper.swift`

Add:

```swift
func updateTransactionCreditCardFields(transactionId: Int, creditCardId: Int, statementId: Int, isCreditCardStatement: Bool) throws {
  guard isInitialized else { return }
  let query = "UPDATE Transactions SET credit_card_id = ?, statement_id = ?, is_credit_card_statement = ? WHERE id = ?;"
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }
  sqlite3_bind_int64(statement, 1, Int64(creditCardId))
  sqlite3_bind_int64(statement, 2, Int64(statementId))
  sqlite3_bind_int(statement, 3, isCreditCardStatement ? 1 : 0)
  sqlite3_bind_int64(statement, 4, Int64(transactionId))
  guard sqlite3_step(statement) == SQLITE_DONE else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.stepFailed(message: msg)
  }
}
```

**BUILD & VERIFY:** Add a transaction with credit card selected → check DB: transaction has `credit_card_id` and `statement_id` set. Statement `total_amount` updated.

---

## Step 3.5 — Wire credit card ID through ViewController

**EDIT FILE:** `Finova/Sources/Scenes/AddTransaction/AddTransactionModalViewController.swift`

Update `sendTransactionData`:

```swift
func sendTransactionData(_ data: AddTransactionData) {
  let result = viewModel.addTransaction(
    title: data.title,
    amount: data.amount,
    dateString: data.date,
    categoryKey: data.category,
    typeRaw: data.transactionType,
    creditCardId: data.creditCardId  // NEW
  )
  handleTransactionResult(result)
}
```

Update `sendInstallmentTransactionData`:

```swift
func sendInstallmentTransactionData(_ data: InstallmentTransactionData) {
  contentView.saveButton.startLoading()

  // Pass creditCardId through
  let dataWithCard = InstallmentTransactionData(
    title: data.title, totalAmount: data.totalAmount, date: data.date,
    category: data.category, transactionType: data.transactionType,
    installments: data.installments, creditCardId: data.creditCardId
  )

  viewModel.addTransactionWithInstallmentsAsync(dataWithCard) { [weak self] result in
    DispatchQueue.main.async {
      self?.contentView.saveButton.stopLoading()
      switch result {
      case .success:
        self?.dismissModal()
        self?.flowDelegate?.didAddTransaction()
      case .failure(let error):
        let message: String
        switch error {
        case TransactionError.invalidDateFormat:
          message = "alert.error.invalidDateFormat".localized
        case TransactionError.invalidCategory:
          message = "alert.error.invalidCategory".localized
        case TransactionError.invalidType:
          message = "alert.error.invalidTransactionType".localized
        case TransactionError.invalidInstallmentCount:
          message = "alert.error.invalidInstallmentCount".localized
        default:
          message = "alert.error.defaultMessage".localized
        }
        self?.handleError(title: "alert.error.title".localized, message: message)
      }
    }
  }
}
```

**BUILD & VERIFY:** Create expense with credit card → transaction saved with card + statement. Dashboard shows transaction normally.

---

# PHASE 4 — Dashboard Integration

---

## Step 4.1 — Update TransactionCellConfiguration + configure

**EDIT FILE:** `Finova/Sources/Scenes/Dashboard/DashboardCarousel/MonthCarousel/TransactionsTable/TransactionCell.swift`

Update `TransactionCellConfiguration`:

```swift
struct TransactionCellConfiguration {
  let category: TransactionCategory
  let title: String
  let date: Date
  let value: Int
  let transactionType: TransactionType
  let transactionMode: TransactionMode
  let installmentNumber: Int?
  let totalInstallments: Int?
  let isCreditCardStatement: Bool  // NEW
  let statementTransactionCount: Int?  // NEW
}
```

In `configure(with:)`, update the icon logic:

```swift
func configure(with configuration: TransactionCellConfiguration) {
  self.titleLabel.text = configuration.title
  self.dateLabel.text = DateFormatter.fullDateFormatter.string(from: configuration.date)

  let symbolFont = Fonts.textXS.font
  self.valueLabel.attributedText = configuration.value.currencyAttributedString(
    symbolFont: symbolFont, font: Fonts.titleMD)
  self.valueLabel.accessibilityLabel = configuration.value.currencyString

  // Credit card statement uses special icon
  if configuration.isCreditCardStatement {
    self.iconView.image = UIImage(named: "lucide_iconCreditCard")

    // Show transaction count as subtitle
    if let count = configuration.statementTransactionCount {
      let key = count == 1
        ? "creditCard.statement.subtitle.singular"
        : "creditCard.statement.subtitle"
      self.dateLabel.text = String(format: key.localized, count)
    }
  } else {
    let iconName = configuration.category.iconName(for: configuration.transactionType)
    self.iconView.image = UIImage(named: iconName)
  }

  if configuration.transactionType == .income {
    self.transactionTypeIconView.image = UIImage(named: "arrowUp")
    self.transactionTypeIconView.tintColor = Colors.mainGreen
  } else {
    self.transactionTypeIconView.image = UIImage(named: "arrowDown")
    self.transactionTypeIconView.tintColor = Colors.mainRed
  }

  switch configuration.transactionMode {
  case .recurring:
    self.recurringIcon.isHidden = false
    self.installmentLabel.isHidden = true
  case .installments:
    self.recurringIcon.isHidden = true
    self.installmentLabel.isHidden = false
  case .normal:
    self.recurringIcon.isHidden = true
    self.installmentLabel.isHidden = true
  }

  if configuration.transactionMode == .installments,
    let currentInstallment = configuration.installmentNumber,
    let totalInstallments = configuration.totalInstallments
  {
    let installmentText = "(\(currentInstallment)/\(totalInstallments))"
    self.installmentLabel.text = installmentText
    self.installmentLabel.isHidden = false
  }
}
```

**BUILD & VERIFY:** Fix all `TransactionCellConfiguration(...)` construction sites to include the 2 new parameters (default them to `false` and `nil`). App compiles and runs identically.

---

## Step 4.2 — Update all TransactionCellConfiguration construction sites

Search for every place `TransactionCellConfiguration(` is constructed (likely in `MonthCarouselCell.swift` or the table data source). Add the new fields:

```swift
// For regular transactions:
TransactionCellConfiguration(
  category: tx.category,
  title: tx.title,
  date: tx.date,
  value: tx.amount,
  transactionType: tx.type,
  transactionMode: tx.mode,
  installmentNumber: tx.installmentNumber,
  totalInstallments: tx.totalInstallments,
  isCreditCardStatement: tx.isCreditCardStatement ?? false,
  statementTransactionCount: nil  // Will be populated for statement rows
)
```

**BUILD & VERIFY:** Existing transactions display identically. New credit card transactions show normally (they're not statement rows yet).

---

## Step 4.3 — Generate statement transactions on Dashboard load

**EDIT FILE:** `Finova/Sources/Core/Services/CreditCardService.swift`

Add this method:

```swift
/// Generates synthetic statement transactions for the dashboard.
/// These represent the credit card bill as a single "expense" row on the due date.
func generateStatementTransactions(userId: String) -> [Transaction] {
  let cards = cardRepo.fetchAllCards(userId: userId)
  var statementTransactions: [Transaction] = []

  for card in cards {
    let statements = stmtRepo.fetchStatements(forCardId: card.id!)

    for stmt in statements {
      // Only generate for statements with transactions
      guard stmt.totalAmount > 0 else { continue }

      // Count transactions in this statement
      let txCount: Int
      do {
        txCount = try DBHelper.shared.getTransactionCountForStatement(statementId: stmt.id!)
      } catch {
        txCount = 0
      }

      let title = String(format: "creditCard.statement.title".localized, card.name, card.lastFourDigits)
      let dueTimestamp = Int(stmt.dueDate.timeIntervalSince1970)

      let data = UITransactionData(
        id: -(stmt.id! * 1000 + (card.id ?? 0)),  // Negative ID to distinguish from real transactions
        title: title,
        amount: stmt.totalAmount,
        dateTimestamp: dueTimestamp,
        budgetMonthDate: stmt.dueDate.monthAnchor,
        isRecurring: false,
        hasInstallments: false,
        parentTransactionId: nil,
        installmentNumber: nil,
        totalInstallments: nil,
        originalAmount: stmt.totalAmount,
        creditCardId: card.id,
        statementId: stmt.id,
        isCreditCardStatement: true,
        category: .creditCard,
        type: .expense
      )

      var tx = Transaction(data: data)
      statementTransactions.append(tx)
    }
  }

  return statementTransactions
}
```

Add to `DBHelper.swift`:

```swift
func getTransactionCountForStatement(statementId: Int) throws -> Int {
  guard isInitialized else { return 0 }
  let query = "SELECT COUNT(*) FROM Transactions WHERE statement_id = ? AND is_credit_card_statement = 0;"
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
    let msg = String(cString: sqlite3_errmsg(db))
    throw DBError.prepareFailed(message: msg)
  }
  defer { sqlite3_finalize(statement) }
  sqlite3_bind_int64(statement, 1, Int64(statementId))
  guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
  return Int(sqlite3_column_int64(statement, 0))
}
```

Add `.creditCard` case to `TransactionCategory`:

**EDIT FILE:** `Finova/Sources/Core/Repositories/TransactionRepository/TransactionModel.swift`

In the `TransactionCategory` enum, add:

```swift
case creditCard
```

And in the `iconName(for:)` method:

```swift
case .creditCard: return "lucide_iconCreditCard"
```

And in the `key` computed property:

```swift
case .creditCard: return "creditCard"
```

And in the `description` computed property:

```swift
case .creditCard: return "Credit Card"
```

**BUILD & VERIFY:** Compiles. No visual change yet — statement transactions aren't injected into the dashboard yet.

---

## Step 4.4 — Inject statement transactions into dashboard data

**EDIT FILE:** `Finova/Sources/Scenes/Dashboard/DashboardViewModel.swift`

Add property:

```swift
private let creditCardService = CreditCardService()
```

Add method:

```swift
func getStatementTransactions() -> [Transaction] {
  guard let uid = AuthenticationManager.shared.currentUser?.uid else { return [] }
  return creditCardService.generateStatementTransactions(userId: uid)
}
```

Then, wherever transactions are loaded and grouped by month for the carousel cells, merge in the statement transactions:

```swift
// In the method that provides transactions to MonthCarouselCell (likely in DashboardViewController or the cell configuration):
let statementTxs = viewModel.getStatementTransactions()
let allTransactions = regularTransactions + statementTxs
```

The exact integration point depends on how `MonthCarouselCell` gets its data. Find where `currentCellTransactions` is set and append statement transactions there.

**BUILD & VERIFY:** Dashboard now shows credit card statement rows with the `lucide_iconCreditCard` icon, showing the card name + last 4 digits as title, due date, and total amount.

---

## Step 4.5 — Exclude CC transactions from balance calculation

**EDIT FILE:** `Finova/Sources/Core/Services/TransactionLedgerService.swift`

In the balance calculation method, filter out transactions that belong to a credit card (they shouldn't affect the cash balance):

```swift
// When calculating net balance for a month, exclude credit card transactions:
let cashTransactions = monthTransactions.filter { tx in
  // Exclude transactions linked to a credit card (they go to the statement instead)
  // BUT include statement payment transactions (isCreditCardStatement == true and isPaid)
  return tx.creditCardId == nil || tx.isCreditCardStatement == true
}
```

This ensures:
- Regular cash/debit transactions affect the balance normally
- Credit card purchases do NOT affect the balance (they're on the card)
- When a statement is marked as paid, that payment DOES affect the balance

**BUILD & VERIFY:** Add a credit card transaction → balance doesn't change. Pay the statement → balance decreases.

---

# PHASE 5 — Statement Details Screen

---

## Step 5.1 — StatementDetailsFlowDelegate

**NEW FILE:** `Finova/Sources/Scenes/StatementDetails/StatementDetailsFlowDelegate.swift`

```swift
//
//  StatementDetailsFlowDelegate.swift
//  Finova
//

protocol StatementDetailsFlowDelegate: AnyObject {
  func dismissStatementDetails()
  func didMarkStatementAsPaid()
}
```

---

## Step 5.2 — StatementDetailsViewModel

**NEW FILE:** `Finova/Sources/Scenes/StatementDetails/StatementDetailsViewModel.swift`

```swift
//
//  StatementDetailsViewModel.swift
//  Finova
//

import Foundation

protocol StatementDetailsViewModelDelegate: AnyObject {
  func didLoadTransactions(_ transactions: [Transaction])
  func didUpdateStatement()
}

final class StatementDetailsViewModel {
  weak var delegate: StatementDetailsViewModelDelegate?

  let card: CreditCard
  var statement: CreditCardStatement
  private let stmtRepo = StatementRepository()
  private let transactionRepo = TransactionRepository()
  private(set) var transactions: [Transaction] = []

  init(card: CreditCard, statement: CreditCardStatement) {
    self.card = card
    self.statement = statement
  }

  func loadTransactions() {
    guard let stmtId = statement.id else { return }
    let allTransactions = transactionRepo.fetchAllTransactions()
    transactions = allTransactions.filter { $0.statementId == stmtId && $0.isCreditCardStatement != true }
    transactions.sort { $0.date > $1.date }
    delegate?.didLoadTransactions(transactions)
  }

  var statementTotal: Int {
    transactions.reduce(0) { $0 + $1.amount }
  }

  var periodText: String {
    let formatter = DateFormatter.fullDateFormatter
    let startStr = formatter.string(from: previousClosingDate())
    let endStr = formatter.string(from: statement.closingDate)
    return "\(startStr) — \(endStr)"
  }

  var dueDateText: String {
    DateFormatter.fullDateFormatter.string(from: statement.dueDate)
  }

  var statusText: String {
    statement.status.displayName
  }

  var statusColor: UIColor {
    statement.status.color
  }

  var isPaid: Bool {
    statement.isPaid
  }

  var paidDateText: String? {
    guard let paidDate = statement.paidDate else { return nil }
    return String(format: "statementDetails.paidOn".localized, DateFormatter.fullDateFormatter.string(from: paidDate))
  }

  func markAsPaid() {
    guard let stmtId = statement.id else { return }
    let success = stmtRepo.markAsPaid(statementId: stmtId, paidAmount: statementTotal, paidDate: Date())
    if success {
      statement.isPaid = true
      statement.paidDate = Date()
      statement.paidAmount = statementTotal
      delegate?.didUpdateStatement()
    }
  }

  private func previousClosingDate() -> Date {
    let calendar = Calendar.current
    return calendar.date(byAdding: .month, value: -1, to: statement.closingDate)!
  }
}
```

---

## Step 5.3 — StatementDetailsView

**NEW FILE:** `Finova/Sources/Scenes/StatementDetails/StatementDetailsView.swift`

```swift
//
//  StatementDetailsView.swift
//  Finova
//

import UIKit

protocol StatementDetailsViewDelegate: AnyObject {
  func didTapBack()
  func didTapMarkAsPaid()
  func didTapTransaction(_ transaction: Transaction)
}

final class StatementDetailsView: UIView {
  weak var delegate: StatementDetailsViewDelegate?

  // MARK: - Header
  private let headerContainerView: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray100
    view.translatesAutoresizingMaskIntoConstraints = false
    view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight - 12).isActive = true
    return view
  }()

  private let headerItemsView: UIView = {
    let view = UIView()
    view.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: Metrics.spacing4, leading: Metrics.spacing5,
      bottom: Metrics.spacing5, trailing: Metrics.spacing5)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let backButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
    button.imageView?.contentMode = .scaleAspectFit
    button.translatesAutoresizingMaskIntoConstraints = false
    if #available(iOS 26.0, *) { button.tintColor = Colors.gray700 }
    else { button.tintColor = Colors.gray500 }
    return button
  }()

  private lazy var backButtonGlassContainer: UIView = {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    return container
  }()

  private let headerTitleLabel: UILabel = {
    let label = UILabel()
    label.fontStyle = Fonts.titleSM
    label.applyStyle()
    label.textColor = Colors.gray700
    label.textAlignment = .left
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  // MARK: - Content
  private let scrollView: UIScrollView = {
    let sv = UIScrollView()
    sv.showsVerticalScrollIndicator = false
    sv.translatesAutoresizingMaskIntoConstraints = false
    return sv
  }()

  private let contentStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = Metrics.spacing4
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  // MARK: - Summary Card
  private let summaryCard: UIView = {
    let view = UIView()
    view.backgroundColor = Colors.gray100
    view.layer.cornerRadius = CornerRadius.extraLarge
    view.layer.borderWidth = 1
    view.layer.borderColor = Colors.gray300.cgColor
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let summaryStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = Metrics.spacing4
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  private let periodLabel = StatementDetailsView.createInfoRow(title: "statementDetails.period".localized)
  private let totalLabel = StatementDetailsView.createInfoRow(title: "statementDetails.total".localized)
  private let dueDateLabel = StatementDetailsView.createInfoRow(title: "statementDetails.dueDate".localized)
  private let statusLabel = StatementDetailsView.createInfoRow(title: "statementDetails.status".localized)

  // MARK: - Paid Info
  private let paidInfoLabel: UILabel = {
    let label = UILabel()
    label.font = Fonts.textSM.font
    label.textColor = Colors.gray500
    label.textAlignment = .center
    label.isHidden = true
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  // MARK: - Transactions Section
  private let transactionsSectionHeader: UILabel = {
    let label = UILabel()
    label.font = Fonts.titleXS.font
    label.textColor = Colors.gray700
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let transactionsStackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }()

  // MARK: - Mark as Paid Button
  let markAsPaidButton = Button(variant: .base, label: "statementDetails.button.markAsPaid".localized)

  // MARK: - Init
  override init(frame: CGRect) {
    super.init(frame: .zero)
    setupView()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Setup
  private func setupView() {
    backgroundColor = Colors.gray200

    addSubview(scrollView)
    scrollView.addSubview(headerContainerView)
    headerContainerView.addSubview(headerItemsView)
    headerItemsView.addSubview(backButtonGlassContainer)
    backButtonGlassContainer.addSubview(backButton)
    setupBackButtonGlassEffect()
    headerItemsView.addSubview(headerTitleLabel)

    scrollView.addSubview(contentStackView)

    // Summary card
    summaryCard.addSubview(summaryStackView)
    summaryStackView.addArrangedSubview(periodLabel.container)
    summaryStackView.addArrangedSubview(totalLabel.container)
    summaryStackView.addArrangedSubview(dueDateLabel.container)
    summaryStackView.addArrangedSubview(statusLabel.container)

    NSLayoutConstraint.activate([
      summaryStackView.topAnchor.constraint(equalTo: summaryCard.topAnchor, constant: Metrics.spacing4),
      summaryStackView.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: Metrics.spacing4),
      summaryStackView.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -Metrics.spacing4),
      summaryStackView.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: -Metrics.spacing4),
    ])

    contentStackView.addArrangedSubview(summaryCard)
    contentStackView.addArrangedSubview(paidInfoLabel)
    contentStackView.addArrangedSubview(transactionsSectionHeader)
    contentStackView.addArrangedSubview(transactionsStackView)
    contentStackView.addArrangedSubview(markAsPaidButton)

    setupConstraints()
    setupActions()
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

      headerContainerView.topAnchor.constraint(equalTo: topAnchor),
      headerContainerView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      headerContainerView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),

      headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
      headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
      headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

      backButtonGlassContainer.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
      backButtonGlassContainer.leadingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
      backButtonGlassContainer.widthAnchor.constraint(equalToConstant: 36),
      backButtonGlassContainer.heightAnchor.constraint(equalToConstant: 36),

      backButton.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
      backButton.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
      backButton.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
      backButton.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),

      headerTitleLabel.leadingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
      headerTitleLabel.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),

      contentStackView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing4),
      contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Metrics.spacing4),
      contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing4),
      contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Metrics.spacing4),
      contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * Metrics.spacing4),
    ])
  }

  private func setupBackButtonGlassEffect() {
    if #available(iOS 26.0, *) {
      let glassEffect = UIGlassEffect()
      glassEffect.isInteractive = true
      let glassView = UIVisualEffectView(effect: glassEffect)
      glassView.translatesAutoresizingMaskIntoConstraints = false
      backButtonGlassContainer.insertSubview(glassView, at: 0)
      backButtonGlassContainer.layer.cornerRadius = 18
      backButtonGlassContainer.clipsToBounds = true
      NSLayoutConstraint.activate([
        glassView.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
        glassView.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
        glassView.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
        glassView.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),
      ])
    }
  }

  private func setupActions() {
    backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
    let backTap = UITapGestureRecognizer(target: self, action: #selector(backTapped))
    backButtonGlassContainer.addGestureRecognizer(backTap)
    markAsPaidButton.addTarget(self, action: #selector(markAsPaidTapped), for: .touchUpInside)
  }

  @objc private func backTapped() { delegate?.didTapBack() }
  @objc private func markAsPaidTapped() { delegate?.didTapMarkAsPaid() }

  // MARK: - Configuration
  func configure(with viewModel: StatementDetailsViewModel) {
    headerTitleLabel.text = String(format: "statementDetails.header.title".localized, viewModel.card.name)

    periodLabel.valueLabel.text = viewModel.periodText
    totalLabel.valueLabel.attributedText = viewModel.statementTotal.currencyAttributedString(
      symbolFont: Fonts.textXS.font, font: Fonts.titleMD)
    dueDateLabel.valueLabel.text = viewModel.dueDateText

    statusLabel.valueLabel.text = viewModel.statusText
    statusLabel.valueLabel.textColor = viewModel.statusColor

    // Show/hide mark as paid button
    markAsPaidButton.isHidden = viewModel.isPaid
    if let paidText = viewModel.paidDateText {
      paidInfoLabel.text = paidText
      paidInfoLabel.isHidden = false
    } else {
      paidInfoLabel.isHidden = true
    }

    // Transactions section
    transactionsSectionHeader.text = String(format: "statementDetails.transactions".localized, viewModel.transactions.count)

    // Reload transaction rows
    transactionsStackView.arrangedSubviews.forEach {
      transactionsStackView.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }

    for transaction in viewModel.transactions {
      let row = createTransactionRow(transaction)
      transactionsStackView.addArrangedSubview(row)
    }
  }

  private func createTransactionRow(_ transaction: Transaction) -> UIView {
    let container = UIView()
    container.backgroundColor = Colors.gray100
    container.translatesAutoresizingMaskIntoConstraints = false
    container.heightAnchor.constraint(equalToConstant: 56).isActive = true

    let iconContainer = UIView()
    iconContainer.layer.cornerRadius = CornerRadius.medium
    iconContainer.backgroundColor = Colors.gray200
    iconContainer.layer.borderColor = Colors.gray300.cgColor
    iconContainer.layer.borderWidth = 1
    iconContainer.translatesAutoresizingMaskIntoConstraints = false

    let iconView = UIImageView()
    iconView.image = UIImage(named: transaction.category.iconName(for: transaction.type))
    iconView.tintColor = Colors.mainMagenta
    iconView.contentMode = .scaleAspectFit
    iconView.translatesAutoresizingMaskIntoConstraints = false

    let titleLabel = UILabel()
    titleLabel.text = transaction.title
    titleLabel.font = Fonts.textSMBold.font
    titleLabel.textColor = Colors.gray700
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    let dateLabel = UILabel()
    dateLabel.text = DateFormatter.fullDateFormatter.string(from: transaction.date)
    dateLabel.font = Fonts.textXS.font
    dateLabel.textColor = Colors.gray500
    dateLabel.translatesAutoresizingMaskIntoConstraints = false

    let amountLabel = UILabel()
    let symbolFont = Fonts.textXS.font
    amountLabel.attributedText = transaction.amount.currencyAttributedString(symbolFont: symbolFont, font: Fonts.titleMD)
    amountLabel.textAlignment = .right
    amountLabel.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(iconContainer)
    iconContainer.addSubview(iconView)
    container.addSubview(titleLabel)
    container.addSubview(dateLabel)
    container.addSubview(amountLabel)

    NSLayoutConstraint.activate([
      iconContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.spacing4),
      iconContainer.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      iconContainer.widthAnchor.constraint(equalToConstant: Metrics.spacing8),
      iconContainer.heightAnchor.constraint(equalToConstant: Metrics.spacing8),

      iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
      iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: Metrics.spacing5),
      iconView.heightAnchor.constraint(equalToConstant: Metrics.spacing5),

      titleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: Metrics.spacing3),
      titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.spacing2),

      dateLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

      amountLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.spacing4),
      amountLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      amountLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: Metrics.spacing3),
    ])

    let tap = UITapGestureRecognizer(target: self, action: #selector(transactionRowTapped(_:)))
    container.tag = transaction.id ?? 0
    container.addGestureRecognizer(tap)
    container.isUserInteractionEnabled = true

    return container
  }

  @objc private func transactionRowTapped(_ gesture: UITapGestureRecognizer) {
    // Transaction tap can navigate to details if needed
  }

  // MARK: - Info Row Helper
  private static func createInfoRow(title: String) -> (container: UIView, valueLabel: UILabel) {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let titleLabel = UILabel()
    titleLabel.text = title
    titleLabel.font = Fonts.textSM.font
    titleLabel.textColor = Colors.gray500
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    let valueLabel = UILabel()
    valueLabel.font = Fonts.textSMBold.font
    valueLabel.textColor = Colors.gray700
    valueLabel.textAlignment = .right
    valueLabel.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(titleLabel)
    container.addSubview(valueLabel)

    NSLayoutConstraint.activate([
      container.heightAnchor.constraint(equalToConstant: 24),
      titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: Metrics.spacing3),
    ])

    return (container, valueLabel)
  }
}
```

**BUILD & VERIFY:** Compiles. No visible change yet.

---

## Step 5.4 — StatementDetailsViewController

**NEW FILE:** `Finova/Sources/Scenes/StatementDetails/StatementDetailsViewController.swift`

```swift
//
//  StatementDetailsViewController.swift
//  Finova
//

import UIKit

final class StatementDetailsViewController: UIViewController {
  let contentView: StatementDetailsView
  private let viewModel: StatementDetailsViewModel
  weak var flowDelegate: StatementDetailsFlowDelegate?

  init(contentView: StatementDetailsView, viewModel: StatementDetailsViewModel, flowDelegate: StatementDetailsFlowDelegate) {
    self.contentView = contentView
    self.viewModel = viewModel
    self.flowDelegate = flowDelegate
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setup()
    viewModel.loadTransactions()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(true, animated: false)
  }

  private func setup() {
    view.addSubview(contentView)
    setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
    contentView.delegate = self
    viewModel.delegate = self
  }
}

extension StatementDetailsViewController: StatementDetailsViewDelegate {
  func didTapBack() {
    flowDelegate?.dismissStatementDetails()
  }

  func didTapMarkAsPaid() {
    let alert = UIAlertController(
      title: "statementDetails.button.markAsPaid".localized,
      message: nil,
      preferredStyle: .alert
    )

    alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default) { [weak self] _ in
      self?.viewModel.markAsPaid()
    })
    alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))

    present(alert, animated: true)
  }

  func didTapTransaction(_ transaction: Transaction) {
    // Could navigate to TransactionDetails if desired
  }
}

extension StatementDetailsViewController: StatementDetailsViewModelDelegate {
  func didLoadTransactions(_ transactions: [Transaction]) {
    contentView.configure(with: viewModel)
  }

  func didUpdateStatement() {
    contentView.configure(with: viewModel)
    flowDelegate?.didMarkStatementAsPaid()
  }
}
```

---

## Step 5.5 — Wire Factory + AppFlowController

**EDIT FILE:** `Finova/Sources/Core/Factories/ViewControllersFactory/ViewControllersFactoryProtocol.swift`

Add:

```swift
func makeStatementDetailsViewController(
  flowDelegate: StatementDetailsFlowDelegate,
  card: CreditCard,
  statement: CreditCardStatement
) -> StatementDetailsViewController
```

**EDIT FILE:** `Finova/Sources/Core/Factories/ViewControllersFactory/ViewControllersFactory.swift`

Add:

```swift
func makeStatementDetailsViewController(
  flowDelegate: StatementDetailsFlowDelegate,
  card: CreditCard,
  statement: CreditCardStatement
) -> StatementDetailsViewController {
  let contentView = StatementDetailsView()
  let viewModel = StatementDetailsViewModel(card: card, statement: statement)
  let viewController = StatementDetailsViewController(
    contentView: contentView, viewModel: viewModel, flowDelegate: flowDelegate)
  return viewController
}
```

**EDIT FILE:** `Finova/Sources/Scenes/Dashboard/DashboardFlowDelegate.swift`

Add:

```swift
func navigateToStatementDetails(card: CreditCard, statement: CreditCardStatement)
```

**EDIT FILE:** `Finova/AppFlowController.swift`

In the `DashboardFlowDelegate` extension, add:

```swift
func navigateToStatementDetails(card: CreditCard, statement: CreditCardStatement) {
  let viewController = viewControllersFactory.makeStatementDetailsViewController(
    flowDelegate: self, card: card, statement: statement)
  navigationController?.pushViewController(viewController, animated: true)
}
```

Add `StatementDetailsFlowDelegate` conformance:

```swift
// MARK: - Statement Details Flow
extension AppFlowController: StatementDetailsFlowDelegate {
  func dismissStatementDetails() {
    navigationController?.popViewController(animated: true)
  }

  func didMarkStatementAsPaid() {
    // Pop back and refresh dashboard
    navigationController?.popViewController(animated: true)
  }
}
```

---

## Step 5.6 — Navigate to Statement Details from Dashboard

In the Dashboard, when the user taps a transaction row that has `isCreditCardStatement == true`, navigate to Statement Details instead of Transaction Details.

**EDIT FILE:** wherever `navigateToTransactionDetails` is called from the dashboard cell tap (likely in `DashboardViewController` or `MonthCarouselCell`):

```swift
// In the transaction cell tap handler:
func didTapTransaction(_ transaction: Transaction) {
  if transaction.isCreditCardStatement == true,
     let cardId = transaction.creditCardId,
     let stmtId = transaction.statementId {
    // Navigate to statement details
    let cardRepo = CreditCardRepository()
    let stmtRepo = StatementRepository()
    if let card = cardRepo.fetchCard(byId: cardId) {
      let statements = stmtRepo.fetchStatements(forCardId: cardId)
      if let statement = statements.first(where: { $0.id == stmtId }) {
        flowDelegate?.navigateToStatementDetails(card: card, statement: statement)
        return
      }
    }
  }

  // Default: navigate to transaction details
  flowDelegate?.navigateToTransactionDetails(transaction: transaction)
}
```

**BUILD & VERIFY:** Dashboard → tap credit card statement row → Statement Details screen appears with summary card (period, total, due date, status) + list of transactions in that statement + "Mark as Paid" button. Tapping "Mark as Paid" → confirms → updates status → pops back.

---

# PHASE 6 — Edge Cases & Polish

---

## Step 6.1 — Recalculate statement totals on transaction edit/delete

**EDIT FILE:** `Finova/Sources/Scenes/AddTransaction/AddTransactionModalViewModel.swift`

In `updateTransaction()` method, after updating the transaction, recalculate statement total:

```swift
// After try transactionRepo.updateTransaction(updatedTransaction):
if let stmtId = updatedTransaction.data.statementId {
  CreditCardService().recalculateStatementTotal(statementId: stmtId)
}
```

**EDIT FILE:** `Finova/Sources/Scenes/Dashboard/DashboardViewModel.swift`

In `deleteTransaction()`, after deleting, recalculate:

```swift
// Before returning .success(()):
if let stmtId = transaction.statementId {
  CreditCardService().recalculateStatementTotal(statementId: stmtId)
}
```

In `deleteComplexTransaction()`, same pattern:

```swift
// After deletion succeeds:
if let stmtId = transaction.statementId {
  CreditCardService().recalculateStatementTotal(statementId: stmtId)
}
```

**BUILD & VERIFY:** Edit a CC transaction amount → statement total updates. Delete a CC transaction → statement total decreases.

---

## Step 6.2 — Show payment method as read-only in edit mode

**EDIT FILE:** `Finova/Sources/Scenes/AddTransaction/AddTransactionModalView.swift`

In `configureForEdit(with:)`, after existing logic:

```swift
// Hide payment method section in edit mode (read-only for now)
paymentMethodSection.isHidden = true
```

**BUILD & VERIFY:** Edit transaction → payment method section not shown.

---

## Step 6.3 — Soft-deleted card handling

Already handled: `fetchAllCards` filters `is_deleted = 0`. When a card is soft-deleted:
- Existing transactions keep their `credit_card_id` (preserved)
- Card picker won't show deleted cards
- Statement details can still load via `fetchCard(byId:)` since it doesn't filter `is_deleted`

Update `getCreditCard(id:)` in DBHelper to NOT filter by `is_deleted` (it already doesn't — it only checks `id`):

```swift
// Already correct — getCreditCard(id:) returns card regardless of is_deleted status
```

**BUILD & VERIFY:** Delete a card → existing CC transactions still display correctly. Card no longer appears in picker.

---

## Step 6.4 — Input.updatePickerValues helper

You may need to add this helper to `Input.swift` if it doesn't exist:

**EDIT FILE:** `Finova/Sources/Core/Components/Input/Input.swift`

Add:

```swift
func updatePickerValues(_ values: [String]) {
  self.pickerValues = values
  if let picker = textField.inputView as? UIPickerView {
    picker.reloadAllComponents()
  }
}

var onPickerSelectionChanged: ((Int) -> Void)?
```

Then in the picker delegate method (where selection changes are handled), call:

```swift
onPickerSelectionChanged?(row)
```

**BUILD & VERIFY:** Card picker updates correctly when cards are added/removed.

---

## Quick Reference: Build Checkpoints

| Step | What You Should See |
|---|---|
| Phase 0 | Auto-login to Dashboard |
| 1.1-1.7 | App identical. New DB tables created silently. |
| 2.1a | Settings: "FINANCIAL" section with "Credit Cards" row |
| 2.2b | Credit Cards list: empty state screen |
| 2.3 | Add Card form: fill & save → card persists |
| 2.2e | Card list: styled card cells with gradient |
| 2.2f | Edit (tap) and Delete (long-press) working |
| 3.1a | AddTransactionData now has creditCardId field (compiles) |
| 3.1b | PaymentMethodOptionView component compiles |
| 3.2a | Add Transaction: Payment Method section visible for expenses |
| 3.3 | Card picker shows registered cards |
| 3.4 | CC transactions saved with card + statement refs in DB |
| 4.1 | TransactionCell supports isCreditCardStatement styling |
| 4.3 | `.creditCard` category added, statement transactions generated |
| 4.4 | Dashboard: statement rows with credit card icon + card name |
| 4.5 | CC transactions excluded from balance; paid statements affect balance |
| 5.3 | Statement Details screen with summary card + transactions list |
| 5.4 | Mark as Paid → status updates → pops back |
| 5.6 | Tap statement row → Statement Details (not Transaction Details) |
| 6.1 | Edit/delete CC transaction → statement total recalculates |
| 6.2 | Edit mode hides payment method section |
| 6.3 | Soft-deleted card → existing transactions preserved |

---

## File Creation Order

```
Phase 1 - Data Layer:
  1. Core/Models/CreditCard.swift                        (NEW)
  2. Core/Models/CreditCardStatement.swift               (NEW)
  3. Core/Database/DBHelper.swift                        (EDIT - 3 new tables + CRUD)
  4. Core/Repositories/TransactionRepository/TransactionData.swift  (EDIT - 3 fields)
  5. Core/Repositories/TransactionRepository/TransactionModel.swift (EDIT - 3 fields)
  6. Core/Repositories/CreditCardRepository.swift        (NEW)
  7. Core/Repositories/StatementRepository.swift         (NEW)
  8. Core/Services/CreditCardService.swift               (NEW)

Phase 2 - Settings → Credit Cards:
  9.  Scenes/Settings/SettingsView.swift                 (EDIT - Financial section)
  10. Scenes/Settings/SettingsViewDelegate.swift          (EDIT - didTapCreditCards)
  11. Scenes/Settings/SettingsFlowDelegate.swift          (EDIT - navigateToCreditCards)
  12. Scenes/Settings/SettingsViewController.swift        (EDIT - wire delegate)
  13. Scenes/CreditCards/CreditCardsFlowDelegate.swift   (NEW)
  14. Scenes/CreditCards/CreditCardsViewDelegate.swift   (NEW)
  15. Scenes/CreditCards/CreditCardsView.swift            (NEW)
  16. Scenes/CreditCards/CreditCardsViewController.swift  (NEW)
  17. Scenes/CreditCards/CreditCardsViewModel.swift       (NEW)
  18. Scenes/CreditCards/Views/CreditCardCell.swift       (NEW)
  19. Scenes/AddCreditCard/AddCreditCardFlowDelegate.swift    (NEW)
  20. Scenes/AddCreditCard/AddCreditCardViewDelegate.swift    (NEW)
  21. Scenes/AddCreditCard/AddCreditCardView.swift            (NEW)
  22. Scenes/AddCreditCard/AddCreditCardViewController.swift  (NEW)
  23. Scenes/AddCreditCard/AddCreditCardViewModel.swift       (NEW)
  24. Core/Factories/ViewControllersFactoryProtocol.swift (EDIT)
  25. Core/Factories/ViewControllersFactory.swift         (EDIT)
  26. AppFlowController.swift                             (EDIT)

Phase 3 - Payment Method:
  27. Scenes/AddTransaction/AddTransactionModalViewDelegate.swift (EDIT - PaymentMethod enum + creditCardId)
  28. Core/Components/PaymentMethodOptionView.swift        (NEW)
  29. Scenes/AddTransaction/AddTransactionModalView.swift  (EDIT - payment section)
  30. Scenes/AddTransaction/AddTransactionModalViewController.swift (EDIT - load cards)
  31. Scenes/AddTransaction/AddTransactionModalViewModel.swift  (EDIT - CC service)
  32. Core/Repositories/TransactionRepository/TransactionRepository.swift (EDIT - updateCreditCardFields)
  33. Core/Database/DBHelper.swift                         (EDIT - updateTransactionCreditCardFields)

Phase 4 - Dashboard:
  34. Scenes/Dashboard/DashboardCarousel/MonthCarousel/TransactionsTable/TransactionCell.swift (EDIT - isCreditCardStatement in config)
  35. Core/Repositories/TransactionRepository/TransactionModel.swift (EDIT - .creditCard category)
  36. Core/Services/CreditCardService.swift                (EDIT - generateStatementTransactions)
  37. Core/Database/DBHelper.swift                         (EDIT - getTransactionCountForStatement)
  38. Scenes/Dashboard/DashboardViewModel.swift            (EDIT - getStatementTransactions)
  39. Core/Services/TransactionLedgerService.swift         (EDIT - exclude CC from balance)

Phase 5 - Statement Details:
  40. Scenes/StatementDetails/StatementDetailsFlowDelegate.swift  (NEW)
  41. Scenes/StatementDetails/StatementDetailsViewModel.swift     (NEW)
  42. Scenes/StatementDetails/StatementDetailsView.swift          (NEW)
  43. Scenes/StatementDetails/StatementDetailsViewController.swift (NEW)
  44. Core/Factories/ViewControllersFactoryProtocol.swift  (EDIT)
  45. Core/Factories/ViewControllersFactory.swift          (EDIT)
  46. Scenes/Dashboard/DashboardFlowDelegate.swift         (EDIT)
  47. AppFlowController.swift                              (EDIT)

Phase 6 - Edge Cases:
  48. Scenes/AddTransaction/AddTransactionModalViewModel.swift (EDIT - recalc on edit)
  49. Scenes/Dashboard/DashboardViewModel.swift            (EDIT - recalc on delete)
  50. Scenes/AddTransaction/AddTransactionModalView.swift  (EDIT - hide payment in edit)
  51. Core/Components/Input/Input.swift                    (EDIT - updatePickerValues helper)
```
