//
//  AddAllocationModalViewController.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import UIKit

protocol AddAllocationModalFlowDelegate: AnyObject {
    func dismissAllocationModal()
    func didSaveAllocation()
}

final class AddAllocationModalViewController: UIViewController {

    // MARK: - Properties

    private let contentView = AddAllocationModalView()
    private let allocationService: BudgetAllocationService
    private let monthAnchor: Int
    private let allocationToEdit: BudgetAllocation?
    weak var flowDelegate: AddAllocationModalFlowDelegate?

    private var isEditMode: Bool {
        allocationToEdit != nil
    }

    // MARK: - Initialization

    init(
        monthAnchor: Int,
        allocationToEdit: BudgetAllocation? = nil,
        allocationService: BudgetAllocationService = BudgetAllocationService()
    ) {
        self.monthAnchor = monthAnchor
        self.allocationToEdit = allocationToEdit
        self.allocationService = allocationService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        contentView.delegate = self
        setupView()

        if let allocation = allocationToEdit {
            contentView.configureForEdit(allocation: allocation)
        } else {
            configureAvailableCategories()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startModalKeyboardObservers()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopModalKeyboardObservers()
    }

    // MARK: - Setup

    private func setupView() {
        let blurEffect = UIBlurEffect(style: .dark)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.frame = view.bounds
        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Add tap gesture to dismiss on background tap
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        blurEffectView.addGestureRecognizer(tapGesture)

        view.addSubview(blurEffectView)
        view.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Height constraint for the modal
        let heightConstraint = contentView.heightAnchor.constraint(
            equalTo: view.heightAnchor, multiplier: 0.42)
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true

        // Minimum and maximum height
        contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        contentView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.6)
            .isActive = true
    }

    private func configureAvailableCategories() {
        let availableCategories = allocationService.getAvailableCategoriesForAllocation(monthAnchor: monthAnchor)
        contentView.configure(availableCategories: availableCategories)
    }

    @objc private func backgroundTapped() {
        flowDelegate?.dismissAllocationModal()
    }
}

// MARK: - AddAllocationModalViewDelegate

extension AddAllocationModalViewController: AddAllocationModalViewDelegate {

    func didTapClose() {
        flowDelegate?.dismissAllocationModal()
    }

    func didTapSave(category: TransactionCategory, amount: Int, isRecurring: Bool) {
        if let allocation = allocationToEdit, let allocationId = allocation.dbId {
            // Edit mode - check if recurring to show options
            let isRecurringAllocation = allocation.isRecurring || allocation.parentAllocationId != nil

            if isRecurringAllocation {
                showRecurringEditOptions(allocationId: allocationId, newAmount: amount)
            } else {
                // Non-recurring allocation - update directly
                performUpdate(allocationId: allocationId, newAmount: amount, option: .currentOnly)
            }
        } else {
            // Create mode - create new allocation
            do {
                try allocationService.createAllocation(
                    category: category,
                    amount: amount,
                    monthAnchor: monthAnchor,
                    isRecurring: isRecurring
                )
                flowDelegate?.didSaveAllocation()
            } catch {
                handleError(
                    title: "allocation.add.error.save.title".localized,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func showRecurringEditOptions(allocationId: Int, newAmount: Int) {
        logDebug("AddAllocationModal: showRecurringEditOptions - allocationId: \(allocationId), newAmount: \(newAmount)")

        let alert = UIAlertController(
            title: "allocation.edit.recurring.title".localized,
            message: "allocation.edit.recurring.message".localized,
            preferredStyle: .alert
        )

        // Edit only this month
        alert.addAction(UIAlertAction(
            title: "allocation.edit.recurring.current".localized,
            style: .default
        ) { [weak self] _ in
            logDebug("AddAllocationModal: User selected CURRENT ONLY option")
            self?.performUpdate(allocationId: allocationId, newAmount: newAmount, option: .currentOnly)
        })

        // Edit this and all future months
        alert.addAction(UIAlertAction(
            title: "allocation.edit.recurring.future".localized,
            style: .default
        ) { [weak self] _ in
            logDebug("AddAllocationModal: User selected FUTURE ONLY option")
            self?.performUpdate(allocationId: allocationId, newAmount: newAmount, option: .futureOnly)
        })

        // Edit all occurrences (past, present, and future)
        alert.addAction(UIAlertAction(
            title: "allocation.edit.recurring.all".localized,
            style: .default
        ) { [weak self] _ in
            logDebug("AddAllocationModal: User selected ALL option")
            self?.performUpdate(allocationId: allocationId, newAmount: newAmount, option: .all)
        })

        alert.addAction(UIAlertAction(
            title: "alert.cancel".localized,
            style: .cancel
        ))

        present(alert, animated: true)
    }

    private func performUpdate(allocationId: Int, newAmount: Int, option: AllocationEditOption) {
        logDebug("AddAllocationModal: performUpdate - allocationId: \(allocationId), newAmount: \(newAmount), option: \(option)")
        do {
            try allocationService.updateAllocationWithOption(
                id: allocationId,
                newAmount: newAmount,
                option: option
            )
            logDebug("AddAllocationModal: Update successful, calling flowDelegate?.didSaveAllocation()")
            flowDelegate?.didSaveAllocation()
        } catch {
            logError("AddAllocationModal: Update failed with error: \(error)")
            handleError(
                title: "allocation.edit.error.save.title".localized,
                message: error.localizedDescription
            )
        }
    }

    func handleError(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Keyboard Handling

extension AddAllocationModalViewController {

    func startModalKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modalKeyboardWillShow(notification:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modalKeyboardWillHide(notification:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    func stopModalKeyboardObservers() {
        NotificationCenter.default.removeObserver(
            self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(
            self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func modalKeyboardWillShow(notification: Notification) {
        guard
            let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                as? CGRect,
            let animationDuration = notification.userInfo?[
                UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else {
            return
        }

        let keyboardHeight = keyboardFrame.height
        let viewHeight = view.frame.height
        let keyboardTopY = viewHeight - keyboardHeight

        let modalBottomY = contentView.frame.maxY

        if modalBottomY > keyboardTopY {
            let overlap = modalBottomY - keyboardTopY
            let shiftAmount = min(overlap * 0.7, 200)

            UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseInOut]) {
                self.contentView.transform = CGAffineTransform(translationX: 0, y: -shiftAmount)
            }
        }
    }

    @objc private func modalKeyboardWillHide(notification: Notification) {
        guard
            let animationDuration = notification.userInfo?[
                UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }

        UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseInOut]) {
            self.contentView.transform = .identity
        }
    }
}
