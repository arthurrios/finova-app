//
//  StatementPaymentViewController.swift
//  Finova
//

import UIKit

final class StatementPaymentViewController: UIViewController {
    let contentView: StatementPaymentView
    let viewModel: StatementPaymentViewModel
    weak var flowDelegate: StatementPaymentFlowDelegate?

    init(
        contentView: StatementPaymentView,
        viewModel: StatementPaymentViewModel,
        flowDelegate: StatementPaymentFlowDelegate
    ) {
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
        view.addSubview(contentView)
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
        contentView.delegate = self
        contentView.configure(with: viewModel)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
}

// MARK: - StatementPaymentViewDelegate

extension StatementPaymentViewController: StatementPaymentViewDelegate {
    func didTapBack() {
        flowDelegate?.dismissStatementPayment()
    }

    func didChangeAmount(cents: Int) {
        viewModel.amount = cents
        contentView.refresh(with: viewModel)
    }

    func didChangeSchedule(payToday: Bool) {
        viewModel.payToday = payToday
        contentView.refresh(with: viewModel)
    }

    func didTapContinue() {
        // Read both fields at confirm time rather than tracking every picker change: the fields are
        // the source of truth, and an untouched one keeps the default the view model was built with.
        viewModel.amount = contentView.amountInput.centsValue
        if let picked = contentView.dateInput.dateValue {
            viewModel.paymentDate = max(picked, viewModel.minimumPaymentDate)
        }
        contentView.refresh(with: viewModel)
        guard viewModel.canContinue else { return }

        let paymentDate = viewModel.effectivePaymentDate
        let outcome = viewModel.paysInFull
            ? "statementPayment.confirm.full".localized
            : String(
                format: "statementPayment.confirm.partial".localized,
                viewModel.balanceAfterPayment.currencyString)

        let message = String(
            format: "statementPayment.confirm.message".localized,
            viewModel.amount.currencyString,
            viewModel.cardLabel,
            DateFormatter.fullDateFormatter.string(from: paymentDate),
            outcome
        )

        let alert = UIAlertController(
            title: "statementPayment.confirm.title".localized,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        alert.addAction(
            UIAlertAction(title: "statementPayment.confirm.action".localized, style: .default) {
                [weak self] _ in
                self?.performPayment()
            })
        present(alert, animated: true)
    }

    private func performPayment() {
        contentView.startLoading()

        // Off the main thread: this writes two rows, recalculates the statement total and schedules a
        // notification, which is enough work to drop frames on a large ledger.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = self.viewModel.confirm()
            DispatchQueue.main.async {
                self.contentView.stopLoading()
                switch result {
                case .success(let paymentId):
                    self.flowDelegate?.didCompleteStatementPayment(paymentId: paymentId)
                case .failure(let error):
                    self.showPaymentError(error)
                }
            }
        }
    }

    private func showPaymentError(_ error: Error) {
        // The balance can move under the user while this screen is open — another device syncing a
        // charge in, a transaction deleted behind it — so an over-the-cap rejection is worth naming
        // rather than folding into the generic message.
        let message: String
        if case StatementPaymentError.exceedsBalance = error {
            message = String(
                format: "statementPayment.error.exceedsBalance".localized,
                viewModel.remainingBalance.currencyString)
        } else {
            message = "statementPayment.error.generic".localized
        }

        let alert = UIAlertController(
            title: "alert.error".localized,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default))
        present(alert, animated: true)
        logError("Statement payment failed: \(error)")
    }
}
