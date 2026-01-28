//
//  UpdateToastView.swift
//  FinanceApp
//
//  Created by Arthur Rios on [Current Date]
//

import UIKit

protocol UpdateToastViewDelegate: AnyObject {
  func updateToastViewDidTapUpdate(_ toastView: UpdateToastView)
  func updateToastViewDidTapDismiss(_ toastView: UpdateToastView)
}

final class UpdateToastView: UIView {

  weak var delegate: UpdateToastViewDelegate?

  // MARK: - UI Components

  // Main container with native notification styling
  private let containerView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    return view
  }()

  // Native iOS notification background with proper blur and styling
  private let backgroundView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
    view.layer.cornerRadius = 16
    view.layer.masksToBounds = true
    return view
  }()

  // Blur effect for native iOS look
  private let blurEffectView: UIVisualEffectView = {
    let blurEffect = UIBlurEffect(style: .systemMaterial)
    let view = UIVisualEffectView(effect: blurEffect)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.layer.cornerRadius = 16
    view.layer.masksToBounds = true
    return view
  }()

  // Main content stack
  private let contentStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.axis = .vertical
    stackView.spacing = 12
    stackView.translatesAutoresizingMaskIntoConstraints = false
    return stackView
  }()

  // Header with icon, title, and dismiss button
  private let headerStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.axis = .horizontal
    stackView.alignment = .center
    stackView.distribution = .fill
    stackView.spacing = 12
    stackView.translatesAutoresizingMaskIntoConstraints = false
    return stackView
  }()

  // App icon placeholder (native notification style)
  private let iconImageView: UIImageView = {
    let imageView = UIImageView()
    imageView.image = UIImage(systemName: "arrow.clockwise.circle.fill")
    imageView.contentMode = .scaleAspectFit
    imageView.tintColor = Colors.mainMagenta
    imageView.translatesAutoresizingMaskIntoConstraints = false
    return imageView
  }()

  // Title and subtitle container
  private let textStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.axis = .vertical
    stackView.spacing = 2
    stackView.alignment = .leading
    stackView.distribution = .fill
    stackView.translatesAutoresizingMaskIntoConstraints = false
    return stackView
  }()

  // Main title (app name style)
  private let titleLabel: UILabel = {
    let label = UILabel()
    label.text = "Finova"
    label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
    label.textColor = UIColor.label
    label.numberOfLines = 1
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  // Subtitle (notification content)
  private let subtitleLabel: UILabel = {
    let label = UILabel()
    label.text = "updateToast.title".localized
    label.font = UIFont.systemFont(ofSize: 15, weight: .medium)
    label.textColor = UIColor.label
    label.numberOfLines = 1
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  // Dismiss button (native style)
  private let dismissButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "xmark"), for: .normal)
    button.tintColor = UIColor.secondaryLabel
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }()

  // Message body
  private let messageLabel: UILabel = {
    let label = UILabel()
    label.text = "updateToast.message".localized
    label.font = UIFont.systemFont(ofSize: 14, weight: .regular)
    label.textColor = UIColor.secondaryLabel
    label.numberOfLines = 2
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  // Action buttons container
  private let actionStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.axis = .horizontal
    stackView.spacing = 12
    stackView.distribution = .fillEqually
    stackView.translatesAutoresizingMaskIntoConstraints = false
    return stackView
  }()

  // Update button (primary action)
  private let updateButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("updateToast.updateButton".localized, for: .normal)
    button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
    button.setTitleColor(.white, for: .normal)
    button.backgroundColor = Colors.mainMagenta
    button.layer.cornerRadius = 8
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }()

  // Later button (secondary action)
  private let laterButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("updateToast.laterButton".localized, for: .normal)
    button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
    button.setTitleColor(Colors.mainMagenta, for: .normal)
    button.backgroundColor = UIColor.systemGray6
    button.layer.cornerRadius = 8
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }()

  // MARK: - Initialization

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
    setupConstraints()
    setupActions()
    setupLiquidGlassEffect()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Setup Methods

  private func setupView() {
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = .clear

    addSubview(containerView)
    containerView.addSubview(backgroundView)
    containerView.addSubview(blurEffectView)
    containerView.addSubview(contentStackView)

    // Setup content stack
    contentStackView.addArrangedSubview(headerStackView)
    contentStackView.addArrangedSubview(messageLabel)
    contentStackView.addArrangedSubview(actionStackView)

    // Setup header stack (icon, text stack, dismiss button)
    headerStackView.addArrangedSubview(iconImageView)
    headerStackView.addArrangedSubview(textStackView)
    headerStackView.addArrangedSubview(dismissButton)

    // Setup text stack (app name + notification title)
    textStackView.addArrangedSubview(titleLabel)
    textStackView.addArrangedSubview(subtitleLabel)

    // Setup action stack
    actionStackView.addArrangedSubview(updateButton)
    actionStackView.addArrangedSubview(laterButton)
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      // Container view
      containerView.topAnchor.constraint(equalTo: topAnchor),
      containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
      containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

      // Background view
      backgroundView.topAnchor.constraint(equalTo: containerView.topAnchor),
      backgroundView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      backgroundView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

      // Blur effect view
      blurEffectView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
      blurEffectView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
      blurEffectView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
      blurEffectView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

      // Content stack view
      contentStackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
      contentStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
      contentStackView.trailingAnchor.constraint(
        equalTo: containerView.trailingAnchor, constant: -16),
      contentStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),

      // Icon constraints (native notification size)
      iconImageView.widthAnchor.constraint(equalToConstant: 32),
      iconImageView.heightAnchor.constraint(equalToConstant: 32),

      // Dismiss button constraints
      dismissButton.widthAnchor.constraint(equalToConstant: 24),
      dismissButton.heightAnchor.constraint(equalToConstant: 24),

      // Button heights (native notification style)
      updateButton.heightAnchor.constraint(equalToConstant: 32),
      laterButton.heightAnchor.constraint(equalToConstant: 32),
    ])
  }

  private func setupActions() {
    updateButton.addTarget(self, action: #selector(updateButtonTapped), for: .touchUpInside)
    laterButton.addTarget(self, action: #selector(laterButtonTapped), for: .touchUpInside)
    dismissButton.addTarget(self, action: #selector(dismissButtonTapped), for: .touchUpInside)
  }

  private func setupLiquidGlassEffect() {
    // Native iOS notification shadow
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOffset = CGSize(width: 0, height: 2)
    layer.shadowRadius = 8
    layer.shadowOpacity = 0.15

    // Native iOS notification border
    backgroundView.layer.borderWidth = 0.5
    backgroundView.layer.borderColor = UIColor.separator.cgColor
  }

  // MARK: - Layout

  // MARK: - Actions

  @objc private func updateButtonTapped() {
    delegate?.updateToastViewDidTapUpdate(self)
  }

  @objc private func laterButtonTapped() {
    delegate?.updateToastViewDidTapDismiss(self)
  }

  @objc private func dismissButtonTapped() {
    delegate?.updateToastViewDidTapDismiss(self)
  }

  // MARK: - Animation Methods

  func show(animated: Bool = true) {
    if animated {
      alpha = 0
      transform = CGAffineTransform(translationX: 0, y: -20).scaledBy(x: 0.9, y: 0.9)

      UIView.animate(
        withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5
      ) {
        self.alpha = 1
        self.transform = .identity
      }
    } else {
      alpha = 1
      transform = .identity
    }
  }

  func hide(animated: Bool = true, completion: (() -> Void)? = nil) {
    if animated {
      UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
        self.alpha = 0
        self.transform = CGAffineTransform(translationX: 0, y: -20).scaledBy(x: 0.9, y: 0.9)
      } completion: { _ in
        completion?()
      }
    } else {
      alpha = 0
      completion?()
    }
  }
}
