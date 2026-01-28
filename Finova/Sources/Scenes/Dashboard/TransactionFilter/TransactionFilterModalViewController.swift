//
//  TransactionFilterModalViewController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 26/01/26.
//

import Foundation
import UIKit

protocol TransactionFilterModalDelegate: AnyObject {
  func transactionFilterModal(_ modal: TransactionFilterModalViewController, didApplyFilters filters: TransactionFilters)
  func transactionFilterModalDidClear(_ modal: TransactionFilterModalViewController)
}

final class TransactionFilterModalViewController: UIViewController {
  weak var delegate: TransactionFilterModalDelegate?
  
  private let contentView = TransactionFilterModalView()
  private var currentFilters: TransactionFilters
  private var monthDate: Date
  
  init(currentFilters: TransactionFilters = TransactionFilters(), monthDate: Date) {
    self.currentFilters = currentFilters
    self.monthDate = monthDate
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .overFullScreen
    modalTransitionStyle = .crossDissolve
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    setup()
    contentView.configure(with: currentFilters, monthDate: monthDate)
  }
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    animateShow()
  }
  
  private func setup() {
    view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
    
    contentView.translatesAutoresizingMaskIntoConstraints = false
    contentView.delegate = self
    view.addSubview(contentView)
    
    setupConstraints()
    setupDismissGesture()
  }
  
  private func setupConstraints() {
    NSLayoutConstraint.activate([
      contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      contentView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.7),
    ])
  }
  
  private func setupDismissGesture() {
    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
    tapGesture.delegate = self
    view.addGestureRecognizer(tapGesture)
  }
  
  @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
    let location = gesture.location(in: view)
    if !contentView.frame.contains(location) {
      dismissModal()
    }
  }
  
  private func animateShow() {
    view.layoutIfNeeded()
    contentView.transform = CGAffineTransform(translationX: 0, y: contentView.frame.height)
    UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
      self.contentView.transform = .identity
      self.view.layoutIfNeeded()
    }
  }
  
  private func dismissModal() {
    UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn, animations: {
      self.contentView.transform = CGAffineTransform(translationX: 0, y: self.contentView.frame.height)
    }) { _ in
      self.dismiss(animated: false)
    }
  }
}

// MARK: - TransactionFilterModalViewDelegate
extension TransactionFilterModalViewController: TransactionFilterModalViewDelegate {
  func didTapClose() {
    dismissModal()
  }
  
  func didTapApply(filters: TransactionFilters) {
    delegate?.transactionFilterModal(self, didApplyFilters: filters)
    dismissModal()
  }
  
  func didTapClear() {
    delegate?.transactionFilterModalDidClear(self)
    dismissModal()
  }
}

// MARK: - UIGestureRecognizerDelegate
extension TransactionFilterModalViewController: UIGestureRecognizerDelegate {
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    return touch.view == view
  }
}

