//
//  ViewController+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

extension UIViewController {
    func setupContentViewToBounds(contentView: UIView, respectingSafeArea: Bool = true) {
        view.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        let top    = respectingSafeArea ? view.safeAreaLayoutGuide.topAnchor    : view.topAnchor
        let bottom = view.bottomAnchor
        let lead   = respectingSafeArea ? view.safeAreaLayoutGuide.leadingAnchor: view.leadingAnchor
        let trail  = respectingSafeArea ? view.safeAreaLayoutGuide.trailingAnchor: view.trailingAnchor
        
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: top),
            contentView.bottomAnchor.constraint(equalTo: bottom),
            contentView.leadingAnchor.constraint(equalTo: lead),
            contentView.trailingAnchor.constraint(equalTo: trail)
        ])
    }
}

extension UIViewController {
    func startKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(notification:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(notification:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    func stopKeyboardObservers() {
        NotificationCenter.default.removeObserver(self)
    }
    
    func hideKeyboardWhenTappedAround() {
        let tap = UITapGestureRecognizer(
            target: self,
            action: #selector(UIViewController.dismissKeyboard)
        )
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func keyboardWillShow(notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let shift = keyboardFrame.height / 2
        UIView.animate(withDuration: 1) {
            self.view.frame.origin.y = -shift
        }
    }
    
    @objc private func keyboardWillHide(notification: Notification) {
        UIView.animate(withDuration: 1) {
            self.view.frame.origin.y = 0
        }
    }
}
