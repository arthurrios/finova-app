//
//  CloudCleanupView.swift
//  Finova
//
//  Created by Arthur Rios on 16/03/26.
//

import UIKit

protocol CloudCleanupViewDelegate: AnyObject {
    func didTapClose()
    func didTapDeleteOrphans()
}

final class CloudCleanupView: UIView {
    weak var delegate: CloudCleanupViewDelegate?

    enum State {
        case scanning(type: String, index: Int, total: Int)
        case results(CloudCleanupScanResult)
        case deleting(current: Int, total: Int)
        case complete(deleted: Int, errors: Int)
        case error(String)
    }

    // MARK: - Header

    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleXS
        label.text = "cloudCleanup.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let closeIconButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "xmark"), for: .normal)
        btn.tintColor = Colors.gray500
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    // MARK: - Status Container

    private let statusContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // Scanning state
    private let scanningIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = Colors.mainMagenta
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let scanningLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var scanningStack: UIStackView = {
        let stack = UIStackView(
            axis: .vertical, spacing: Metrics.spacing3, alignment: .center,
            arrangedSubviews: [scanningIndicator, scanningLabel])
        return stack
    }()

    // Results state — breakdown table
    private lazy var breakdownStack: UIStackView = {
        let stack = UIStackView(axis: .vertical, spacing: 0)
        return stack
    }()

