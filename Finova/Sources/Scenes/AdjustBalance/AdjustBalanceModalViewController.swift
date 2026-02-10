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
    private var bottomConstraint: NSLayoutConstraint?
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

        let bottom = contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        self.bottomConstraint = bottom

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom
        ])
    }

    @objc private func backgroundTapped() {
        flowDelegate?.dismissAdjustBalanceModal()
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
        else { return }

        bottomConstraint?.constant = -keyboardFrame.height

        UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseInOut]) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func modalKeyboardWillHide(notification: Notification) {
        guard
            let animationDuration = notification.userInfo?[
                UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }

        bottomConstraint?.constant = 0

        UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseInOut]) {
            self.view.layoutIfNeeded()
        }
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
