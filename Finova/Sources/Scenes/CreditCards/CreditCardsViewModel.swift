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

    /// Async because deleting a card is a batch: it walks every statement to cancel its
    /// notifications, soft-deletes the card and its statements, and marks rows for CloudKit deletion.
    /// Run inline that blocked the main thread for the whole card and reloaded the list before the
    /// writes had landed.
    func deleteCard(_ card: CreditCard, completion: @escaping (Bool) -> Void) {
        guard let id = card.id else {
            completion(false)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let deleted = self?.cardRepo.deleteCard(id: id) ?? false
            DispatchQueue.main.async {
                if deleted { self?.loadCards() }
                completion(deleted)
            }
        }
    }
}
