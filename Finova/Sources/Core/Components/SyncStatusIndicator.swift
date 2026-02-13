//
//  SyncStatusIndicator.swift
//  Finova
//
//  Created by Arthur Rios on 12/02/26.
//

import UIKit

final class SyncStatusIndicator: UIView {
    enum Status {
        case idle
        case syncing
        case synced
        case error
        case offline
    }

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = Colors.gray400
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray400
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),

            statusLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Metrics.spacing1),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    func updateStatus(_ status: Status) {
        stopSpinning()

        switch status {
        case .idle:
            iconView.image = UIImage(systemName: "cloud")
            iconView.tintColor = Colors.gray400
            statusLabel.text = "sync.status.idle".localized
            statusLabel.textColor = Colors.gray400
        case .syncing:
            iconView.image = UIImage(systemName: "arrow.triangle.2.circlepath")
            iconView.tintColor = Colors.mainMagenta
            statusLabel.text = "sync.status.syncing".localized
            statusLabel.textColor = Colors.mainMagenta
            startSpinning()
        case .synced:
            iconView.image = UIImage(systemName: "checkmark.icloud")
            iconView.tintColor = Colors.mainGreen
            statusLabel.text = "sync.status.synced".localized
            statusLabel.textColor = Colors.mainGreen
        case .error:
            iconView.image = UIImage(systemName: "exclamationmark.icloud")
            iconView.tintColor = Colors.mainRed
            statusLabel.text = "sync.status.error".localized
            statusLabel.textColor = Colors.mainRed
        case .offline:
            iconView.image = UIImage(systemName: "icloud.slash")
            iconView.tintColor = Colors.gray400
            statusLabel.text = "sync.status.offline".localized
            statusLabel.textColor = Colors.gray400
        }
    }

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
