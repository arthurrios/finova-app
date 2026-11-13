//
//  ImportReviewView.swift
//  Finova
//

import UIKit

protocol ImportReviewViewDelegate: AnyObject {
    func didTapApply()
    func didTapCancel()
    func didTapResolveSigns(asWritten: Bool)
}

final class ImportReviewView: UIView {

    weak var delegate: ImportReviewViewDelegate?

    /// Same shape as `CloudCleanupView`: one enum, one entry point, no half-states possible.
    enum State {
        case reviewing(summary: String, net: Int, canApply: Bool, warning: String?, needsSignDecision: Bool)
        case applying(done: Int, total: Int)
        case failed(String)
    }

    let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .grouped)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private let warningLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.mainRed
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let signPromptContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.cornerRadius = CornerRadius.large
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let signPromptLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray700
        label.numberOfLines = 0
        label.text = "import.review.signPrompt".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var signAsWrittenButton = makeSmallButton("import.review.signPrompt.asWritten")
    private lazy var signInvertedButton = makeSmallButton("import.review.signPrompt.inverted")

    private let summaryLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray600
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let netLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray700
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let progressBar: RoundedProgressBar = {
        let bar = RoundedProgressBar()
        bar.trackTintColor = Colors.gray200
        bar.progressTintColor = Colors.mainMagenta
        bar.cornerRadius = 3
        bar.isHidden = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private let applyButton = Button(variant: .base, label: "import.review.apply".localized)
    private let cancelButton = Button(variant: .outlined, label: "import.review.cancel".localized)

    private let footerContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray200
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray200
        setupLayout()
        setupActions()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeSmallButton(_ key: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(key.localized, for: .normal)
        button.titleLabel?.font = Fonts.textSMBold.font
        button.setTitleColor(Colors.mainMagenta, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func setupLayout() {
        addSubview(tableView)
        addSubview(footerContainer)
        [warningLabel, signPromptContainer, summaryLabel, netLabel, progressBar,
         applyButton, cancelButton].forEach(footerContainer.addSubview)
        [signPromptLabel, signAsWrittenButton, signInvertedButton]
            .forEach(signPromptContainer.addSubview)

        [applyButton, cancelButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: footerContainer.topAnchor),

            footerContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            warningLabel.topAnchor.constraint(
                equalTo: footerContainer.topAnchor, constant: Metrics.spacing3),
            warningLabel.leadingAnchor.constraint(
                equalTo: footerContainer.leadingAnchor, constant: Metrics.spacing4),
            warningLabel.trailingAnchor.constraint(
                equalTo: footerContainer.trailingAnchor, constant: -Metrics.spacing4),

            signPromptContainer.topAnchor.constraint(
                equalTo: warningLabel.bottomAnchor, constant: Metrics.spacing2),
            signPromptContainer.leadingAnchor.constraint(equalTo: warningLabel.leadingAnchor),
            signPromptContainer.trailingAnchor.constraint(equalTo: warningLabel.trailingAnchor),

            signPromptLabel.topAnchor.constraint(
                equalTo: signPromptContainer.topAnchor, constant: Metrics.spacing3),
            signPromptLabel.leadingAnchor.constraint(
                equalTo: signPromptContainer.leadingAnchor, constant: Metrics.spacing3),
            signPromptLabel.trailingAnchor.constraint(
                equalTo: signPromptContainer.trailingAnchor, constant: -Metrics.spacing3),

            signAsWrittenButton.topAnchor.constraint(
                equalTo: signPromptLabel.bottomAnchor, constant: Metrics.spacing2),
            signAsWrittenButton.leadingAnchor.constraint(equalTo: signPromptLabel.leadingAnchor),
            signAsWrittenButton.bottomAnchor.constraint(
                equalTo: signPromptContainer.bottomAnchor, constant: -Metrics.spacing3),

            signInvertedButton.centerYAnchor.constraint(equalTo: signAsWrittenButton.centerYAnchor),
            signInvertedButton.leadingAnchor.constraint(
                equalTo: signAsWrittenButton.trailingAnchor, constant: Metrics.spacing5),

            summaryLabel.topAnchor.constraint(
                equalTo: signPromptContainer.bottomAnchor, constant: Metrics.spacing3),
            summaryLabel.leadingAnchor.constraint(equalTo: warningLabel.leadingAnchor),

            netLabel.centerYAnchor.constraint(equalTo: summaryLabel.centerYAnchor),
            netLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: summaryLabel.trailingAnchor, constant: Metrics.spacing2),
            netLabel.trailingAnchor.constraint(equalTo: warningLabel.trailingAnchor),

            progressBar.topAnchor.constraint(
                equalTo: summaryLabel.bottomAnchor, constant: Metrics.spacing2),
            progressBar.leadingAnchor.constraint(equalTo: warningLabel.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: warningLabel.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 6),

            applyButton.topAnchor.constraint(
                equalTo: progressBar.bottomAnchor, constant: Metrics.spacing3),
            applyButton.leadingAnchor.constraint(equalTo: warningLabel.leadingAnchor),
            applyButton.trailingAnchor.constraint(equalTo: warningLabel.trailingAnchor),
            applyButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),

            cancelButton.topAnchor.constraint(
                equalTo: applyButton.bottomAnchor, constant: Metrics.spacing2),
            cancelButton.leadingAnchor.constraint(equalTo: warningLabel.leadingAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: warningLabel.trailingAnchor),
            cancelButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            cancelButton.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Metrics.spacing3),
        ])
    }

    private func setupActions() {
        applyButton.addTarget(self, action: #selector(applyTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        signAsWrittenButton.addTarget(self, action: #selector(signAsWritten), for: .touchUpInside)
        signInvertedButton.addTarget(self, action: #selector(signInverted), for: .touchUpInside)
    }

    @objc private func applyTapped() { delegate?.didTapApply() }
    @objc private func cancelTapped() { delegate?.didTapCancel() }
    @objc private func signAsWritten() { delegate?.didTapResolveSigns(asWritten: true) }
    @objc private func signInverted() { delegate?.didTapResolveSigns(asWritten: false) }

    // MARK: - State

    func setState(_ state: State) {
        switch state {
        case .reviewing(let summary, let net, let canApply, let warning, let needsSignDecision):
            summaryLabel.text = summary
            netLabel.text = (net >= 0 ? "+" : "-") + abs(net).currencyString
            netLabel.textColor = net >= 0 ? Colors.mainGreen : Colors.gray700

            warningLabel.text = warning
            warningLabel.isHidden = warning == nil
            signPromptContainer.isHidden = !needsSignDecision

            progressBar.isHidden = true
            applyButton.stopLoading()
            applyButton.isEnabled = canApply
            applyButton.alpha = canApply ? 1.0 : 0.5
            cancelButton.isEnabled = true
            tableView.isUserInteractionEnabled = true

        case .applying(let done, let total):
            progressBar.isHidden = false
            progressBar.progress = total == 0 ? 0 : Float(done) / Float(total)
            summaryLabel.text = String(format: "import.review.applying".localized, done, total)
            applyButton.startLoading()
            applyButton.isEnabled = false
            cancelButton.isEnabled = false
            // An apply is a single unit of work; letting the list change under it would desync the
            // plan from what is actually being written.
            tableView.isUserInteractionEnabled = false

        case .failed(let message):
            progressBar.isHidden = true
            applyButton.stopLoading()
            applyButton.isEnabled = true
            applyButton.alpha = 1.0
            cancelButton.isEnabled = true
            tableView.isUserInteractionEnabled = true
            warningLabel.text = message
            warningLabel.isHidden = false
        }
    }
}
