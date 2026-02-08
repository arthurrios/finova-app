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
