//
//  Input.swift
//  FinanceApp
//
//  Created by Arthur Rios on 08/05/25.
//

import Foundation
import UIKit

class Input: UIView {
    // MARK: - Configuration
    enum IconPosition {
        case left, right
    }
    
    enum DatePickerStyle {
        case monthYear, fullDate
    }
    
    enum InputTextFieldType: Equatable {
        case normal
        case password
        case email
        case date(style: DatePickerStyle)
        case currency
        case picker(values: [String])
        
        static func == (lhs: InputTextFieldType, rhs: InputTextFieldType) -> Bool {
            switch (lhs, rhs) {
            case (.normal, .normal):
                return true
            case (.password, .password):
                return true
            case (.email, .email):
                return true
            case (.currency, .currency):
                return true
            case let (.date(style1), .date(style2)):
                return style1 == style2
            default:
                return false
            }
        }
    }
    
    // MARK: - Public Properties
    var placeholder: String
    var icon: UIImage?
    var iconPosition: IconPosition?    
    var pickerDescriptions: [String]?
    var categoryOptions: [TransactionCategory]?
    
    
    // MARK: - Private Defaults
    private struct Defaults {
        static let backgroundColor = Colors.gray200
        static let borderColor = Colors.gray300
        static let iconColor = Colors.gray600
        static let filledColor = Colors.mainMagenta
        static let errorColor = Colors.mainRed
        static let borderWidth: CGFloat = 1
        static let cornerRadius: CGFloat = CornerRadius.large
        static let iconSize: CGFloat = Metrics.inputIconSize
        static let verticalPadding: CGFloat = Metrics.spacing3
        static let horizontalPadding: CGFloat = Metrics.spacing4
    }
    
    private let type: InputTextFieldType?
    private var datePicker: UIDatePicker?
    private var datePickerStyle: DatePickerStyle = .monthYear
    public private(set) var dateValue: Date?
    private var textFieldLeadingConstraint: NSLayoutConstraint?
    public private(set) var centsValue: Int = 0
    
    init(type: InputTextFieldType? = .normal, placeholder: String, icon: UIImage? = nil, iconPosition: IconPosition? = nil) {
        self.placeholder = placeholder
        self.icon = icon
        self.iconPosition = iconPosition
        self.type = type
        super.init(frame: .zero)
        setupDefaults()
        setupView()
        addObservers()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var text: String? {
        get { textField.text }
        set {
            textField.text = newValue
            updateAppearance()
        }
    }
    
    private var isError = false {
        didSet { updateAppearance() }
    }
    
    func setError(_ hasError: Bool) {
        self.isError = hasError
    }
    
    // MARK: - Setup Defaults
    private func setupDefaults() {
        textField.isSecureTextEntry = false
    }
    
    // MARK: - Subviews & State
    let textField: UITextField = {
        let textField = UITextField()
        
        textField.borderStyle = .none
        textField.font = Fonts.input.font
        textField.tintColor = Colors.gray700
        textField.translatesAutoresizingMaskIntoConstraints = false
        
        return textField
    }()
    
    private let iconImageView: UIImageView = {
        let iconImageView = UIImageView()
        
        iconImageView.tintColor = Defaults.iconColor
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        
        return iconImageView
    }()
    
    private func configurePlaceholder(placeholder: String) {
        textField.placeholder = placeholder
        textField.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [NSAttributedString.Key.foregroundColor: Colors.gray400])
    }
    
