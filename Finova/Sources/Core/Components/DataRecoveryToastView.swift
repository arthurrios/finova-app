//
//  DataRecoveryToastView.swift
//  Finova
//
//  Created by Arthur Rios on 13/09/25.
//

import UIKit

protocol DataRecoveryToastViewDelegate: AnyObject {
  func dataRecoveryToastViewDidTapRecover(_ toastView: DataRecoveryToastView)
  func dataRecoveryToastViewDidTapDismiss(_ toastView: DataRecoveryToastView)
}

final class DataRecoveryToastView: UIView {

  weak var delegate: DataRecoveryToastViewDelegate?

  // MARK: - UI Components
  private let containerView = UIView()
  private let iconImageView = UIImageView()
  private let titleLabel = UILabel()
  private let messageLabel = UILabel()
  private let recoverButton = UIButton(type: .system)
  private let laterButton = UIButton(type: .system)
  private let buttonStackView = UIStackView()
  private let closeButton = UIButton(type: .system)

  // MARK: - Properties
  private var isVisible = false

  // MARK: - Initialization
  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }

  // MARK: - Setup
  private func setupView() {
    backgroundColor = UIColor.black.withAlphaComponent(0.3)
    isHidden = true

    setupContainerView()
    setupIconImageView()
    setupTitleLabel()
    setupMessageLabel()
    setupRecoverButton()
    setupLaterButton()
    setupButtonStackView()
    setupCloseButton()
    setupConstraints()

    // Add tap gesture to dismiss when tapping outside
    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
    addGestureRecognizer(tapGesture)
  }

  private func setupContainerView() {
    containerView.backgroundColor = UIColor.systemBackground
    containerView.layer.cornerRadius = 16
    containerView.layer.shadowColor = UIColor.black.cgColor
    containerView.layer.shadowOffset = CGSize(width: 0, height: 4)
    containerView.layer.shadowRadius = 12
    containerView.layer.shadowOpacity = 0.15
    containerView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(containerView)
  }

  private func setupIconImageView() {
    iconImageView.image = UIImage(systemName: "arrow.clockwise.circle.fill")
    iconImageView.tintColor = Colors.mainMagenta
    iconImageView.contentMode = .scaleAspectFit
    iconImageView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(iconImageView)
  }

  private func setupTitleLabel() {
    titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
    titleLabel.textColor = Colors.gray700
    titleLabel.numberOfLines = 0
    titleLabel.textAlignment = .center
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = "🚨 Data Recovery Available"
    containerView.addSubview(titleLabel)
  }

  private func setupMessageLabel() {
    messageLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
    messageLabel.textColor = Colors.gray600
    messageLabel.numberOfLines = 0
    messageLabel.textAlignment = .center
    messageLabel.translatesAutoresizingMaskIntoConstraints = false
    messageLabel.text =
      "We detected that your data may need to be recovered from a previous version. Tap 'Recover' to restore your transactions and budgets."
    containerView.addSubview(messageLabel)
  }

  private func setupRecoverButton() {
    recoverButton.backgroundColor = Colors.mainMagenta
    recoverButton.setTitleColor(.white, for: .normal)
    recoverButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
    recoverButton.layer.cornerRadius = 8
    recoverButton.translatesAutoresizingMaskIntoConstraints = false
    recoverButton.setTitle("Recover My Data", for: .normal)
    recoverButton.addTarget(self, action: #selector(recoverButtonTapped), for: .touchUpInside)
  }

  private func setupLaterButton() {
    laterButton.backgroundColor = Colors.gray200
    laterButton.setTitleColor(Colors.gray700, for: .normal)
    laterButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
    laterButton.layer.cornerRadius = 8
    laterButton.translatesAutoresizingMaskIntoConstraints = false
    laterButton.setTitle("Later", for: .normal)
    laterButton.addTarget(self, action: #selector(laterButtonTapped), for: .touchUpInside)
  }

  private func setupButtonStackView() {
    buttonStackView.axis = .horizontal
    buttonStackView.distribution = .fillEqually
    buttonStackView.spacing = 12
    buttonStackView.translatesAutoresizingMaskIntoConstraints = false

    buttonStackView.addArrangedSubview(laterButton)
    buttonStackView.addArrangedSubview(recoverButton)
    containerView.addSubview(buttonStackView)
  }

  private func setupCloseButton() {
    closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
    closeButton.tintColor = Colors.gray400
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
    containerView.addSubview(closeButton)
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      // Container constraints
      containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
      containerView.centerYAnchor.constraint(equalTo: centerYAnchor),
      containerView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
      containerView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
      containerView.widthAnchor.constraint(lessThanOrEqualToConstant: 350),

      // Close button constraints
      closeButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
      closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
      closeButton.widthAnchor.constraint(equalToConstant: 24),
      closeButton.heightAnchor.constraint(equalToConstant: 24),

      // Icon constraints
      iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
      iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
      iconImageView.widthAnchor.constraint(equalToConstant: 48),
      iconImageView.heightAnchor.constraint(equalToConstant: 48),

      // Title constraints
      titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 16),
      titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
      titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

      // Message constraints
      messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
      messageLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
      messageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

      // Button stack constraints
      buttonStackView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 24),
      buttonStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
      buttonStackView.trailingAnchor.constraint(
        equalTo: containerView.trailingAnchor, constant: -20),
      buttonStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20),
      buttonStackView.heightAnchor.constraint(equalToConstant: 44),
    ])
  }

  // MARK: - Animation Methods
  func show(animated: Bool = true) {
    isHidden = false
    isVisible = true

    if animated {
      alpha = 0
      containerView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)

      UIView.animate(
        withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.2
      ) {
        self.alpha = 1
        self.containerView.transform = .identity
      }
    } else {
      alpha = 1
      containerView.transform = .identity
    }
  }

  func hide(animated: Bool = true, completion: (() -> Void)? = nil) {
    guard isVisible else {
      completion?()
      return
    }

    isVisible = false

    if animated {
      UIView.animate(
        withDuration: 0.25,
        animations: {
          self.alpha = 0
          self.containerView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }
      ) { _ in
        self.isHidden = true
        completion?()
      }
    } else {
      alpha = 0
      isHidden = true
      completion?()
    }
  }

  // MARK: - Actions
  @objc private func recoverButtonTapped() {
    delegate?.dataRecoveryToastViewDidTapRecover(self)
  }

  @objc private func laterButtonTapped() {
    delegate?.dataRecoveryToastViewDidTapDismiss(self)
  }

  @objc private func closeButtonTapped() {
    delegate?.dataRecoveryToastViewDidTapDismiss(self)
  }

  @objc private func backgroundTapped() {
    delegate?.dataRecoveryToastViewDidTapDismiss(self)
  }
}
