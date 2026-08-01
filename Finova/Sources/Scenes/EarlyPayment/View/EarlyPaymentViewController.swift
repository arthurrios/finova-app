//
//  EarlyPaymentViewController.swift
//  Finova
//

import UIKit

final class EarlyPaymentViewController: UIViewController {
    let contentView: EarlyPaymentView
    let viewModel: EarlyPaymentViewModel
    weak var flowDelegate: EarlyPaymentFlowDelegate?

    init(
        contentView: EarlyPaymentView,
        viewModel: EarlyPaymentViewModel,
        flowDelegate: EarlyPaymentFlowDelegate
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

// MARK: - EarlyPaymentViewDelegate

extension EarlyPaymentViewController: EarlyPaymentViewDelegate {
    func didTapBack() {
        flowDelegate?.dismissEarlyPayment()
    }

    func didToggleInstallment(id: Int) {
        viewModel.toggle(id: id)
        contentView.refreshSelection(with: viewModel)
    }

    func didToggleSelectAll() {
        viewModel.toggleSelectAll()
        contentView.refreshSelection(with: viewModel)
    }

    func didChangeDestination(chargeToOpenStatement: Bool) {
        viewModel.chargeToOpenStatement = chargeToOpenStatement
        contentView.refreshDestination(with: viewModel)
    }

    func didTapContinue() {
        // Read the date at confirm time rather than tracking every picker change: the field is the
        // source of truth, and an untouched field keeps the default the view model was built with.
        if let picked = contentView.dateInput.dateValue {
            viewModel.paymentDate = max(picked, viewModel.minimumPaymentDate)
        }

        let destinationText: String
        if case .openStatement(let card) = viewModel.destination {
            // Names the invoice rather than just the card, so the user can see which statement this
            // lands on before confirming.
            let target = viewModel.targetStatementLabel.map { "\(card.name) · \($0)" } ?? card.name
            destinationText = String(
                format: "earlyPayment.confirm.destination.statement".localized, target)
        } else {
            destinationText = "earlyPayment.confirm.destination.standalone".localized
        }

        let message = String(
            format: "earlyPayment.confirm.message".localized,
            viewModel.selectedCount,
            viewModel.selectedTotal.currencyString,
            DateFormatter.fullDateFormatter.string(from: viewModel.paymentDate),
            destinationText
        )

        let alert = UIAlertController(
            title: "earlyPayment.confirm.title".localized,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        alert.addAction(
            UIAlertAction(title: "earlyPayment.confirm.action".localized, style: .default) {
                [weak self] _ in
                self?.performEarlyPayment()
            })
        present(alert, animated: true)
    }

    private func performEarlyPayment() {
        contentView.startLoading()

        // Off the main thread: this writes several rows, recalculates statement totals and reschedules
        // notifications, which is enough work to drop frames on a large ledger.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = self.viewModel.confirm()
            DispatchQueue.main.async {
                self.contentView.stopLoading()
                switch result {
                case .success(let paymentId):
                    self.flowDelegate?.didCompleteEarlyPayment(paymentId: paymentId)
                case .failure(let error):
                    self.showEarlyPaymentError(error)
                }
            }
        }
    }

    private func showEarlyPaymentError(_ error: Error) {
        let alert = UIAlertController(
            title: "alert.error".localized,
            message: "earlyPayment.error.generic".localized,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default))
        present(alert, animated: true)
        logError("Early payment failed: \(error)")
    }
}
