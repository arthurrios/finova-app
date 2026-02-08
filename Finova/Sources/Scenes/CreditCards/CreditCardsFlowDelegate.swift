//
//  CreditCardsFlowDelegate.swift
//  Finova
//

protocol CreditCardsFlowDelegate: AnyObject {
    func dismissCreditCards()
    func navigateToAddCreditCard()
    func navigateToEditCreditCard(_ card: CreditCard)
}
