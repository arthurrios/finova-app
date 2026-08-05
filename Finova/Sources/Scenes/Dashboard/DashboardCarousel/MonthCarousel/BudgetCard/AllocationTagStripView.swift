//
//  AllocationTagStripView.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import UIKit

protocol AllocationTagStripViewDelegate: AnyObject {
    /// `nil` clears the filter.
    func didSelectTag(_ tagId: String?)
    func didTapCreateTag()
}

/// The per-tag subtotals under the budget card, doubling as the filter control for the list below.
///
/// Sits between the allocations header and the table rather than inside either. The header is a
/// horizontal stack whose 44pt height constraint is activated inline with no stored reference, so it
/// can never be made taller; and its `.equalSpacing` distribution means a third arranged subview would
/// redistribute the spacing around the two that are there.
final class AllocationTagStripView: UIView {

    weak var delegate: AllocationTagStripViewDelegate?

    /// Same 44pt as the header above it, so the two read as one band.
    static let preferredHeight = Metrics.spacing11

    private static let chipHeight: CGFloat = 28

    /// The pieces of one chip that selection restyles. Held explicitly rather than rediscovered by
    /// walking `subviews`: inverting the dot to `gray100` on selection would otherwise destroy the only
    /// record of its tag colour, and deselecting could not restore it.
    private struct Chip {
        let button: UIButton
        let dot: UIView
        let nameLabel: UILabel
        let amountLabel: UILabel
        let inkColor: UIColor
    }

    private var chipsByTagId: [String: Chip] = [:]
    private var selectedTagId: String?
    /// Held so it can be inserted and removed as the filter toggles, without rebuilding every chip.
    private var clearChip: UIButton?

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private let chipsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Metrics.spacing2
        stack.alignment = .center
        // `.fill`, never `.fillEqually`: chips are sized by their own content and must be allowed to
        // overflow into the scroll view rather than being squeezed to share the visible width.
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// Wanted, unlike a bottom edge: the header above deliberately leaves its own bottom open.
    private let topDividerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray100
        // No corner masking: the header owns the top corners and the table the bottom ones, so this
        // middle band must stay square for the three of them to read as one rounded card.
        clipsToBounds = true

        addSubview(topDividerView)
        addSubview(scrollView)
        scrollView.addSubview(chipsStackView)

