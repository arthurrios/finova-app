//
//  InitialSyncView.swift
//  Finova
//
//  Created by Arthur Rios on 17/03/26.
//

import UIKit

protocol InitialSyncViewDelegate: AnyObject {
    func didTapRetry()
    func didTapSkip()
}

final class InitialSyncView: UIView {

    // MARK: - State

    enum State {
        case syncing(phase: String, progress: Float)
        case error(String)
    }

    // MARK: - Properties

    weak var delegate: InitialSyncViewDelegate?
    private var currentPhase: String?
    private var isAnimatingPhase = false

    // MARK: - UI Elements

    private let logoImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "appLogo"))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleSM.font
        label.textColor = Colors.gray700
        label.textAlignment = .center
        label.text = "initialSync.status.syncing".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let phaseContainer: UIView = {
        let view = UIView()
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var phaseLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let progressBar: RoundedProgressBar = {
        let bar = RoundedProgressBar()
        bar.trackTintColor = Colors.gray200
        bar.progressTintColor = Colors.mainMagenta
        bar.cornerRadius = 3
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private let retryButton: Button = {
        let button = Button(variant: .base, label: "initialSync.retry".localized)
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.mainRed
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let skipButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("initialSync.skip".localized, for: .normal)
        button.setTitleColor(Colors.gray500, for: .normal)
        button.titleLabel?.font = Fonts.textSM.font
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupConstraints()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = Colors.gray100

        addSubview(logoImageView)
        addSubview(statusLabel)
        addSubview(phaseContainer)
        phaseContainer.addSubview(phaseLabel)
        addSubview(progressBar)
        addSubview(errorLabel)
        addSubview(retryButton)
        addSubview(skipButton)

        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            logoImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            logoImageView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -120),
            logoImageView.widthAnchor.constraint(equalToConstant: 80),
            logoImageView.heightAnchor.constraint(equalToConstant: 80),

            statusLabel.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: Metrics.spacing8),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing8),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing8),

            phaseContainer.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: Metrics.spacing3),
            phaseContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing8),
            phaseContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing8),
            phaseContainer.heightAnchor.constraint(equalToConstant: 24),

            phaseLabel.centerXAnchor.constraint(equalTo: phaseContainer.centerXAnchor),
            phaseLabel.centerYAnchor.constraint(equalTo: phaseContainer.centerYAnchor),

            progressBar.topAnchor.constraint(equalTo: phaseContainer.bottomAnchor, constant: Metrics.spacing6),
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing12),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing12),
            progressBar.heightAnchor.constraint(equalToConstant: 6),

            errorLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: Metrics.spacing6),
            errorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing8),
            errorLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing8),

            retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: Metrics.spacing6),
            retryButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            retryButton.widthAnchor.constraint(equalToConstant: 200),
            retryButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),

            skipButton.topAnchor.constraint(equalTo: retryButton.bottomAnchor, constant: Metrics.spacing3),
            skipButton.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    // MARK: - State Updates

    func setState(_ state: State) {
        switch state {
        case .syncing(let phase, let progress):
            showSyncing(phase: phase, progress: progress)
        case .error(let message):
            showError(message)
        }
    }

    private func showSyncing(phase: String, progress: Float) {
        statusLabel.text = "initialSync.status.syncing".localized
        statusLabel.textColor = Colors.gray700
        errorLabel.isHidden = true
        retryButton.isHidden = true
        skipButton.isHidden = true
        progressBar.isHidden = false

        progressBar.setProgress(progress, animated: true)
        updatePhase(phase)
    }

    private func showError(_ message: String) {
        statusLabel.text = "initialSync.status.error".localized
        statusLabel.textColor = Colors.mainRed
        errorLabel.text = message
        errorLabel.isHidden = false
        retryButton.isHidden = false
        skipButton.isHidden = false
        progressBar.isHidden = true
    }

    // MARK: - Animated Phase Transitions

    func updatePhase(_ newPhase: String) {
        guard newPhase != currentPhase else { return }
        currentPhase = newPhase

        // Cancel any in-progress animation and clean up stale labels
        if isAnimatingPhase {
            phaseContainer.layer.removeAllAnimations()
            for subview in phaseContainer.subviews where subview !== phaseLabel {
                subview.removeFromSuperview()
            }
        }

        let outgoing = phaseLabel
        // Reset outgoing state in case a previous animation left it mid-transition
        outgoing.alpha = 1
        outgoing.transform = .identity

        let incoming = UILabel()
        incoming.font = Fonts.textSM.font
        incoming.textColor = Colors.gray500
        incoming.textAlignment = .center
        incoming.text = newPhase.localized
        incoming.alpha = 0
        incoming.transform = CGAffineTransform(translationX: 0, y: 20)
        incoming.translatesAutoresizingMaskIntoConstraints = false

        phaseContainer.addSubview(incoming)
        NSLayoutConstraint.activate([
            incoming.centerXAnchor.constraint(equalTo: phaseContainer.centerXAnchor),
            incoming.centerYAnchor.constraint(equalTo: phaseContainer.centerYAnchor),
        ])

        isAnimatingPhase = true
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            outgoing.alpha = 0
            outgoing.transform = CGAffineTransform(translationX: 0, y: -20)
            incoming.alpha = 1
            incoming.transform = .identity
        } completion: { [weak self] finished in
            guard let self else { return }
            outgoing.removeFromSuperview()
            self.phaseLabel = incoming
            self.isAnimatingPhase = false
        }
    }

    // MARK: - Actions

    @objc private func retryTapped() {
        delegate?.didTapRetry()
    }

    @objc private func skipTapped() {
        delegate?.didTapSkip()
    }
}
