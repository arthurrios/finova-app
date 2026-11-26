//
//  BudgetsView.swift
//  FinanceApp
//
//  Created by Arthur Rios on 16/05/25.
//

import Foundation
import UIKit

final class BudgetsView: UIView {
    public weak var delegate: BudgetsViewDelegate?
    
    private var tableHeightConstraint: NSLayoutConstraint?
    private var budgets: [DisplayBudgetModel] = []

    private lazy var hideValuesButton: HideValuesButton = {
        let button = HideValuesButton(style: .onHeader)
        // BudgetsCell masks at render time, so the rows only need a reload.
        button.onToggle = { [weak self] _ in
            self?.budgetsTableView.reloadData()
            self?.refreshSuggestion()
        }
        return button
    }()
    
    private let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight).isActive = true
        return view
    }()
    
    private let headerItemsView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing4, leading: Metrics.spacing5, bottom: Metrics.spacing5,
            trailing: Metrics.spacing5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    lazy var headerTextStackView = UIStackView(
        axis: .vertical, spacing: Metrics.spacing1,
        arrangedSubviews: [headerTitleLabel, headerSubtitleLabel])
    
    private let backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false

        if #available(iOS 26.0, *) {
            button.tintColor = Colors.gray700
        } else {
            button.tintColor = Colors.gray500
        }

        return button
    }()

    private lazy var backButtonGlassContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()
    
    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.text = "budgets.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let headerSubtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.text = "budgets.header.subtitle".localized
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let newBudgetCardHeaderView = CardHeader(
        headerTitle: "budgets.new.header.title".localized)
    
    private lazy var cardContentView: UIStackView = {
        let stackView = UIStackView(
            axis: .vertical, spacing: Metrics.spacing4,
            arrangedSubviews: [inputStackView, suggestionButton, repeatRowStackView, repeatResolvedLabel, addButton])
        stackView.layoutMargins = UIEdgeInsets(
            top: Metrics.spacing5, left: Metrics.spacing5, bottom: Metrics.spacing5,
            right: Metrics.spacing5)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.distribution = .fill
        stackView.backgroundColor = Colors.gray100
        stackView.layer.borderWidth = 1
        stackView.layer.borderColor = Colors.gray300.cgColor
        stackView.layer.cornerRadius = CornerRadius.extraLarge
        stackView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        stackView.clipsToBounds = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private lazy var inputStackView: UIStackView = {
        let stackView = UIStackView(
            axis: .horizontal, spacing: Metrics.spacing3, arrangedSubviews: [dateInput, budgetValueInput])
        stackView.distribution = .fillEqually
        stackView.heightAnchor.constraint(equalToConstant: Metrics.inputHeight).isActive = true
        return stackView
    }()
    
    private let dateInput = Input(
        type: .date(style: .monthYear), placeholder: "00/0000", icon: UIImage(named: "calendar"))
    
    private let budgetValueInput = Input(type: .currency, placeholder: "0,00")
    
    private let addButton = Button(label: "budgets.button.add.title".localized)

    /// Offers the month's income as the amount. It only fills the field: saving stays the user's tap,
    /// and with no income in the month there is nothing to offer, so the row collapses.
    private let suggestionButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = Fonts.textSM.font
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.contentHorizontalAlignment = .leading
        button.setTitleColor(Colors.mainMagenta, for: .normal)
        button.isHidden = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return button
    }()

    // MARK: - Repeat for (many months at once)
    //
    // Same presets and look as the allocation form's "Repeat for" row. The default is this month
    // only, so a plain save behaves exactly as before.

    enum RepeatChoice: Equatable {
        case thisMonthOnly
        /// N months counting the start month.
        case months(Int)
        /// Through this month anchor.
        case until(Int)
    }

    static let repeatPresets = [3, 6, 12, 24]
    private(set) var repeatChoice: RepeatChoice = .thisMonthOnly

    private lazy var repeatRowStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [repeatLabel, repeatButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        stack.setContentHuggingPriority(.required, for: .vertical)
        return stack
    }()

    private let repeatLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray700
        label.text = "allocation.recurrence.duration".localized
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private lazy var repeatButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = Fonts.textSM.font
        button.setTitleColor(Colors.mainMagenta, for: .normal)
        button.showsMenuAsPrimaryAction = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        button.accessibilityIdentifier = "budgets.repeat.button"
        return button
    }()

    /// Spells out the last month ("Until Dec 2026") for whatever is chosen.
    private let repeatResolvedLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.textAlignment = .right
        label.isHidden = true
        return label
    }()

    /// The month typed in the form, or this month when the field is empty.
    private var repeatBaseAnchor: Int {
        dateInput.textField.text
            .flatMap { DateFormatter.monthYearFormatter.date(from: $0) }?.monthAnchor
            ?? Date().monthAnchor
    }

    /// The last month to write, or `nil` for this month only.
    var repeatEndMonth: Int? {
        let base = repeatBaseAnchor
        switch repeatChoice {
        case .thisMonthOnly:
            return nil
        case .months(let count):
            return BudgetsViewModel.monthAnchor(base, plusMonths: count - 1)
        case .until(let anchor):
            return anchor > base ? anchor : nil
        }
    }

    private func setRepeatChoice(_ choice: RepeatChoice) {
        repeatChoice = choice
        refreshRepeatRow()
    }

    private func repeatMonthName(_ anchor: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(anchor)))
    }

    private func refreshRepeatRow() {
        let base = repeatBaseAnchor
        // An end month chosen for an older start can fall before a new start: drop it.
        if case .until(let anchor) = repeatChoice, anchor <= base { repeatChoice = .thisMonthOnly }

        var actions: [UIMenuElement] = [
            UIAction(
                title: "budgets.repeat.thisMonthOnly".localized,
                state: repeatChoice == .thisMonthOnly ? .on : .off
            ) { [weak self] _ in self?.setRepeatChoice(.thisMonthOnly) }
        ]
        for preset in Self.repeatPresets {
            actions.append(UIAction(
                title: String(format: "allocation.recurrence.months".localized, preset),
                state: repeatChoice == .months(preset) ? .on : .off
            ) { [weak self] _ in self?.setRepeatChoice(.months(preset)) })
        }
        var monthActions: [UIAction] = []
        for offset in 1...RecurringTransactionManager.horizonMonths {
            let anchor = BudgetsViewModel.monthAnchor(base, plusMonths: offset)
            monthActions.append(UIAction(
                title: repeatMonthName(anchor),
                state: repeatChoice == .until(anchor) ? .on : .off
            ) { [weak self] _ in self?.setRepeatChoice(.until(anchor)) })
        }
        actions.append(UIMenu(title: "allocation.recurrence.chooseEnd".localized, children: monthActions))
        repeatButton.menu = UIMenu(title: "", children: actions)

        let title: String
        switch repeatChoice {
        case .thisMonthOnly: title = "budgets.repeat.thisMonthOnly".localized
        case .months(let count): title = String(format: "allocation.recurrence.months".localized, count)
        case .until(let anchor): title = repeatMonthName(anchor)
        }
        repeatButton.setTitle("\(title)  ⌄", for: .normal)

        if let end = repeatEndMonth {
            repeatResolvedLabel.text = String(
                format: "allocation.recurrence.until".localized, repeatMonthName(end))
            repeatResolvedLabel.isHidden = false
        } else {
            repeatResolvedLabel.isHidden = true
        }
    }

    /// The income of the month typed in the form, from the view controller.
    var suggestedAmount: ((String) -> Int)?
    private var suggestedCents = 0
    
    private let budgetsTableHeaderView = CardHeader(
        headerTitle: "budgets.table.header.title".localized)

    /// Entry point to allocation tags. Overlaid on the header rather than added to its stack:
    /// `CardHeader`'s stack is `.equalSpacing` and shared by several screens, so a third arranged
    /// subview would redistribute the spacing everywhere it is used. The header's trailing side is
    /// free here because no items-quantity pill is passed.
    private let manageTagsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("budgets.tags.manage".localized, for: .normal)
        button.titleLabel?.font = Fonts.titleXS.font
        button.setTitleColor(Colors.mainMagenta, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    let budgetsTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Colors.gray100
        tableView.layer.borderWidth = 1
        tableView.layer.borderColor = Colors.gray300.cgColor
        tableView.layer.cornerRadius = CornerRadius.extraLarge
        tableView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets.zero
        tableView.clipsToBounds = true
        tableView.separatorColor = Colors.gray300
        tableView.isScrollEnabled = true
        tableView.showsVerticalScrollIndicator = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    private let emptyStateView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.borderWidth = 1
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let emptyStateIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "iconBankSlip")
        imageView.tintColor = Colors.gray400
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let emptyStateDescriptionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.text = "budgets.emptyState.description".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: .zero)
        setupView()
        
        dateInput.textField.delegate = self
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissPicker))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
        
        if let picker = dateInput.textField.inputView as? UIDatePicker {
            picker.addTarget(
                self,
                action: #selector(pickerValueChanged(_:)),
                for: .valueChanged)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc
    private func dismissPicker() {
        endEditing(true)
    }
    
    private func setupView() {
        backgroundColor = Colors.gray200
        
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        setupBackButtonGlassEffect()
        headerItemsView.addSubview(hideValuesButton)
        headerItemsView.addSubview(headerTextStackView)
        
        addSubview(newBudgetCardHeaderView)
        addSubview(cardContentView)
        cardContentView.addSubview(inputStackView)
        cardContentView.addSubview(suggestionButton)
        cardContentView.addSubview(addButton)
        
        addSubview(budgetsTableHeaderView)
        budgetsTableHeaderView.addSubview(manageTagsButton)
        addSubview(budgetsTableView)
        
        addSubview(emptyStateView)
        emptyStateView.addSubview(emptyStateIconImageView)
        emptyStateView.addSubview(emptyStateDescriptionLabel)
        
        cardContentView.accessibilityIdentifier = CoachMarkTarget.budgetsForm.rawValue
        budgetsTableHeaderView.accessibilityIdentifier = CoachMarkTarget.budgetsList.rawValue
        backButtonGlassContainer.accessibilityIdentifier = CoachMarkTarget.budgetsBack.rawValue

        backButton.addTarget(self, action: #selector(didTapBackButton), for: .touchUpInside)
        addButton.addTarget(self, action: #selector(didTapAddBudgetButton), for: .touchUpInside)
        suggestionButton.addTarget(self, action: #selector(didTapSuggestion), for: .touchUpInside)
        manageTagsButton.addTarget(self, action: #selector(didTapManageTags), for: .touchUpInside)
        refreshRepeatRow()
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            
            backButtonGlassContainer.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
            backButtonGlassContainer.leadingAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
            backButtonGlassContainer.widthAnchor.constraint(equalToConstant: 36),
            backButtonGlassContainer.heightAnchor.constraint(equalToConstant: 36),

            backButton.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
            backButton.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
            backButton.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
            backButton.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),

            hideValuesButton.trailingAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.trailingAnchor),
            hideValuesButton.centerYAnchor.constraint(
                equalTo: backButtonGlassContainer.centerYAnchor),

            headerTextStackView.leadingAnchor.constraint(
                equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
            headerTextStackView.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),
            headerTextStackView.trailingAnchor.constraint(
                lessThanOrEqualTo: hideValuesButton.leadingAnchor, constant: -Metrics.spacing3),
            
            newBudgetCardHeaderView.topAnchor.constraint(
                equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing4),
            newBudgetCardHeaderView.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: Metrics.spacing4),
            newBudgetCardHeaderView.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -Metrics.spacing4),
            
            cardContentView.topAnchor.constraint(equalTo: newBudgetCardHeaderView.bottomAnchor),
            cardContentView.leadingAnchor.constraint(equalTo: newBudgetCardHeaderView.leadingAnchor),
            cardContentView.trailingAnchor.constraint(equalTo: newBudgetCardHeaderView.trailingAnchor),
            
            budgetsTableHeaderView.topAnchor.constraint(
                equalTo: cardContentView.bottomAnchor, constant: Metrics.spacing4),
            budgetsTableHeaderView.leadingAnchor.constraint(equalTo: cardContentView.leadingAnchor),
            budgetsTableHeaderView.trailingAnchor.constraint(equalTo: cardContentView.trailingAnchor),
            
            manageTagsButton.trailingAnchor.constraint(
                equalTo: budgetsTableHeaderView.trailingAnchor, constant: -Metrics.spacing4),
            manageTagsButton.centerYAnchor.constraint(equalTo: budgetsTableHeaderView.centerYAnchor),

            budgetsTableView.topAnchor.constraint(equalTo: budgetsTableHeaderView.bottomAnchor),
            budgetsTableView.leadingAnchor.constraint(equalTo: cardContentView.leadingAnchor),
            budgetsTableView.trailingAnchor.constraint(equalTo: cardContentView.trailingAnchor),
            budgetsTableView.bottomAnchor.constraint(
                lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -Metrics.spacing8),
            
            emptyStateView.topAnchor.constraint(equalTo: budgetsTableHeaderView.bottomAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: cardContentView.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: cardContentView.trailingAnchor),
            emptyStateView.heightAnchor.constraint(equalToConstant: Metrics.tableEmptyViewHeight),
            
            emptyStateIconImageView.leadingAnchor.constraint(
                equalTo: emptyStateView.leadingAnchor, constant: Metrics.spacing5),
            emptyStateIconImageView.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor),
            emptyStateIconImageView.heightAnchor.constraint(equalToConstant: Metrics.spacing8),
            emptyStateIconImageView.widthAnchor.constraint(equalToConstant: Metrics.spacing8),
            
            emptyStateDescriptionLabel.leadingAnchor.constraint(
                equalTo: emptyStateIconImageView.trailingAnchor, constant: Metrics.spacing5),
            emptyStateDescriptionLabel.trailingAnchor.constraint(
                equalTo: emptyStateView.trailingAnchor, constant: -Metrics.spacing4),
            emptyStateDescriptionLabel.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor)
        ])
    }

    private func setupBackButtonGlassEffect() {
        backButtonGlassContainer.applyClearGlass(cornerRadius: 18)
    }

    func updateUI(with budgets: [DisplayBudgetModel], selectedDate: Date?) {
        self.budgets = budgets
        
        if let selectedDate = selectedDate {
            self.dateInput.text = DateFormatter.monthYearFormatter.string(from: selectedDate)
        }
        
        refreshSuggestion()

        if budgets.isEmpty {
            budgetsTableView.isHidden = true
            emptyStateView.isHidden = false
        } else {
            budgetsTableView.isHidden = false
            emptyStateView.isHidden = true
            budgetsTableView.reloadData()
        }
    }
    
    func clearTextFields() {
        dateInput.textField.text = ""
        budgetValueInput.textField.text = ""
        repeatChoice = .thisMonthOnly
        refreshSuggestion()
    }

    private func refreshSuggestion() {
        suggestedCents = dateInput.textField.text.flatMap { suggestedAmount?($0) } ?? 0
        suggestionButton.isHidden = suggestedCents <= 0
        suggestionButton.setTitle(
            String(
                format: "budgets.suggestion.income".localized,
                suggestedCents.maskedCurrencyString()),
            for: .normal)
        refreshRepeatRow()
    }

    @objc
    private func didTapSuggestion() {
        budgetValueInput.setCentsValue(suggestedCents)
    }
    
    func toggleEmptyState(_ show: Bool) {
        budgetsTableView.isHidden = show
        emptyStateView.isHidden = !show
    }
    
    @objc
    private func didTapBackButton() {
        delegate?.didTapBackButton()
    }

    @objc
    private func didTapManageTags() {
        delegate?.didTapManageTags()
    }
    
    @objc
    private func didTapAddBudgetButton() {
        let inputs = [dateInput, budgetValueInput]
        
        let invalids = inputs.filter { !$0.textField.hasText }
        
        invalids.forEach { $0.setError(true) }
        
        guard invalids.isEmpty else { return }
        
        let date = dateInput.textField.text ?? ""
        let budget = budgetValueInput.centsValue
        if let endMonth = repeatEndMonth {
            delegate?.didTapAddBudgets(monthYearDate: date, budgetAmount: budget, endMonth: endMonth)
        } else {
            delegate?.didTapAddBudgetButton(monthYearDate: date, budgetAmount: budget)
        }
    }
}

extension BudgetsView: UITextFieldDelegate {
    func textFieldDidEndEditing(_ textField: UITextField) {
        guard textField == dateInput.textField,
              let picker = textField.inputView as? UIDatePicker
        else { return }
        
        let formatted = DateFormatter.monthYearFormatter.string(from: picker.date)
        textField.text = formatted
        refreshSuggestion()
    }
    
    @objc private func pickerValueChanged(_ picker: UIDatePicker) {
        dateInput.textField.text = DateFormatter.monthYearFormatter.string(from: picker.date)
        refreshSuggestion()
    }
}