        NSLayoutConstraint.activate([
            topDividerView.topAnchor.constraint(equalTo: topAnchor),
            topDividerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            topDividerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            topDividerView.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: topDividerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            chipsStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            chipsStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            chipsStackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            chipsStackView.leadingAnchor.constraint(
                equalTo: scrollView.leadingAnchor, constant: Metrics.spacing5),
            chipsStackView.trailingAnchor.constraint(
                equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing4),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    /// Rebuilds the chips for a month. Returns whether there is anything to show, which the caller uses
    /// to decide the strip's height - `isHidden` alone cannot collapse a view that owns one.
    @discardableResult
    func configure(
        breakdown: AllocationTagBreakdown,
        selectedTagId: String?,
        isValuesHidden: Bool
    ) -> Bool {
        self.selectedTagId = selectedTagId

        chipsByTagId.removeAll()
        clearChip = nil
        chipsStackView.arrangedSubviews.forEach {
            chipsStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard breakdown.hasTags else { return false }

        for arc in breakdown.tagArcs {
            let chip = makeChip(
                title: arc.tag.displayName,
                amount: arc.bucket.allocated,
                inkColor: arc.tag.color.ink,
                isValuesHidden: isValuesHidden)
            chip.button.accessibilityLabel = accessibilityLabel(
                for: arc, isValuesHidden: isValuesHidden)
            chip.button.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            chipsByTagId[arc.id] = chip
            chipsStackView.addArrangedSubview(chip.button)
        }

        // The untagged chip is grey and never a palette colour - it is a remainder, not a tag, and is
        // not tappable because "everything else" is not a filter anyone asked for.
        if let untagged = breakdown.untagged {
            let chip = makeChip(
                title: "budget.tags.strip.untagged".localized,
                amount: untagged.allocated,
                inkColor: Colors.gray400,
                isValuesHidden: isValuesHidden)
            chip.button.isUserInteractionEnabled = false
            chipsStackView.addArrangedSubview(chip.button)
        }

        // Trailing, after Untagged: creating a tag is the least frequent thing done here, so it goes
        // last, past the figures the strip exists to show.
        chipsStackView.addArrangedSubview(makeAddChip())

        updateClearChip()
        refreshSelection()
        return true
    }

    private func makeChip(
        title: String,
        amount: Int,
        inkColor: UIColor,
        isValuesHidden: Bool
    ) -> Chip {
        let chip = UIButton(type: .system)
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.backgroundColor = Colors.gray200
        chip.layer.borderWidth = 1
        chip.layer.borderColor = Colors.gray300.cgColor
        // Pill radius set here, not in `layoutSubviews`: the height is a constant, so deferring it only
        // creates an ordering dependency on when the chip's bounds are first resolved.
        chip.layer.cornerRadius = Self.chipHeight / 2
        chip.heightAnchor.constraint(equalToConstant: Self.chipHeight).isActive = true

        let dot = UIView()
        dot.backgroundColor = inkColor
        dot.layer.cornerRadius = 3.5
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 7).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 7).isActive = true

        let nameLabel = UILabel()
        nameLabel.text = title
        nameLabel.font = Fonts.textXS.font
        nameLabel.textColor = Colors.gray600

        let amountLabel = UILabel()
        amountLabel.text = isValuesHidden ? "••••" : amount.compactCurrencyString
        amountLabel.font = Fonts.titleXS.font
        amountLabel.textColor = Colors.gray700

        let stack = UIStackView(arrangedSubviews: [dot, nameLabel, amountLabel])
        stack.axis = .horizontal
        stack.spacing = Metrics.spacing1
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: Metrics.spacing3),
            stack.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -Metrics.spacing3),
            stack.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
        ])

        return Chip(
            button: chip, dot: dot, nameLabel: nameLabel, amountLabel: amountLabel,
            inkColor: inkColor)
    }

    /// Magenta rather than a palette colour: this is an app action, not a tag, and `mainMagenta` is
    /// what the app already uses for "add" affordances.
    private func makeAddChip() -> UIButton {
        let chip = UIButton(type: .system)
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.backgroundColor = Colors.lowMagenta
        chip.layer.borderWidth = 1
        chip.layer.borderColor = Colors.mainMagenta.cgColor
        chip.layer.cornerRadius = Self.chipHeight / 2
        chip.setImage(
            UIImage(
                systemName: "plus",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)),
            for: .normal)
        chip.tintColor = Colors.mainMagenta
        chip.accessibilityLabel = "allocationTags.create.title".localized
        chip.heightAnchor.constraint(equalToConstant: Self.chipHeight).isActive = true
        chip.widthAnchor.constraint(equalToConstant: Self.chipHeight).isActive = true
        chip.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        return chip
    }

    private func makeClearChip() -> UIButton {
        let chip = UIButton(type: .system)
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.backgroundColor = Colors.gray200
        chip.layer.borderWidth = 1
        chip.layer.borderColor = Colors.gray300.cgColor
        // Sized explicitly: the default symbol weight is body-sized and fills a 28pt chip edge to edge.
        chip.setImage(
            UIImage(
                systemName: "xmark",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)),
            for: .normal)
        chip.tintColor = Colors.gray500
        chip.accessibilityLabel = "budget.tags.strip.clear".localized
        // Pill radius set here, not in `layoutSubviews`: the height is a constant, so deferring it only
        // creates an ordering dependency on when the chip's bounds are first resolved.
        chip.layer.cornerRadius = Self.chipHeight / 2
        chip.heightAnchor.constraint(equalToConstant: Self.chipHeight).isActive = true
        chip.widthAnchor.constraint(equalToConstant: 28).isActive = true
        chip.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        return chip
    }

    private func accessibilityLabel(
        for arc: AllocationTagBreakdown.TagArc,
        isValuesHidden: Bool
    ) -> String {
        guard !isValuesHidden else { return arc.tag.displayName }
        let share = Int((arc.bucket.share * 100).rounded())
        return [
            arc.tag.displayName,
            arc.bucket.allocated.compactCurrencyString,
            String(format: "budget.tag.shareOfBudget".localized, share),
        ].joined(separator: ", ")
    }

    /// Selected chips fill with the tag's own `ink` tone, which is the tone validated to carry
    /// `gray100` text - the bright `arc` tone belongs on the dark card, not here.
    func setSelectedTag(_ tagId: String?) {
        selectedTagId = tagId
        updateClearChip()
        refreshSelection()
    }

    /// Keeps the clear button in step with the filter on a chip tap, not only on a full rebuild.
    ///
    /// Leading, not trailing: the strip scrolls, and with three tags plus an Untagged chip a trailing
    /// clear button sits off the right edge - the one control the user needs would be the one they
    /// cannot see. Its arrival at the front also reads as "a filter is on".
    private func updateClearChip() {
        if selectedTagId == nil {
            clearChip?.removeFromSuperview()
            clearChip = nil
            return
        }
        guard clearChip == nil, !chipsByTagId.isEmpty else { return }
        let chip = makeClearChip()
        clearChip = chip
        chipsStackView.insertArrangedSubview(chip, at: 0)
    }

    private func refreshSelection() {
        for (tagId, chip) in chipsByTagId {
            if tagId == selectedTagId {
                chip.button.backgroundColor = chip.inkColor
                chip.button.layer.borderWidth = 0
                chip.dot.backgroundColor = Colors.gray100
                chip.nameLabel.textColor = Colors.gray100
                chip.amountLabel.textColor = Colors.gray100
            } else {
                chip.button.backgroundColor = Colors.gray200
                chip.button.layer.borderWidth = 1
                chip.button.layer.borderColor = Colors.gray300.cgColor
                chip.dot.backgroundColor = chip.inkColor
                chip.nameLabel.textColor = Colors.gray600
                chip.amountLabel.textColor = Colors.gray700
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Left and right hairlines, drawn here rather than by the parent so this view owns its own
        // chrome and a snapshot of it in isolation shows the real thing. Not a full `layer.border`: the
        // top edge is the divider above and the bottom edge belongs to the table, which draws its own.
        layer.sublayers?.removeAll { $0.name == Self.borderLayerName }
        guard bounds.width > 0, bounds.height > 0 else { return }

        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0.5, y: 0))
        path.addLine(to: CGPoint(x: 0.5, y: bounds.height))
        path.move(to: CGPoint(x: bounds.width - 0.5, y: 0))
        path.addLine(to: CGPoint(x: bounds.width - 0.5, y: bounds.height))

        let border = CAShapeLayer()
        border.name = Self.borderLayerName
        border.path = path.cgPath
        border.fillColor = UIColor.clear.cgColor
        border.strokeColor = Colors.gray300.cgColor
        border.lineWidth = 1
        border.frame = bounds
        layer.addSublayer(border)
    }

    private static let borderLayerName = "allocationTagStrip.sideBorder"

    @objc private func chipTapped(_ sender: UIButton) {
        guard let tagId = chipsByTagId.first(where: { $0.value.button === sender })?.key else { return }
        // Tapping the selected chip clears, matching the donut's tap-again behaviour.
        delegate?.didSelectTag(tagId == selectedTagId ? nil : tagId)
    }

    @objc private func clearTapped() {
        delegate?.didSelectTag(nil)
    }

    @objc private func addTapped() {
        delegate?.didTapCreateTag()
    }
}
