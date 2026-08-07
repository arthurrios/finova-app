//
//  ProjectionExplainerView.swift
//  Finova
//
//  Created by Arthur Rios on 07/08/26.
//

import UIKit

/// The projection, itemised. A sheet rather than anything on the card, because the card's trailing
/// block is 72pt wide and cannot carry a sentence, let alone a table.
final class ProjectionExplainerView: UIView {

    static let formulaStackIdentifier = "projectionExplainer.formulaStack"
    static let historyStackIdentifier = "projectionExplainer.historyStack"

    // MARK: - Views

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.showsVerticalScrollIndicator = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing5
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleMD
        label.textColor = Colors.gray700
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let formulaHeaderLabel = makeSectionHeader()

    private let formulaStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing2
        stack.accessibilityIdentifier = ProjectionExplainerView.formulaStackIdentifier
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let formulaNoteLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.textXS
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let historyHeaderLabel = makeSectionHeader()

    private let historyStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing3
        stack.accessibilityIdentifier = ProjectionExplainerView.historyStackIdentifier
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let historyEmptyLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.textSM
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray100
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(scrollView)
        scrollView.addSubview(contentStackView)

        contentStackView.addArrangedSubview(titleLabel)
        contentStackView.addArrangedSubview(formulaHeaderLabel)
        contentStackView.addArrangedSubview(formulaStackView)
        contentStackView.addArrangedSubview(formulaNoteLabel)
        contentStackView.addArrangedSubview(historyHeaderLabel)
        contentStackView.addArrangedSubview(historyStackView)
        contentStackView.addArrangedSubview(historyEmptyLabel)

