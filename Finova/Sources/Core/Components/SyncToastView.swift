//
//  SyncToastView.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class SyncToastView: UIView {

    // MARK: - UI Components

    private let blurEffectView: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let view = UIVisualEffectView(effect: blurEffect)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.masksToBounds = true
        return view
    }()

    private let backgroundView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
        view.layer.masksToBounds = true
        return view
    }()

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = Colors.gray400
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray400
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let batchLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let outerStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        addSubview(backgroundView)
        addSubview(blurEffectView)
        addSubview(outerStack)

        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(statusLabel)

        outerStack.addArrangedSubview(contentStack)
        outerStack.addArrangedSubview(batchLabel)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            blurEffectView.topAnchor.constraint(equalTo: topAnchor),
            blurEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            outerStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
        ])

        // Shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 6
        layer.shadowOpacity = 0.12

        // Border
        backgroundView.layer.borderWidth = 0.5
        backgroundView.layer.borderColor = UIColor.separator.cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pillRadius = bounds.height / 2
        backgroundView.layer.cornerRadius = pillRadius
        blurEffectView.layer.cornerRadius = pillRadius
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: pillRadius).cgPath
    }

    // MARK: - Public API

    func updatePushProgress(_ progress: SyncPushProgress) {
        stopSpinning()

        iconView.image = UIImage(systemName: "arrow.triangle.2.circlepath")
        iconView.tintColor = Colors.mainMagenta
        statusLabel.text = "sync.toast.uploading".localized
        statusLabel.textColor = Colors.mainMagenta
        startSpinning()

        batchLabel.text = String(format: "sync.toast.batchProgress".localized, progress.currentBatch, progress.totalBatches)
        batchLabel.isHidden = false
    }

    func updateStatus(_ status: SyncStatusIndicator.Status) {
        stopSpinning()
        batchLabel.isHidden = true

        switch status {
        case .syncing:
            iconView.image = UIImage(systemName: "arrow.triangle.2.circlepath")
            iconView.tintColor = Colors.mainMagenta
            statusLabel.text = "sync.toast.syncing".localized
            statusLabel.textColor = Colors.mainMagenta
            startSpinning()
        case .synced:
            iconView.image = UIImage(systemName: "checkmark.icloud")
            iconView.tintColor = Colors.mainGreen
            statusLabel.text = "sync.toast.synced".localized
            statusLabel.textColor = Colors.mainGreen
        case .error:
            iconView.image = UIImage(systemName: "exclamationmark.icloud")
            iconView.tintColor = Colors.mainRed
            statusLabel.text = "sync.toast.error".localized
            statusLabel.textColor = Colors.mainRed
        case .idle, .offline:
            iconView.image = UIImage(systemName: "cloud")
            iconView.tintColor = Colors.gray400
            statusLabel.text = "sync.status.idle".localized
            statusLabel.textColor = Colors.gray400
        }
    }

    // MARK: - Animations

    func show(animated: Bool = true) {
        if animated {
            alpha = 0
            transform = CGAffineTransform(translationX: 0, y: -15)

            UIView.animate(
                withDuration: 0.35, delay: 0,
                usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5
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
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
                self.alpha = 0
                self.transform = CGAffineTransform(translationX: 0, y: -15)
            } completion: { _ in
                completion?()
            }
        } else {
            alpha = 0
            completion?()
        }
    }

    // MARK: - Spin Animation

    private func startSpinning() {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.toValue = NSNumber(value: Double.pi * 2)
        rotation.duration = 1.5
        rotation.repeatCount = .infinity
        rotation.isCumulative = true
        iconView.layer.add(rotation, forKey: "rotationAnimation")
    }

    private func stopSpinning() {
        iconView.layer.removeAnimation(forKey: "rotationAnimation")
    }
}
