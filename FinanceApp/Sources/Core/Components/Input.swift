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
//            configureCurrencyInput()
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
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: Defaults.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Defaults.iconSize),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            textField.topAnchor.constraint(equalTo: topAnchor, constant: Defaults.verticalPadding),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Defaults.verticalPadding),
        ])
        
        switch iconPosition {
        case .left:
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4).isActive = true
            textField.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Metrics.spacing2).isActive = true
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Defaults.horizontalPadding).isActive = true
        case .right:
            iconImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4).isActive = true
            textField.trailingAnchor.constraint(equalTo: iconImageView.leadingAnchor, constant: -Metrics.spacing2).isActive = true
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Defaults.horizontalPadding).isActive = true
        case .none:
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Defaults.horizontalPadding).isActive = true
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Defaults.horizontalPadding).isActive = true
            break
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
    
    private func configureDateInput(style: DatePickerStyle) {
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .wheels
        picker.locale = Locale.current
        picker.addTarget(self, action: #selector(dateChanged(_:)), for: .valueChanged)
        datePicker = picker
        
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        
        let done = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(dateDoneTapped)
        )
        toolbar.setItems([.flexibleSpace(), done], animated: false)
        
        textField.inputView = picker
        textField.inputAccessoryView = toolbar
        textField.tintColor = .clear
    }
    
    @objc
    private func dateChanged(_ picker: UIDatePicker) {
        dateValue = picker.date
    }
    
    @objc
    private func dateDoneTapped() {
        guard let date = dateValue ?? datePicker?.date else { return }
        
        let formatted: String
        switch datePickerStyle {
        case .monthYear:
            formatted = DateFormatter.monthYearFormatter.string(from: date)
        case .fullDate:
            formatted = DateFormatter.fullDateFormatter.string(from: date)
        }
        
        textField.text = formatted
        textField.sendActions(for: .editingChanged)
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