    // Deleting state
    private let deletingProgressBar: RoundedProgressBar = {
        let bar = RoundedProgressBar()
        bar.trackTintColor = Colors.gray200
        bar.progressTintColor = Colors.mainRed
        bar.cornerRadius = 3
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private let deletingLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var deletingStack: UIStackView = {
        let stack = UIStackView(
            axis: .vertical, spacing: Metrics.spacing3,
            arrangedSubviews: [deletingProgressBar, deletingLabel])
        deletingProgressBar.heightAnchor.constraint(equalToConstant: 6).isActive = true
        return stack
    }()

    // Complete/Error state
    private let resultLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Action Button

    private let actionButton = Button(variant: .base, label: "")

    // MARK: - Content Stack

    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing7
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing10,
            leading: Metrics.spacing8,
            bottom: Metrics.spacing4,
            trailing: Metrics.spacing8)
        return stack
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray100
        setupView()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupView() {
        addSubview(contentStackView)

        // Header
        let headerStack = UIStackView(arrangedSubviews: [headerTitleLabel, UIView(), closeIconButton])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        closeIconButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        closeIconButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        contentStackView.addArrangedSubview(headerStack)

        // Status container
        contentStackView.addArrangedSubview(statusContainer)

        // Action button
        contentStackView.addArrangedSubview(actionButton)
        actionButton.isHidden = true

        closeIconButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    // MARK: - State Updates

    func updateState(_ state: State) {
        clearStatusContainer()

        switch state {
        case .scanning(let type, let index, let total):
            showScanning(type: type, index: index, total: total)
        case .results(let result):
            showResults(result)
        case .deleting(let current, let total):
            showDeleting(current: current, total: total)
        case .complete(let deleted, let errors):
            showComplete(deleted: deleted, errors: errors)
        case .error(let message):
            showError(message)
        }
    }

    // MARK: - Private — State Views

    private func clearStatusContainer() {
        statusContainer.subviews.forEach { $0.removeFromSuperview() }
    }

    private func showScanning(type: String, index: Int, total: Int) {
        actionButton.isHidden = true
        scanningIndicator.startAnimating()

        if type.isEmpty {
            scanningLabel.text = "cloudCleanup.scanning.zone".localized
        } else {
            scanningLabel.text = String(
                format: "cloudCleanup.scanning".localized, type, index, total
            )
        }

        statusContainer.addSubview(scanningStack)
        NSLayoutConstraint.activate([
            scanningStack.topAnchor.constraint(equalTo: statusContainer.topAnchor),
            scanningStack.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor),
            scanningStack.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor),
            scanningStack.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor),
        ])
    }

    private func showResults(_ result: CloudCleanupScanResult) {
        buildBreakdownTable(result)

        statusContainer.addSubview(breakdownStack)
        NSLayoutConstraint.activate([
            breakdownStack.topAnchor.constraint(equalTo: statusContainer.topAnchor),
            breakdownStack.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor),
            breakdownStack.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor),
            breakdownStack.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor),
        ])

        if result.totalOrphans > 0 {
            actionButton.setTitle(
                String(format: "cloudCleanup.deleteAction".localized, result.totalOrphans),
                for: .normal
            )
            actionButton.setTitleColor(Colors.gray100, for: .normal)
            actionButton.backgroundColor = Colors.mainRed
            actionButton.isHidden = false
        } else {
            actionButton.setTitle("alert.ok".localized, for: .normal)
            actionButton.variant = .base
            actionButton.isHidden = false
        }
    }

    private func showDeleting(current: Int, total: Int) {
        actionButton.isHidden = true

        let fraction: Float = total > 0 ? Float(current) / Float(total) : 0
        deletingProgressBar.setProgress(fraction, animated: true)
        deletingLabel.text = String(
            format: "cloudCleanup.deleting".localized, current, total
        )

        statusContainer.addSubview(deletingStack)
        NSLayoutConstraint.activate([
            deletingStack.topAnchor.constraint(equalTo: statusContainer.topAnchor),
            deletingStack.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor),
            deletingStack.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor),
            deletingStack.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor),
        ])
    }

    private func showComplete(deleted: Int, errors: Int) {
        resultLabel.text = String(
            format: "cloudCleanup.complete".localized, deleted, errors
        )
        resultLabel.textColor = Colors.gray500

        statusContainer.addSubview(resultLabel)
        NSLayoutConstraint.activate([
            resultLabel.topAnchor.constraint(equalTo: statusContainer.topAnchor),
            resultLabel.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor),
            resultLabel.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor),
            resultLabel.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor),
        ])

        actionButton.setTitle("alert.ok".localized, for: .normal)
        actionButton.variant = .base
        actionButton.isHidden = false
    }

    private func showError(_ message: String) {
        resultLabel.text = message
        resultLabel.textColor = Colors.mainRed

        statusContainer.addSubview(resultLabel)
        NSLayoutConstraint.activate([
            resultLabel.topAnchor.constraint(equalTo: statusContainer.topAnchor),
            resultLabel.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor),
            resultLabel.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor),
            resultLabel.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor),
        ])

        actionButton.setTitle("alert.ok".localized, for: .normal)
        actionButton.variant = .base
        actionButton.isHidden = false
    }

    // MARK: - Private — Breakdown Table

    private func buildBreakdownTable(_ result: CloudCleanupScanResult) {
        breakdownStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Header row
        let headerRow = makeTableRow(
            name: "cloudCleanup.column.type".localized,
            cloud: "cloudCleanup.column.cloud".localized,
            local: "cloudCleanup.column.local".localized,
            orphans: "cloudCleanup.column.orphans".localized,
            isHeader: true
        )
        breakdownStack.addArrangedSubview(headerRow)
        breakdownStack.addArrangedSubview(makeSeparator())

        // Data rows
        for entry in result.breakdown {
            let row = makeTableRow(
                name: entry.recordType,
                cloud: "\(entry.cloud)",
                local: "\(entry.local)",
                orphans: "\(entry.orphans)",
                isHeader: false,
                orphanCount: entry.orphans
            )
            breakdownStack.addArrangedSubview(row)
        }

        breakdownStack.addArrangedSubview(makeSeparator())

        // Total row
        let totalRow = makeTableRow(
            name: "cloudCleanup.row.total".localized,
            cloud: "\(result.totalCloud)",
            local: "\(result.totalLocal)",
            orphans: "\(result.totalOrphans)",
            isHeader: false,
            isTotal: true,
            orphanCount: result.totalOrphans
        )
        breakdownStack.addArrangedSubview(totalRow)

        if result.totalOrphans == 0 {
            let noOrphansLabel = UILabel()
            noOrphansLabel.font = Fonts.textSM.font
            noOrphansLabel.textColor = Colors.gray500
            noOrphansLabel.textAlignment = .center
            noOrphansLabel.numberOfLines = 0
            noOrphansLabel.text = "cloudCleanup.noOrphans".localized
            noOrphansLabel.translatesAutoresizingMaskIntoConstraints = false

            let spacer = UIView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.heightAnchor.constraint(equalToConstant: Metrics.spacing4).isActive = true
            breakdownStack.addArrangedSubview(spacer)
            breakdownStack.addArrangedSubview(noOrphansLabel)
        }
    }

    private func makeTableRow(
        name: String, cloud: String, local: String, orphans: String,
        isHeader: Bool, isTotal: Bool = false, orphanCount: Int = 0
    ) -> UIStackView {
        let font: UIFont = (isHeader || isTotal) ? Fonts.textSMBold.font : Fonts.textSM.font

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = isHeader ? Fonts.textXS.font : font
        nameLabel.textColor = isHeader ? Colors.gray500 : Colors.gray700
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let cloudLabel = UILabel()
        cloudLabel.text = cloud
        cloudLabel.font = isHeader ? Fonts.textXS.font : font
        cloudLabel.textColor = isHeader ? Colors.gray500 : Colors.gray500
        cloudLabel.textAlignment = .right
        cloudLabel.translatesAutoresizingMaskIntoConstraints = false

        let localLabel = UILabel()
        localLabel.text = local
        localLabel.font = isHeader ? Fonts.textXS.font : font
        localLabel.textColor = isHeader ? Colors.gray500 : Colors.gray500
        localLabel.textAlignment = .right
        localLabel.translatesAutoresizingMaskIntoConstraints = false

        let orphansLabel = UILabel()
        orphansLabel.text = orphans
        orphansLabel.font = isHeader ? Fonts.textXS.font : font
        orphansLabel.textColor = isHeader ? Colors.gray500 : (orphanCount > 0 ? Colors.mainRed : Colors.gray500)
        orphansLabel.textAlignment = .right
        orphansLabel.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(
            axis: .horizontal, spacing: Metrics.spacing2, distribution: .fill,
            arrangedSubviews: [nameLabel, cloudLabel, localLabel, orphansLabel])
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing2, leading: 0, bottom: Metrics.spacing2, trailing: 0)

        // Name takes available space, numbers have fixed widths
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        cloudLabel.widthAnchor.constraint(equalToConstant: 50).isActive = true
        localLabel.widthAnchor.constraint(equalToConstant: 50).isActive = true
        orphansLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true

        return row
    }

    private func makeSeparator() -> UIView {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    // MARK: - Actions

    private var currentState: State?

    @objc private func closeTapped() {
        delegate?.didTapClose()
    }

    @objc private func actionTapped() {
        if case .results(let result) = currentState, result.totalOrphans > 0 {
            delegate?.didTapDeleteOrphans()
        } else {
            delegate?.didTapClose()
        }
    }
}

// MARK: - State tracking for action button routing

extension CloudCleanupView {
    func setState(_ state: State) {
        currentState = state
        updateState(state)
    }
}
