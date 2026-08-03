//
//  EarlyPaymentFlowDelegate.swift
//  Finova
//

protocol EarlyPaymentFlowDelegate: AnyObject {
    func dismissEarlyPayment()
    /// The early payment was booked. `paymentId` is the debit that was created, so the flow can take
    /// the user straight to it.
    func didCompleteEarlyPayment(paymentId: Int)
}