    private func configurePasswordInput() {
        textField.isSecureTextEntry = true
        iconPosition = .right
        icon = UIImage(named: "eye")?.withRenderingMode(.alwaysTemplate)
        iconImageView.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleSecureEntry))
        iconImageView.addGestureRecognizer(tap)
    }
    
    private let prefixLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleMD.font
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    @objc
    private func toggleSecureEntry() {
        textField.isSecureTextEntry.toggle()
        let imageName = textField.isSecureTextEntry ? "eye" : "eye-closed"
        icon = UIImage(named: imageName)?.withRenderingMode(.alwaysTemplate)
        iconImageView.image = icon
        updateAppearance()
    }
    
    private func configureTextField() {
        switch type {
        case .password:
            configurePasswordInput()
        case .email:
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        case .date(let style):
            datePickerStyle = style
            configureDateInput(style: style)
        case .currency:
            configureCurrencyInput()
            break
        case .picker(let values):
            configurePickerInput(values: values)
            pickerDescriptions = values.map { $0.description }
            break
        case .some(.normal):
            break
        case .none:
            break
        }
        
        configurePlaceholder(placeholder: placeholder)
        
        iconImageView.image = icon?.withRenderingMode(.alwaysTemplate)
    }
    
    private func setupView() {
        configureTextField()
        
        layer.backgroundColor = Defaults.backgroundColor.cgColor
        layer.borderWidth = Defaults.borderWidth
        layer.borderColor = Defaults.borderColor.cgColor
        layer.cornerRadius = Defaults.cornerRadius
        layer.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(textField)
        addSubview(iconImageView)
        
        if case .currency = type {
            addSubview(prefixLabel)
        }
        
        setupConstraints()
    }
    
    private var effectiveIconPosition: IconPosition? {
        switch type {
        case .date, .currency:
            return .left
        default:
            return iconPosition
        }
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Metrics.inputHeight),
        ])
        
        iconImageView.setContentHuggingPriority(.required, for: .horizontal)
        iconImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: Defaults.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Defaults.iconSize),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        
        if case .currency = type {
            prefixLabel.setContentHuggingPriority(.required, for: .horizontal)
            prefixLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            NSLayoutConstraint.activate([
                prefixLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Defaults.horizontalPadding),
                prefixLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                
                textField.leadingAnchor.constraint(equalTo: prefixLabel.trailingAnchor, constant: Metrics.spacing2),
                textField.centerYAnchor.constraint(equalTo: centerYAnchor),
                textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Defaults.horizontalPadding),
            ])
            return
        }
        
        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: topAnchor, constant: Defaults.verticalPadding),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Defaults.verticalPadding),
        ])
        
        switch effectiveIconPosition {
        case .left:
            NSLayoutConstraint.activate([
                iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Defaults.horizontalPadding),
                
                textField.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Metrics.spacing2),
                textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Defaults.horizontalPadding),
            ])
            
        case .right:
            NSLayoutConstraint.activate([
                iconImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
                
                textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Defaults.horizontalPadding),
                textField.trailingAnchor.constraint(equalTo: iconImageView.leadingAnchor, constant: -Metrics.spacing2),
            ])
            
        case .none:
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Defaults.horizontalPadding),
                textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Defaults.horizontalPadding),
            ])
        }
    }
    
    
    
    
    private func addObservers() {
        let events: [UIControl.Event] = [
            .editingDidBegin,
            .editingDidEnd
        ]
        events.forEach {
            textField.addTarget(self,
                                action: #selector(updateAppearance),
                                for: $0)
        }
        
        textField.addTarget(self,
                            action: #selector(textDidChange),
                            for: .editingChanged)
        
        textField.addTarget(self,
                            action: #selector(clearErrorOnTyping),
                            for: .editingChanged)
    }
    
    // MARK: - Date
    
    private func configureDateInput(style: DatePickerStyle) {
        switch style {
        case .monthYear:
            let picker = UIPickerView()
            picker.dataSource = self
            picker.delegate = self
            datePicker = nil
            textField.inputView = picker
        case .fullDate:
            let picker = UIDatePicker()
            picker.datePickerMode = .date
            picker.preferredDatePickerStyle = .wheels
            picker.locale = Locale.current
            picker.addTarget(self, action: #selector(dateChanged(_:)), for: .valueChanged)
            datePicker = picker
            textField.inputView = picker
        }
        
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        
        let done = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(dateDoneTapped)
        )
        toolbar.setItems([.flexibleSpace(), done], animated: false)
        
        textField.inputAccessoryView = toolbar
        textField.tintColor = .clear
    }
    
    private let calendar = Calendar.current
    private let currentYear  = Calendar.current.component(.year, from: Date())
    private let currentMonth = Calendar.current.component(.month, from: Date())
    
    private lazy var allMonths: [String] = {
        DateFormatter().monthSymbols ?? []
    }()
    
    private lazy var years: [Int] = {
        let range = currentYear...currentYear+5
        return Array(range)
    }()
    
    private var selectedMonth = Calendar.current.component(.month, from: Date())
    var pickerValues: [String]?
    var selectedPickerIndex: Int = 0
    private var selectedYear = Calendar.current.component(.year, from: Date())
    
    private func monthOptionsCount() -> Int {
        if selectedYear == currentYear {
            return allMonths.count - (currentMonth - 1)
        } else {
            return allMonths.count
        }
    }
    
    @objc
    private func dateChanged(_ picker: UIDatePicker) {
        dateValue = picker.date
    }
    
    @objc
    private func dateDoneTapped() {
        switch datePickerStyle {
        case .monthYear:
            if dateValue == nil {
                var comps = DateComponents()
                comps.month = selectedMonth
                comps.year  = selectedYear
                dateValue = Calendar.current.date(from: comps)
            }
            
            if let date = dateValue {
                textField.text = DateFormatter.monthYearFormatter.string(from: date)
            }
        case .fullDate:
            guard let date = dateValue ?? datePicker?.date else { return }
            textField.text = DateFormatter.fullDateFormatter.string(from: date)
        }
        
        textField.sendActions(for: .editingChanged)
        textField.resignFirstResponder()
        updateAppearance()
    }
    
    private func configurePickerInput(values: [String]) {
        let picker = UIPickerView()
        picker.dataSource = self
        picker.delegate = self
        self.pickerValues = values
        textField.inputView = picker
        
        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.sizeToFit()
        
        let done = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(pickerDoneTapped)
        )
        toolbar.setItems([.flexibleSpace(), done], animated: false)
        
        textField.inputAccessoryView = toolbar
        textField.tintColor = .clear
    }
    
    @objc private func pickerDoneTapped() {
        if let rawValues = pickerValues {
            let raw = rawValues[selectedPickerIndex]

            if let cat = TransactionCategory.allCases.first(where: { $0.key == raw }) {
                textField.text = cat.description
            } else {
                let human = raw
                    .replacingOccurrences(of: "(?<=[a-z])([A-Z])",
                                          with: " $1",
                                          options: .regularExpression)
                    .capitalized
                textField.text = human
            }
        }
        setError(false)
        textField.resignFirstResponder()
        updateAppearance()
    }

    
    @objc
    private func clearErrorOnTyping() {
        guard isError else { return }
        setError(false)
    }
    
    @objc
    private func textDidChange() {
        guard type == .email else { return }
        
        textField.enableEmailValidation { [weak self] isValid in
            self?.setError(!isValid)
        }
    }
    
    @objc
    private func currencyTextChanged() {
        guard let raw = textField.text else { return }
        let digits = raw
            .compactMap { $0.wholeNumberValue }
            .map(String.init)
            .joined()
        let intValue = Int(digits) ?? 0
        centsValue = intValue
        
        let code = AppConfig.currencyCode
        let frac = CurrencyUtils.fractionDigits(for: code)
        
        let divisor = pow(Decimal(10), frac)
        
        let amountDecimal = Decimal(intValue) / divisor
        
        let amountNumber = NSDecimalNumber(decimal: amountDecimal)
        
        let decFmt = NumberFormatter()
        decFmt.numberStyle             = .decimal
        decFmt.minimumFractionDigits   = frac
        decFmt.maximumFractionDigits   = frac
        decFmt.locale                  = Locale.current
        
        textField.text = decFmt.string(from: amountNumber) ?? ""
    }
    
    @objc
    private func updateAppearance() {
        let isFocused = textField.isFirstResponder
        
        let (borderColor, iconColor, cursorColor): (UIColor, UIColor, UIColor) = {
            if isError {
                return (Defaults.errorColor, Defaults.errorColor, Colors.gray700)
            } else if isFocused {
                return (Defaults.filledColor, Defaults.filledColor, Defaults.filledColor)
            } else {
                return (Defaults.borderColor, Defaults.iconColor, Colors.gray700)
            }
        }()
        
        
        layer.borderColor      = borderColor.cgColor
        iconImageView.tintColor = iconColor
        textField.tintColor     = cursorColor
    }
}


