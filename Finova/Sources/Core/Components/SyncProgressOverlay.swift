//
//  SyncProgressOverlay.swift
//  Finova
//
//  Created by Arthur Rios on 05/03/26.
//

import UIKit

final class SyncProgressOverlay: UIView {

    // MARK: - UI Components

    private let backgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let contentCard: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 12
        view.layer.shadowOpacity = 0.15
        return view
    }()

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "cloud.fill")
        iv.contentMode = .scaleAspectFit
        iv.tintColor = Colors.mainMagenta
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleXS.font
        label.textColor = Colors.gray100
        label.text = "sync.overlay.title".localized
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray400
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let progressBar: RoundedProgressBar = {
        let bar = RoundedProgressBar()
        bar.trackTintColor = Colors.gray600
        bar.progressTintColor = Colors.mainMagenta
        bar.cornerRadius = 4
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private let percentageLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.mainMagenta
        label.textAlignment = .center
        label.text = "0%"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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

        addSubview(backgroundView)
        addSubview(contentCard)

        contentCard.addSubview(iconView)
        contentCard.addSubview(titleLabel)
        contentCard.addSubview(descriptionLabel)
        contentCard.addSubview(progressBar)
        contentCard.addSubview(percentageLabel)

        let cardWidth = min(280, UIScreen.main.bounds.width * 0.8)
        let padding = Metrics.spacing5

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentCard.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentCard.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentCard.widthAnchor.constraint(equalToConstant: cardWidth),

            iconView.topAnchor.constraint(equalTo: contentCard.topAnchor, constant: padding),
            iconView.centerXAnchor.constraint(equalTo: contentCard.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: Metrics.spacing3),
            titleLabel.leadingAnchor.constraint(equalTo: contentCard.leadingAnchor, constant: padding),
            titleLabel.trailingAnchor.constraint(equalTo: contentCard.trailingAnchor, constant: -padding),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Metrics.spacing1),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentCard.leadingAnchor, constant: padding),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentCard.trailingAnchor, constant: -padding),

            progressBar.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: Metrics.spacing4),
            progressBar.leadingAnchor.constraint(equalTo: contentCard.leadingAnchor, constant: padding),
            progressBar.trailingAnchor.constraint(equalTo: contentCard.trailingAnchor, constant: -padding),
            progressBar.heightAnchor.constraint(equalToConstant: 8),

            percentageLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: Metrics.spacing2),
            percentageLabel.centerXAnchor.constraint(equalTo: contentCard.centerXAnchor),
            percentageLabel.bottomAnchor.constraint(equalTo: contentCard.bottomAnchor, constant: -padding),
        ])

        startSpinning()
    }

    // MARK: - Public API

    func updateProgress(_ phaseProgress: SyncPhaseProgress) {
        let percent = Int(phaseProgress.progress * 100)
        percentageLabel.text = "\(percent)%"
        descriptionLabel.text = phaseProgress.phaseKey.localized
        progressBar.setProgress(phaseProgress.progress, animated: true)
    }

    func show(animated: Bool = true) {
        if animated {
            backgroundView.alpha = 0
            contentCard.alpha = 0
            contentCard.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)

            UIView.animate(
                withDuration: 0.3, delay: 0,
                usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5
            ) {
                self.backgroundView.alpha = 1
                self.contentCard.alpha = 1
                self.contentCard.transform = .identity
            }
        } else {
            backgroundView.alpha = 1
            contentCard.alpha = 1
            contentCard.transform = .identity
        }
    }

    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        // Set to 100% briefly before dismissing
        percentageLabel.text = "100%"
        descriptionLabel.text = "sync.phase.complete".localized
        progressBar.setProgress(1.0, animated: true)

        let dismissBlock = { [weak self] in
            if animated {
                UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
                    self?.backgroundView.alpha = 0
                    self?.contentCard.alpha = 0
                    self?.contentCard.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
                } completion: { _ in
                    self?.stopSpinning()
                    self?.removeFromSuperview()
                    completion?()
                }
            } else {
                self?.stopSpinning()
                self?.removeFromSuperview()
                completion?()
            }
        }

        // Brief pause at 100% before fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: dismissBlock)
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
