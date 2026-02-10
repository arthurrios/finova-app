//
//  AdjustBalanceModalViewController.swift
//  Finova
//
//  Created by Arthur Rios on 09/02/26.
//

import UIKit

protocol AdjustBalanceModalFlowDelegate: AnyObject {
    func dismissAdjustBalanceModal()
    func didAdjustBalance()
}

final class AdjustBalanceModalViewController: UIViewController {

    // MARK: - Properties

    private let contentView = AdjustBalanceModalView()
    private let currentCalculatedBalance: Int
    weak var flowDelegate: AdjustBalanceModalFlowDelegate?

    // MARK: - Initialization

    init(currentBalance: Int) {
        self.currentCalculatedBalance = currentBalance
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
        contentView.configure(currentBalance: currentCalculatedBalance)
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

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        blurEffectView.addGestureRecognizer(tapGesture)

        view.addSubview(blurEffectView)
        view.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let heightConstraint = contentView.heightAnchor.constraint(
            equalTo: view.heightAnchor, multiplier: 0.45)
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true

        contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        contentView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.55)
            .isActive = true
    }

    @objc private func backgroundTapped() {
        flowDelegate?.dismissAdjustBalanceModal()
    }
}

// MARK: - AdjustBalanceModalViewDelegate

extension AdjustBalanceModalViewController: AdjustBalanceModalViewDelegate {

    func didTapClose() {
        flowDelegate?.dismissAdjustBalanceModal()
    }

    func didTapConfirm(realBalanceCents: Int) {
        let oldOffset = UIDUserDefaultsManager.shared.getCurrentUserBalanceOffset()
        let newOffset = realBalanceCents - currentCalculatedBalance + oldOffset
        UIDUserDefaultsManager.shared.setCurrentUserBalanceOffset(newOffset)
        flowDelegate?.didAdjustBalance()
    }
}

// MARK: - Keyboard Handling

extension AdjustBalanceModalViewController {

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