extension Input: UIPickerViewDataSource, UIPickerViewDelegate {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        if case .picker = type {
            return 1
        } else if case .date(let style) = type {
            return style == .monthYear ? 2 : 3
        }
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        if pickerValues != nil {
            return pickerValues?.count ?? 0
        }
        switch component {
        case 0:
            return monthOptionsCount()
        case 1:
            return years.count
        default:
            return 0
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if let rawValues = pickerValues {
            let key = rawValues[row]
            if let cat = TransactionCategory.allCases.first(where: { $0.key == key }) {
                return cat.description
            }
            return key.capitalized
        }

        switch component {
        case 0:
            let index = (selectedYear == currentYear) ? (currentMonth - 1 + row) : row
            return allMonths[index]
        case 1:
            return String(years[row])
        default:
            return nil
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if let rawValues = pickerValues {
                selectedPickerIndex = row
                let key = rawValues[row]

                if let categoryEnum = TransactionCategory.allCases.first(where: { $0.key == key }) {
                    textField.text = categoryEnum.description
                } else {
                    let human = key
                        .replacingOccurrences(of: "(?<=[a-z])([A-Z])",
                                              with: " $1",
                                              options: .regularExpression)
                        .capitalized
                    textField.text = human
                }
                return
            }
        switch component {
        case 1:
            selectedYear = years[row]
            if selectedYear == currentYear && selectedMonth < currentMonth {
                selectedMonth = currentMonth
            }
            pickerView.reloadComponent(0)
            
        case 0:
            selectedMonth = (selectedYear == currentYear)
            ? (currentMonth + row)
            : (row + 1)
        default:
            break
        }
        
        var comps = DateComponents()
        comps.month = selectedMonth
        comps.year = selectedYear
        dateValue = Calendar.current.date(from: comps)
        
        if let date = dateValue {
            textField.text = DateFormatter.monthFormatter.string(from: date)
        }
    }
}

extension Input: UITextFieldDelegate {
    // MARK: - Currency
    
    private func configureCurrencyInput() {
        let code = AppConfig.currencyCode
        let fmt  = NumberFormatter()
        fmt.numberStyle  = .currency
        fmt.currencyCode = code
        let symbol = fmt.currencySymbol ?? code
        
        prefixLabel.text      = symbol
        prefixLabel.font      = Fonts.input.font
        prefixLabel.textColor = Defaults.iconColor
        
        textField.keyboardType = .numberPad
        textField.delegate     = self
        textField.addTarget(self, action: #selector(currencyTextChanged), for: .editingChanged)
    }
}
