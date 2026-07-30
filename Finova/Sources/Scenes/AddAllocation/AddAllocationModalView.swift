//
//  AddAllocationModalView.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import UIKit

protocol AddAllocationModalViewDelegate: AnyObject {
    func didTapClose()
    /// - Parameter recurrenceEndMonth: last month anchor the recurring series should cover;
    ///   `nil` means ongoing ("Always"). Ignored when `isRecurring` is false.
    func didTapSave(
        category: TransactionCategory, amount: Int, isRecurring: Bool, recurrenceEndMonth: Int?)
    func handleError(title: String, message: String)
}

final class AddAllocationModalView: UIView {

    weak var delegate: AddAllocationModalViewDelegate?

    private var availableCategories: [TransactionCategory] = []
    private var isEditMode = false
    private var editingAllocation: BudgetAllocation?

    // MARK: - UI Components

    private lazy var contentStackView: UIStackView = {
        let sv = UIStackView(
            axis: .vertical, spacing: Metrics.spacing7, distribution: .fill,
            arrangedSubviews: [
                headerStackView, inputStackView, recurringSectionStackView, separator, saveButton
            ])
        sv.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing10, leading: Metrics.spacing8, bottom: Metrics.spacing4,
            trailing: Metrics.spacing8)
        sv.isLayoutMarginsRelativeArrangement = true
        sv.setContentHuggingPriority(UILayoutPriority(251), for: .vertical)
        sv.setContentCompressionResistancePriority(UILayoutPriority(751), for: .vertical)
        return sv
    }()

    private lazy var headerStackView = UIStackView(
        axis: .horizontal, alignment: .center, arrangedSubviews: [headerTitleLabel, closeIconButton])

    private lazy var inputStackView = UIStackView(
        axis: .vertical, spacing: Metrics.spacing3,
        arrangedSubviews: [categoryPickerView, amountTextField])

    // Section container for recurring option with label
    private let recurringSectionStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = Metrics.spacing3
        stack.setContentHuggingPriority(.required, for: .vertical)
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        return stack
    }()

    private let recurringSectionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray400
        label.text = "allocation.add.recurring.section".localized
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    private let recurringOptionStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        return stack
    }()

    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleXS
        label.textColor = Colors.gray700
        label.text = "allocation.add.title".localized
        label.applyStyle()
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let closeIconButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(named: "x"), for: .normal)
        button.tintColor = Colors.gray500
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 20),
            button.heightAnchor.constraint(equalToConstant: 20)
        ])
        button.accessibilityLabel = "allocation.add.close".localized
        return button
    }()

    private(set) lazy var categoryPickerView: Input = {
        let input = Input(
            type: .picker(values: []),
            placeholder: "allocation.add.category.placeholder".localized,
            icon: UIImage(named: "tag"),
            iconPosition: .left
        )
        return input
    }()

    private lazy var categoryDisplayView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray200
        view.layer.cornerRadius = CornerRadius.medium
        view.layer.borderWidth = 1
        view.layer.borderColor = Colors.gray300.cgColor
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var categoryDisplayStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Metrics.spacing3
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var categoryDisplayIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.gray500
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var categoryDisplayLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray700
        return label
    }()

    private let amountTextField = Input(type: .currency, placeholder: "0,00")

    private let recurringLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray700
        label.text = "allocation.add.recurring".localized
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    private let recurringSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.onTintColor = Colors.mainMagenta
        toggle.isOn = false
        return toggle
    }()

    // MARK: - Recurrence Duration
    //
    // Progressive disclosure: hidden until Recurring is switched on, so the common "ongoing
    // budget" path stays a single tap. Presets give speed; the resolved end month is always
    // spelled out underneath so the user never has to do the date math themselves.

    /// `nil` = ongoing ("Always"), otherwise the last month anchor the series should cover.
    private var recurrenceEndMonth: Int?

    /// The month this allocation starts in — presets are computed relative to it.
    private var baseMonthAnchor: Int = Date().monthAnchor

    /// Sets the starting month so "6 months" resolves to the right end month.
    func setBaseMonth(_ anchor: Int) {
        baseMonthAnchor = anchor
        rebuildDurationMenu()
        updateDurationDisplay()
    }

    private static let durationPresets = [3, 6, 12, 24]

    private lazy var durationRowStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [durationLabel, durationButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.isHidden = true
        return stack
    }()

    private let durationLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray700
        label.text = "allocation.recurrence.duration".localized
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private lazy var durationButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = Fonts.textSM.font
        button.setTitleColor(Colors.mainMagenta, for: .normal)
        button.showsMenuAsPrimaryAction = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }()

    /// Spells out the concrete end month ("Until Dec 2026") for whatever preset is chosen.
    private let durationResolvedLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.textAlignment = .right
        label.isHidden = true
        return label
    }()

    let separator: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let saveButton = Button(label: "allocation.add.save".localized)

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = Colors.gray100
        layer.cornerRadius = CornerRadius.bottomSheet

        // Build category display view for edit mode
        categoryDisplayView.addSubview(categoryDisplayStackView)
        categoryDisplayStackView.addArrangedSubview(categoryDisplayIcon)
        categoryDisplayStackView.addArrangedSubview(categoryDisplayLabel)

        NSLayoutConstraint.activate([
            // Match the height of Input component
            categoryDisplayView.heightAnchor.constraint(equalToConstant: Metrics.inputHeight),

            // Center the content vertically
            categoryDisplayStackView.centerYAnchor.constraint(equalTo: categoryDisplayView.centerYAnchor),
            categoryDisplayStackView.leadingAnchor.constraint(
                equalTo: categoryDisplayView.leadingAnchor, constant: Metrics.spacing4),
            categoryDisplayStackView.trailingAnchor.constraint(
                lessThanOrEqualTo: categoryDisplayView.trailingAnchor, constant: -Metrics.spacing4),
            categoryDisplayIcon.widthAnchor.constraint(equalToConstant: 20),
            categoryDisplayIcon.heightAnchor.constraint(equalToConstant: 20)
        ])

        // Build recurring option stack (label + switch)
        recurringOptionStackView.addArrangedSubview(recurringLabel)
        recurringOptionStackView.addArrangedSubview(recurringSwitch)

        // Build recurring section stack (section label + option row + duration disclosure)
        recurringSectionStackView.addArrangedSubview(recurringSectionLabel)
        recurringSectionStackView.addArrangedSubview(recurringOptionStackView)
        recurringSectionStackView.addArrangedSubview(durationRowStackView)
        recurringSectionStackView.addArrangedSubview(durationResolvedLabel)

        recurringSwitch.addTarget(self, action: #selector(recurringSwitchChanged), for: .valueChanged)
        rebuildDurationMenu()
        updateDurationDisplay()

        addSubview(contentStackView)
        addSubview(categoryDisplayView)
        closeIconButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(didTapSaveAllocation), for: .touchUpInside)

        // Add Done button toolbar to amount input
        amountTextField.addDoneButtonToolbar()

        // Add extra spacing after recurring section before separator
        contentStackView.setCustomSpacing(Metrics.spacing10, after: recurringSectionStackView)

        setupConstraints()
    }

    private func setupConstraints() {
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - Configuration

    func configure(availableCategories: [TransactionCategory], preselectedCategory: TransactionCategory? = nil) {
        self.availableCategories = availableCategories
        let categoryKeys = availableCategories.map { $0.key }
        categoryPickerView.updatePickerValues(categoryKeys)

        // If a preselected category is provided, select it in the picker
        if let preselected = preselectedCategory,
           let index = availableCategories.firstIndex(where: { $0.key == preselected.key }) {
            categoryPickerView.selectPickerValue(at: index)
        }
    }

    func configureForEdit(allocation: BudgetAllocation) {
        isEditMode = true
        editingAllocation = allocation

        // Update title
        headerTitleLabel.text = "allocation.edit.title".localized
        headerTitleLabel.applyStyle()

        // Update save button
        saveButton.setTitle("allocation.edit.save".localized, for: .normal)

        // Replace category picker with category display in the stack
        // First remove picker from stack and insert display view in its place
        if let pickerIndex = inputStackView.arrangedSubviews.firstIndex(of: categoryPickerView) {
            inputStackView.removeArrangedSubview(categoryPickerView)
            categoryPickerView.removeFromSuperview()
            inputStackView.insertArrangedSubview(categoryDisplayView, at: pickerIndex)
        }

        categoryDisplayView.isHidden = false
        categoryDisplayIcon.image = UIImage(named: allocation.category.iconName)
        categoryDisplayLabel.text = allocation.category.displayName

        // Pre-fill amount
        amountTextField.setCentsValue(allocation.allocatedAmount)

        // Set recurring switch (disabled in edit mode)
        recurringSwitch.isOn = allocation.isRecurring || allocation.parentAllocationId != nil
        recurringSwitch.isEnabled = false
        recurringLabel.textColor = Colors.gray400
    }

    // MARK: - Actions

    @objc private func didTapClose() {
        delegate?.didTapClose()
    }

    // MARK: - Recurrence Duration

    @objc private func recurringSwitchChanged() {
        let on = recurringSwitch.isOn
        if !on { recurrenceEndMonth = nil }
        UIView.animate(withDuration: 0.2) {
            self.durationRowStackView.isHidden = !on
            self.durationResolvedLabel.isHidden = !on || self.recurrenceEndMonth == nil
            self.layoutIfNeeded()
        }
        updateDurationDisplay()
    }

    /// Month anchor `count` months after the allocation's own month.
    private func monthAnchor(offsetFromBase count: Int) -> Int? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(abbreviation: "UTC")!
        let base = Date(timeIntervalSince1970: TimeInterval(baseMonthAnchor))
        return cal.date(byAdding: .month, value: count, to: base)?.monthAnchor
    }

    private func monthDisplayName(for anchor: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM yyyy"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(anchor)))
    }

    private func rebuildDurationMenu() {
        var actions: [UIMenuElement] = []

        actions.append(UIAction(
            title: "allocation.recurrence.always".localized,
            state: recurrenceEndMonth == nil ? .on : .off
        ) { [weak self] _ in
            self?.recurrenceEndMonth = nil
            self?.rebuildDurationMenu()
            self?.updateDurationDisplay()
        })

        for preset in Self.durationPresets {
            // A preset of N means N more months on top of the starting month.
            guard let anchor = monthAnchor(offsetFromBase: preset - 1) else { continue }
            actions.append(UIAction(
                title: String(format: "allocation.recurrence.months".localized, preset),
                state: recurrenceEndMonth == anchor ? .on : .off
            ) { [weak self] _ in
                self?.recurrenceEndMonth = anchor
                self?.rebuildDurationMenu()
                self?.updateDurationDisplay()
            })
        }

        // Exact end month — a submenu of every month within the generation horizon.
        var monthActions: [UIAction] = []
        for offset in 1...RecurringTransactionManager.horizonMonths {
            guard let anchor = monthAnchor(offsetFromBase: offset) else { continue }
            monthActions.append(UIAction(
                title: monthDisplayName(for: anchor),
                state: recurrenceEndMonth == anchor ? .on : .off
            ) { [weak self] _ in
                self?.recurrenceEndMonth = anchor
                self?.rebuildDurationMenu()
                self?.updateDurationDisplay()
            })
        }
        actions.append(UIMenu(
            title: "allocation.recurrence.chooseEnd".localized,
            children: monthActions))

        durationButton.menu = UIMenu(title: "", children: actions)
    }

    private func updateDurationDisplay() {
        if let end = recurrenceEndMonth {
            // Show the preset label when it matches one, otherwise the month itself.
            let matchedPreset = Self.durationPresets.first { monthAnchor(offsetFromBase: $0 - 1) == end }
            let title = matchedPreset.map { String(format: "allocation.recurrence.months".localized, $0) }
                ?? monthDisplayName(for: end)
            durationButton.setTitle("\(title)  ⌄", for: .normal)
            durationResolvedLabel.text = String(
                format: "allocation.recurrence.until".localized, monthDisplayName(for: end))
            durationResolvedLabel.isHidden = !recurringSwitch.isOn
        } else {
            durationButton.setTitle("\("allocation.recurrence.always".localized)  ⌄", for: .normal)
            durationResolvedLabel.isHidden = true
        }
    }

    @objc private func didTapSaveAllocation() {
        let selectedCategory: TransactionCategory

        if isEditMode {
            // In edit mode, use the existing category
            guard let allocation = editingAllocation else { return }
            selectedCategory = allocation.category
        } else {
            // Validate category in create mode
            guard categoryPickerView.selectedPickerIndex >= 0,
                  categoryPickerView.selectedPickerIndex < availableCategories.count else {
                categoryPickerView.setError(true)
                delegate?.handleError(
                    title: "allocation.add.error.category.title".localized,
                    message: "allocation.add.error.category.message".localized
                )
                return
            }
            selectedCategory = availableCategories[categoryPickerView.selectedPickerIndex]
        }

        // Validate amount
        guard amountTextField.centsValue > 0 else {
            amountTextField.setError(true)
            delegate?.handleError(
                title: "allocation.add.error.amount.title".localized,
                message: "allocation.add.error.amount.message".localized
            )
            return
        }

        let amount = amountTextField.centsValue
        let isRecurring = recurringSwitch.isOn

        delegate?.didTapSave(
            category: selectedCategory,
            amount: amount,
            isRecurring: isRecurring,
            recurrenceEndMonth: isRecurring ? recurrenceEndMonth : nil)
    }
}