        // Tighter than the stack's own spacing: a header belongs to the block under it, so it sits
        // closer to that block than to the one above.
        contentStackView.setCustomSpacing(Metrics.spacing2, after: formulaHeaderLabel)
        contentStackView.setCustomSpacing(Metrics.spacing2, after: formulaStackView)
        contentStackView.setCustomSpacing(Metrics.spacing2, after: historyHeaderLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStackView.topAnchor.constraint(
                equalTo: scrollView.topAnchor, constant: Metrics.spacing6),
            contentStackView.leadingAnchor.constraint(
                equalTo: scrollView.leadingAnchor, constant: Metrics.spacing5),
            contentStackView.trailingAnchor.constraint(
                equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing5),
            contentStackView.bottomAnchor.constraint(
                equalTo: scrollView.bottomAnchor, constant: -Metrics.spacing8),
            // Pins the content width, which is what lets the multi-line labels wrap instead of
            // stretching the scroll view sideways.
            contentStackView.widthAnchor.constraint(
                equalTo: scrollView.widthAnchor, constant: -Metrics.spacing5 * 2)
        ])
    }

    // MARK: - Configuration

    func configure(
        title: String,
        formulaHeader: String,
        formulaLines: [ProjectionExplainerLine],
        formulaNote: String,
        historyHeader: String,
        historyRows: [ProjectionExplainerHistoryRow],
        historyEmptyText: String?,
        isValuesHidden: Bool
    ) {
        titleLabel.text = title
        titleLabel.applyStyle()
        formulaHeaderLabel.text = formulaHeader
        formulaHeaderLabel.applyStyle()
        formulaNoteLabel.text = formulaNote
        formulaNoteLabel.applyStyle()
        historyHeaderLabel.text = historyHeader
        historyHeaderLabel.applyStyle()

        formulaStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for line in formulaLines {
            formulaStackView.addArrangedSubview(Self.makeFormulaRow(line, isValuesHidden: isValuesHidden))
        }

        historyStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for row in historyRows {
            historyStackView.addArrangedSubview(Self.makeHistoryRow(row))
        }

        // The table and its stand-in are mutually exclusive; the header stays either way, so the
        // section never reads as missing.
        historyStackView.isHidden = historyEmptyText != nil
        historyEmptyLabel.isHidden = historyEmptyText == nil
        historyEmptyLabel.text = historyEmptyText
        historyEmptyLabel.applyStyle()
    }

    // MARK: - Row builders

    private static func makeSectionHeader() -> UILabel {
        let label = UILabel()
        label.fontStyle = Fonts.titleXS
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// A label-left, amount-right row, matching the summary rows on the allocation details screen.
    ///
    /// The result line is separated by a hairline rule and set bold: it is the figure the card shows,
    /// and everything above it is working.
    private static func makeFormulaRow(
        _ line: ProjectionExplainerLine, isValuesHidden: Bool
    ) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = Metrics.spacing2
        container.translatesAutoresizingMaskIntoConstraints = false

        if line.kind == .result {
            let rule = UIView()
            rule.backgroundColor = Colors.gray300
            rule.translatesAutoresizingMaskIntoConstraints = false
            rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
            container.addArrangedSubview(rule)
        }

        let label = UILabel()
        label.fontStyle = line.kind == .result ? Fonts.textSMBold : Fonts.textSM
        label.textColor = line.kind == .result ? Colors.gray700 : Colors.gray500
        label.numberOfLines = 0
        label.text = line.label
        label.applyStyle()

        let value = UILabel()
        value.fontStyle = line.kind == .result ? Fonts.textSMBold : Fonts.textSM
        value.textAlignment = .right
        value.setContentCompressionResistancePriority(.required, for: .horizontal)

        // A subtraction reads with its minus; the base and the result carry their own sign, so a
        // negative balance still reads as negative rather than as something taken away.
        switch line.kind {
        case .subtraction:
            value.text = "-" + line.amount.maskedCurrencyString(hidden: isValuesHidden)
            value.textColor = Colors.gray500
        case .base:
            value.text = line.amount.maskedSignedCurrencyString(hidden: isValuesHidden)
            value.textColor = Colors.gray700
        case .result:
            value.text = line.amount.maskedSignedCurrencyString(hidden: isValuesHidden)
            // Colour suppressed while masked, matching the card: a red row of bullets would still
            // announce an overdraft.
            value.textColor =
                (!isValuesHidden && line.amount < 0) ? Colors.mainRed : Colors.gray700
        }
        // After the text, not before: `applyStyle` bails when `text` is nil, and the setter on
        // `fontStyle` fires it at assignment time - so styling set at construction never lands on a
        // label whose text arrives later.
        value.applyStyle()

        let row = UIStackView(arrangedSubviews: [label, value])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = Metrics.spacing3
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isAccessibilityElement = true
        row.accessibilityLabel = "\(line.label), \(value.text ?? "")"

        container.addArrangedSubview(row)
        return container
    }

    /// Category on the left, range and its basis stacked on the right.
    ///
    /// Never masked. These are percentages and month counts, not amounts - the same reason the
    /// allocation details ring keeps its percentage and the donut keeps its proportions while values
    /// are hidden.
    private static func makeHistoryRow(_ row: ProjectionExplainerHistoryRow) -> UIView {
        let name = UILabel()
        name.fontStyle = Fonts.textSM
        name.textColor = Colors.gray700
        name.numberOfLines = 0
        name.text = row.categoryName
        name.applyStyle()

        let trailing = UIStackView()
        trailing.axis = .vertical
        trailing.alignment = .trailing
        trailing.spacing = 0
        trailing.translatesAutoresizingMaskIntoConstraints = false

        if let range = row.range {
            let rangeLabel = UILabel()
            rangeLabel.fontStyle = Fonts.textSMBold
            rangeLabel.textColor = Colors.gray700
            rangeLabel.textAlignment = .right
            rangeLabel.text = range
            rangeLabel.applyStyle()
            trailing.addArrangedSubview(rangeLabel)
        }

        let detail = UILabel()
        detail.fontStyle = Fonts.textXS
        detail.textColor = Colors.gray500
        detail.textAlignment = .right
        detail.numberOfLines = 0
        detail.text = row.detail
        detail.applyStyle()
        trailing.addArrangedSubview(detail)

        let stack = UIStackView(arrangedSubviews: [name, trailing])
        stack.axis = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = Metrics.spacing3
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isAccessibilityElement = true
        stack.accessibilityLabel = [row.categoryName, row.range, row.detail]
            .compactMap { $0 }
            .joined(separator: ", ")
        return stack
    }
}
