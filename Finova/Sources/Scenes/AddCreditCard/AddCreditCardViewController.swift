//
//  AddCreditCardViewController.swift
//  Finova
//

import UIKit

final class AddCreditCardViewController: UIViewController {
    let contentView: AddCreditCardView
    private let viewModel: AddCreditCardViewModel
    weak var flowDelegate: AddCreditCardFlowDelegate?

    init(contentView: AddCreditCardView, viewModel: AddCreditCardViewModel, flowDelegate: AddCreditCardFlowDelegate) {
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
        if let card = viewModel.cardToEdit {
            contentView.configureForEdit(card)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private func setup() {
        view.addSubview(contentView)
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
        contentView.delegate = self
        hideKeyboardWhenTappedAround()
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardHeight = keyboardFrame.height
        contentView.scrollView.contentInset.bottom = keyboardHeight
        contentView.scrollView.verticalScrollIndicatorInsets.bottom = keyboardHeight
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        contentView.scrollView.contentInset.bottom = 0
        contentView.scrollView.verticalScrollIndicatorInsets.bottom = 0
    }
}

extension AddCreditCardViewController: AddCreditCardViewDelegate {
    func didTapBack() {
        flowDelegate?.dismissAddCreditCard()
    }

    func didTapSave() {
        // Dismiss keyboard first
        view.endEditing(true)

        // Validate inputs - highlights errors and scrolls to first invalid
        guard contentView.validateInputs() else { return }

        let name = contentView.nameInput.text ?? ""
        let lastFour = contentView.lastFourInput.text ?? ""
        let brandIndex = contentView.brandSelector.selectedPickerIndex
        let closingDay = Int(contentView.closingDayInput.text ?? "15") ?? 15
        let dueDay = Int(contentView.dueDayInput.text ?? "22") ?? 22

        var creditLimit: Int?
        let limitCents = contentView.creditLimitInput.centsValue
        if limitCents > 0 {
            creditLimit = limitCents
        }

        let success = viewModel.saveCard(
            name: name, lastFour: lastFour, brandIndex: brandIndex,
            closingDay: closingDay, dueDay: dueDay,
            creditLimit: creditLimit, cardColor: contentView.selectedColor,
            isDefault: contentView.isDefaultCard
        )

        if success {
            flowDelegate?.didSaveCreditCard()
        }
    }
}
