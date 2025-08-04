//
//  AddTransactionViewController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/05/25.
//

import Foundation
import UIKit

final class AddTransactionModalViewController: UIViewController {
    let viewModel: AddTransactionModalViewModel
    let contentView: AddTransactionModalView
    weak var flowDelegate: AddTransactionModalFlowDelegate?
    
    init(
        contentView: AddTransactionModalView, flowDelegate: AddTransactionModalFlowDelegate,
        viewModel: AddTransactionModalViewModel
    ) {
        self.contentView = contentView
        self.flowDelegate = flowDelegate
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 🔒 Authenticate SecureLocalDataManager for UID-isolated data access
        if let user = UserDefaultsManager.getUser(), let firebaseUID = user.firebaseUID {
            SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)
            print("🔒 AddTransactionModal: SecureLocalDataManager authenticated for user: \(firebaseUID)")
        }
        
        contentView.delegate = self
        contentView.incomeSelectorButton.delegate = self
        contentView.expenseSelectorButton.delegate = self
        
        setupView()
        
        // Start animation immediately
        DispatchQueue.main.async {
            self.animateShow()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startKeyboardObservers()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Animation is now handled in viewDidLoad
    }
    
    private func setupView() {
        let blurEffect = UIBlurEffect(style: .dark)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.translatesAutoresizingMaskIntoConstraints = false
        
        setupGesture(viewTapped: blurEffectView)
        
        view.addSubview(blurEffectView)
        view.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        // Make blur view fill entire screen including beyond safe area
        NSLayoutConstraint.activate([
            blurEffectView.topAnchor.constraint(equalTo: view.topAnchor),
            blurEffectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurEffectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurEffectView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        setupConstraints()
        
        // Position content view off-screen initially (will be animated in viewDidAppear)
        contentView.transform = CGAffineTransform(translationX: 0, y: view.bounds.height)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Use a priority-based approach for flexible height
        let heightConstraint = contentView.heightAnchor.constraint(
            equalTo: view.heightAnchor, multiplier: 0.56)
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true
        
        // Add a minimum height constraint to ensure content is always visible
        contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        
        // Add a maximum height constraint to prevent oversizing
        contentView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.75)
            .isActive = true
    }
    
    private func setupGesture(viewTapped: UIView) {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissModal))
        viewTapped.addGestureRecognizer(tapGestureRecognizer)
    }
    
    @objc
    private func dismissModal() {
        dismiss(animated: true)
    }
    
    func animateShow() {
        UIView.animate(
            withDuration: 0.3,
            animations: {
                self.contentView.transform = .identity
            })
    }
}

extension AddTransactionModalViewController: AddTransactionModalViewDelegate,
                                             TransactionTypeSelectorDelegate {
    
    func sendInstallmentTransactionData(_ data: InstallmentTransactionData) {
        let result = viewModel.addTransactionWithInstallments(data)
        handleTransactionResult(result)
    }
    
    func handleError(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let retryAction = UIAlertAction(title: "alert.ok".localized, style: .default)
        alertController.addAction(retryAction)
        self.present(alertController, animated: true)
    }
    
    func sendTransactionData(_ data: AddTransactionData) {
        let result = viewModel.addTransaction(
            title: data.title,
            amount: data.amount,
            dateString: data.date,
            categoryKey: data.category,
            typeRaw: data.transactionType)
        
        handleTransactionResult(result)
    }
    
    func sendRecurringTransactionData(_ data: AddTransactionData) {
        let result = viewModel.addTransaction(
            title: data.title,
            amount: data.amount,
            dateString: data.date,
            categoryKey: data.category,
            typeRaw: data.transactionType,
            isRecurring: true
        )
        
        handleTransactionResult(result)
    }
    
    private func handleTransactionResult(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            dismissModal()
            flowDelegate?.didAddTransaction()
        case .failure(let error):
            let message: String
            switch error {
            case TransactionError.invalidDateFormat:
                message = "alert.error.invalidDateFormat".localized
            case TransactionError.invalidCategory:
                message = "alert.error.invalidCategory".localized
            case TransactionError.invalidType:
                message = "alert.error.invalidTransactionType".localized
            case TransactionError.invalidInstallmentCount:
                message = "alert.error.invalidInstallmentCount".localized
            default:
                message = "alert.error.defaultMessage".localized
            }
            handleError(title: "alert.error.title".localized, message: message)
        }
    }
    
    func transactionTypeSelectorDidSelect(_ selector: TransactionTypeSelector) {
        if selector.variant == .selected {
            contentView.incomeSelectorButton.variant = .normal
            contentView.expenseSelectorButton.variant = .normal
        } else {
            if selector.transactionType == .income {
                contentView.incomeSelectorButton.variant = .selected
                contentView.expenseSelectorButton.variant = .unselected
            } else {
                contentView.expenseSelectorButton.variant = .selected
                contentView.incomeSelectorButton.variant = .unselected
            }
        }
    }
    
    func closeModal() {
        dismissModal()
    }
}
