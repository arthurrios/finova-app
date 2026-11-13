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
