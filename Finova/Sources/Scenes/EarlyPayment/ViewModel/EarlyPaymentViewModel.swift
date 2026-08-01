//
//  EarlyPaymentViewModel.swift
//  Finova
//

import Foundation

final class EarlyPaymentViewModel {
    /// One row of the selection list.
    struct Row {
        let id: Int
        let title: String
        let amount: Int
        let isSelected: Bool
    }

    private let service: EarlyPaymentService
    private(set) var sourceTransaction: Transaction
    private(set) var installments: [EarlyPayableInstallment]
    private(set) var selectedIds: Set<Int> = []

    /// The card the series is charged to, or nil for a series with no card. Its absence is what
    /// removes the destination choice from the screen entirely — there is no open statement to
    /// charge to.
    let card: CreditCard?

    var paymentDate: Date
    var chargeToOpenStatement: Bool

    init(service: EarlyPaymentService = EarlyPaymentService(), transaction: Transaction) {
        self.service = service
        self.sourceTransaction = transaction
        self.installments = service.payableInstallments(for: transaction)
        self.card = service.card(for: transaction)
        self.paymentDate = Date()
        // Defaults to the card's open statement when there is one: that is what the operation means
        // on a credit card, and it matches what bank apps do. Switchable on the screen.
        self.chargeToOpenStatement = self.card != nil
    }

    // MARK: - Derived state

    var hasInstallments: Bool { !installments.isEmpty }

    var seriesTitle: String { sourceTransaction.title }

    var rows: [Row] {
        installments.compactMap { installment in
            guard let id = installment.id else { return nil }
            return Row(
                id: id,
                title: String(
                    format: "earlyPayment.installmentRow".localized,
                    installment.installmentNumber,
                    installment.totalInstallments,
                    DateFormatter.monthYearShortFormatter.string(from: installment.dueDate)
                ),
                amount: installment.amount,
                isSelected: selectedIds.contains(id)
            )
        }
    }

    var selectedTotal: Int {
        installments
            .filter { $0.id.map(selectedIds.contains) ?? false }
            .reduce(0) { $0 + $1.amount }
    }

    var selectedCount: Int { selectedIds.count }

    var allSelected: Bool {
        !installments.isEmpty && selectedIds.count == installments.count
    }

    var canContinue: Bool { !selectedIds.isEmpty }

    var destinationSubtitle: String {
        guard let card = card else { return "" }
        return "\(card.name) ****\(card.lastFourDigits)"
    }

    /// The statement the charge would actually land on, named by its due month.
    ///
    /// Shown because "the card's open statement" is ambiguous around a closing date — the user needs
    /// to see which invoice this ends up on before confirming.
    var targetStatementLabel: String? {
        guard let card = card,
              let uid = UIDUserDefaultsManager.shared.currentUserUID
                ?? AuthenticationManager.shared.currentUser?.uid,
              let statement = CreditCardService().nextOpenStatement(
                for: card, userId: uid, asOf: paymentDate)
        else { return nil }
        return DateFormatter.monthYearShortFormatter.string(from: statement.dueDate)
    }

    /// Earliest date the payment may be dated. Backdating an early payment into a closed month would
    /// rewrite a balance the user has already reconciled, so the picker starts today.
    var minimumPaymentDate: Date { Calendar.current.startOfDay(for: Date()) }

    // MARK: - Selection

    func toggle(id: Int) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    func toggleSelectAll() {
        if allSelected {
            selectedIds.removeAll()
        } else {
            selectedIds = Set(installments.compactMap { $0.id })
        }
    }

    // MARK: - Confirming

    var destination: EarlyPaymentDestination {
        if chargeToOpenStatement, let card = card { return .openStatement(card) }
        return .standalone
    }

    func confirm() -> Result<Int, Error> {
        let selected = installments.filter { $0.id.map(selectedIds.contains) ?? false }
        do {
            let paymentId = try service.payEarly(
                installments: selected,
                paymentDate: paymentDate,
                destination: destination,
                seriesTitle: seriesTitle
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
