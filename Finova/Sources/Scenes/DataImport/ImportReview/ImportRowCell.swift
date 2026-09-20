//
//  ImportRowCell.swift
//  Finova
//
//  One proposed transaction in the review list.
//
//  Portrait-only, `UIRequiresFullScreen`, and 375 pt at the narrowest — so this is a vertical row,
//  never a side-by-side before/after table.
//

import UIKit

final class ImportRowCell: UITableViewCell {

    static let identifier = "ImportRowCell"

    var onToggleInclusion: (() -> Void)?
    var onTapCategory: (() -> Void)?

    private let includeButton: UIButton = {
        let button = UIButton(type: .system)
        button.tintColor = Colors.mainMagenta
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }()

    private let categoryIconView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.textColor = Colors.gray700
        label.applyStyle()
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let amountLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textAlignment = .right
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let badgeLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupLayout()
        includeButton.addTarget(self, action: #selector(toggleTapped), for: .touchUpInside)

        let categoryTap = UITapGestureRecognizer(target: self, action: #selector(categoryTapped))
        categoryIconView.isUserInteractionEnabled = true
        categoryIconView.addGestureRecognizer(categoryTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupLayout() {
        let textStack = UIStackView(
            axis: .vertical, spacing: 2, arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false

        [includeButton, categoryIconView, textStack, amountLabel, badgeLabel]
            .forEach(contentView.addSubview)

        NSLayoutConstraint.activate([
            includeButton.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: Metrics.spacing4),
            includeButton.topAnchor.constraint(
                equalTo: contentView.topAnchor, constant: Metrics.spacing3),
            includeButton.widthAnchor.constraint(equalToConstant: 24),
            includeButton.heightAnchor.constraint(equalToConstant: 24),

            categoryIconView.leadingAnchor.constraint(
                equalTo: includeButton.trailingAnchor, constant: Metrics.spacing3),
            categoryIconView.centerYAnchor.constraint(equalTo: includeButton.centerYAnchor),
            categoryIconView.widthAnchor.constraint(equalToConstant: 20),
            categoryIconView.heightAnchor.constraint(equalToConstant: 20),

            textStack.leadingAnchor.constraint(
                equalTo: categoryIconView.trailingAnchor, constant: Metrics.spacing3),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.spacing3),

            amountLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: textStack.trailingAnchor, constant: Metrics.spacing2),
            amountLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),
            amountLabel.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),

            badgeLabel.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
            badgeLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -Metrics.spacing4),
            badgeLabel.topAnchor.constraint(equalTo: textStack.bottomAnchor, constant: 2),
            badgeLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -Metrics.spacing3),
        ])
    }

    @objc private func toggleTapped() { onToggleInclusion?() }
    @objc private func categoryTapped() { onTapCategory?() }

    // MARK: - Configuration

    func configure(
        row: ImportRow, title: String, category: TransactionCategory, isIncluded: Bool
    ) {
        titleLabel.text = title
        categoryIconView.image = UIImage(systemName: category.iconName)
        categoryIconView.tintColor = isIncluded ? category.color : Colors.gray400

        includeButton.setImage(
            UIImage(systemName: isIncluded ? "checkmark.circle.fill" : "circle"), for: .normal)
        includeButton.tintColor = isIncluded ? Colors.mainMagenta : Colors.gray400
        includeButton.isHidden = row.disposition.isFailure
        includeButton.accessibilityLabel = isIncluded
            ? "import.review.a11y.included".localized
            : "import.review.a11y.excluded".localized

        if let parsed = row.parsed {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy"
            subtitleLabel.text = "\(formatter.string(from: parsed.date)) · \(category.displayName)"

            let isIncome = parsed.signedCents > 0
            amountLabel.text = (isIncome ? "+" : "-") + abs(parsed.signedCents).currencyString
            amountLabel.textColor = isIncluded
                ? (isIncome ? Colors.mainGreen : Colors.gray700)
                : Colors.gray400
        } else {
            subtitleLabel.text = row.rawCells.joined(separator: " · ")
            amountLabel.text = nil
        }

        // Dimmed rather than hidden: a row the user chose to skip must stay visible and reversible.
        contentView.alpha = isIncluded || row.disposition.isFailure ? 1.0 : 0.55

        badgeLabel.text = Self.badgeText(for: row)
        badgeLabel.isHidden = badgeLabel.text == nil
        badgeLabel.textColor = row.disposition.isFailure ? Colors.mainRed : Colors.gray500
    }

    private static func badgeText(for row: ImportRow) -> String? {
        var parts: [String] = []

        switch row.disposition {
        case .duplicateExact:
            parts.append("import.review.badge.duplicateExact".localized)
        case .duplicateLikely(_, let similarity):
            parts.append(String(format: "import.review.badge.duplicateLikely".localized,
                                Int(similarity * 100)))
        case .duplicateInFile:
            parts.append("import.review.badge.duplicateInFile".localized)
        case .alreadyImported:
            parts.append("import.review.badge.alreadyImported".localized)
        case .needsDecision(.ambiguousSign):
            parts.append("import.review.badge.ambiguousSign".localized)
        case .needsDecision(.ambiguousDate):
            parts.append("import.review.badge.ambiguousDate".localized)
        case .needsDecision(.debitAndCreditBothSet):
            parts.append("import.review.badge.bothColumns".localized)
        case .failed(let reason):
            parts.append(describe(reason))
        case .insert:
            break
        }

        for warning in row.warnings {
            switch warning {
            case .amountRounded: parts.append("import.review.badge.rounded".localized)
            case .ambiguousNumberFormat: parts.append("import.review.badge.ambiguousNumber".localized)
            case .installmentHintIgnored: parts.append("import.review.badge.installmentIgnored".localized)
            case .titleWasEmpty: parts.append("import.review.badge.noDescription".localized)
            case .dateFarFromOthers: parts.append("import.review.badge.oddDate".localized)
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func describe(_ error: RowError) -> String {
        switch error {
        case .unparseableDate(let value):
            return String(format: "import.review.error.badDate".localized, value)
        case .unparseableAmount(let value):
            return String(format: "import.review.error.badAmount".localized, value)
        case .zeroAmount: return "import.review.error.zeroAmount".localized
        case .missingField: return "import.review.error.missingField".localized
        case .amountOutOfRange: return "import.review.error.amountOutOfRange".localized
        case .shortRow: return "import.review.error.shortRow".localized
        }
    }
}
