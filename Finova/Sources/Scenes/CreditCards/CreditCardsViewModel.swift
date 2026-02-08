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
