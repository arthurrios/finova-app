//
//  StatementPaymentViewModel.swift
//  Finova
//

import Foundation

final class StatementPaymentViewModel {
    private let service: StatementPaymentService

    let card: CreditCard
    let statement: CreditCardStatement

    /// What the invoice still owes, read once when the screen opens. Everything on the screen — the
    /// prefilled amount, the cap, the "remaining after this payment" line — is derived from it.
    let remainingBalance: Int

    /// In cents, mirroring `Input.centsValue`.
    var amount: Int

    /// `true` while the "Pay today" option is selected. Scheduling reveals the date field; paying
    /// today ignores it entirely, which is why the date is only read from the field when this is off.
    var payToday: Bool = true

    var paymentDate: Date

    init(service: StatementPaymentService = StatementPaymentService(),
         card: CreditCard,
         statement: CreditCardStatement) {
        self.service = service
        self.card = card
        self.statement = statement
        let balance = statement.id.map { service.remainingBalance(statementId: $0) } ?? 0
        self.remainingBalance = balance
        // Prefilled with the full balance: paying the whole invoice is the common case, and it makes
        // the cap visible without the user having to discover it by overshooting.
        self.amount = balance
        self.paymentDate = Date()
    }

    // MARK: - Derived state

    var cardLabel: String { "\(card.name) ****\(card.lastFourDigits)" }

    var dueDateText: String {
        DateFormatter.fullDateFormatter.string(from: statement.dueDate)
    }

    var statementLabel: String {
        DateFormatter.monthYearShortFormatter.string(from: statement.dueDate)
    }

    /// The date the payment will actually be booked on. "Pay today" wins over whatever the date field
    /// happens to hold, so switching back to today after picking a date does what it says.
    var effectivePaymentDate: Date {
        payToday ? Date() : max(paymentDate, minimumPaymentDate)
    }

    /// Backdating a payment into a month the user has already reconciled would rewrite a balance they
    /// have closed the books on, so the picker starts today. Same rule as early installment payment.
    var minimumPaymentDate: Date { Calendar.current.startOfDay(for: Date()) }

    var balanceAfterPayment: Int { max(0, remainingBalance - amount) }

    var paysInFull: Bool { amount > 0 && amount >= remainingBalance }

    var exceedsBalance: Bool { amount > remainingBalance }

    var canContinue: Bool { amount > 0 && amount <= remainingBalance }

    /// Shown under the amount field when the entered value is over the cap. Nothing is blocked
    /// silently — the button disables, and this says why.
    var amountErrorText: String? {
        guard exceedsBalance else { return nil }
        return String(
            format: "statementPayment.error.exceedsBalance".localized,
            remainingBalance.currencyString)
    }

    // MARK: - Confirming

    func confirm() -> Result<Int, Error> {
        do {
            let paymentId = try service.pay(
                statement: statement,
                card: card,
                amount: amount,
                paymentDate: effectivePaymentDate
            )
            return .success(paymentId)
        } catch {
            return .failure(error)
        }
    }

    /// The debit that was created, for handing to the details screen.
    func createdPayment(id: Int) -> Transaction? {
        TransactionRepository().fetchAllTransactions().first { $0.id == id }
    }
}
