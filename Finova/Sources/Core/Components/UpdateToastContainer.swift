//
//  UpdateToastContainer.swift
//  FinanceApp
//
//  Created by Arthur Rios on [Current Date]
//

import UIKit

final class UpdateToastContainer: UIView {

  private var toastView: UpdateToastView?
  private var isShowing = false

  // MARK: - Initialization

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupView() {
    backgroundColor = .clear
    isUserInteractionEnabled = true
  }

  // MARK: - Touch Handling

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    // Only intercept touches that are actually on the toast view
    if let toastView = toastView {
      let toastPoint = convert(point, to: toastView)
      if toastView.bounds.contains(toastPoint) {
        return super.hitTest(point, with: event)
      }
    }

    // For all other touches, return nil so they pass through to the underlying views
    return nil
  }

  // MARK: - Public Methods

  func showUpdateToast(delegate: UpdateToastViewDelegate) {
    guard !isShowing else { return }

    let toast = UpdateToastView()
    toast.delegate = delegate
    self.toastView = toast

    addSubview(toast)
    setupToastConstraints(toast)

    isShowing = true
    toast.show(animated: true)
  }

  func hideUpdateToast(animated: Bool = true, completion: (() -> Void)? = nil) {
    guard let toast = toastView, isShowing else {
      completion?()
      return
    }

    toast.hide(animated: animated) { [weak self] in
      toast.removeFromSuperview()
      self?.toastView = nil
      self?.isShowing = false
      completion?()
    }
  }

  private func setupToastConstraints(_ toast: UpdateToastView) {
    toast.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      // Native iOS notification positioning
      toast.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
      toast.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      toast.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      toast.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
    ])
  }
}
