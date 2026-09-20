//
//  ImportHistoryView.swift
//  Finova
//

import UIKit

protocol ImportHistoryViewDelegate: AnyObject {
    func didTapImportFile()
}

final class ImportHistoryCell: UITableViewCell {

    static let identifier = "ImportHistoryCell"

    private let filenameLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.textColor = Colors.gray700
        label.applyStyle()
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let summaryLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray400
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        let stack = UIStackView(
            axis: .vertical, spacing: 2,
            arrangedSubviews: [filenameLabel, summaryLabel, dateLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing3),
            stack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
            stack.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),
            stack.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -Metrics.spacing3),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(batch: ImportBatch, summary: String, range: String?) {
        filenameLabel.text = batch.sourceFilename
        summaryLabel.text = summary

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        dateLabel.text = [formatter.string(from: batch.createdAt), range]
            .compactMap { $0 }.joined(separator: " · ")

        let isSpent = batch.status == .rolledBack || batch.status == .cancelled
        contentView.alpha = isSpent ? 0.55 : 1.0
    }
}

final class ImportHistoryView: UIView {

    weak var delegate: ImportHistoryViewDelegate?

    let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.separatorStyle = .singleLine
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "import.history.empty".localized
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = Colors.mainMagenta
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let importButton = Button(variant: .base, label: "import.history.pickFile".localized)

    private let footnoteLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.textAlignment = .center
        // Stated plainly, because it is a real limitation the user would otherwise discover the hard
        // way: the batch record is local, so history does not travel between devices.
        label.text = "import.history.footnote".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray200
        importButton.translatesAutoresizingMaskIntoConstraints = false
        [tableView, emptyLabel, activityIndicator, importButton, footnoteLabel].forEach(addSubview)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(
                equalTo: importButton.topAnchor, constant: -Metrics.spacing3),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing6),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing6),

            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),

            importButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            importButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            importButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
            importButton.bottomAnchor.constraint(
                equalTo: footnoteLabel.topAnchor, constant: -Metrics.spacing2),

            footnoteLabel.leadingAnchor.constraint(equalTo: importButton.leadingAnchor),
            footnoteLabel.trailingAnchor.constraint(equalTo: importButton.trailingAnchor),
            footnoteLabel.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Metrics.spacing3),
        ])

        importButton.addTarget(self, action: #selector(importTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func importTapped() { delegate?.didTapImportFile() }

    func updateEmptyState(isEmpty: Bool) {
        emptyLabel.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }

    func setParsing(_ parsing: Bool) {
        if parsing { activityIndicator.startAnimating() } else { activityIndicator.stopAnimating() }
        importButton.isEnabled = !parsing
        importButton.alpha = parsing ? 0.5 : 1.0
    }
}
