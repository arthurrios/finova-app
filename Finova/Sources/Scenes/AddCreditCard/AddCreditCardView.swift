//
//  AddCreditCardView.swift
//  Finova
//

import UIKit

final class AddCreditCardView: UIView {
    weak var delegate: AddCreditCardViewDelegate?

    // MARK: - Header
    private let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight - 12).isActive = true
        return view
    }()

    private let headerItemsView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing4, leading: Metrics.spacing5,
            bottom: Metrics.spacing5, trailing: Metrics.spacing5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 26.0, *) { button.tintColor = Colors.gray700 }
        else { button.tintColor = Colors.gray500 }
        return button
    }()

    private lazy var backButtonGlassContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.text = "addCreditCard.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Scroll + Form
    let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let scrollContentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let formCardView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.borderWidth = 1
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let formStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing5
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Form Fields
    let nameInput = Input(placeholder: "addCreditCard.input.name.placeholder".localized)
    let lastFourInput = Input(type: .number, placeholder: "1234")
    let closingDayInput = Input(type: .picker(values: (1...28).map { String($0) }), placeholder: "15")
    let dueDayInput = Input(type: .picker(values: (1...28).map { String($0) }), placeholder: "22")
    let creditLimitInput = Input(type: .currency, placeholder: "0,00")

    // MARK: - Brand Selector
    let brandSelector: Input = {
        let input = Input(
            type: .picker(values: CardBrand.allCases.map { $0.displayName }),
            placeholder: CardBrand.allCases.first?.displayName ?? "")
        input.selectPickerValue(at: 0)
        return input
    }()

    // MARK: - Color Selector
    let colorStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Metrics.spacing3
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Default Switch
    private let defaultSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.onTintColor = Colors.mainMagenta
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }()

    var isDefaultCard: Bool {
        get { defaultSwitch.isOn }
        set { defaultSwitch.isOn = newValue }
    }

    var selectedColor: CardColor = .blue
    private var colorButtons: [UIButton] = []

    // MARK: - Footer
    private lazy var actionButtonsContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var footerBorderView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var actionButtonsStackView: UIStackView = {
        let stackView = UIStackView(
            axis: .vertical,
            spacing: Metrics.spacing3,
            arrangedSubviews: [saveButton]
        )
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing4, leading: Metrics.spacing4, bottom: Metrics.spacing4,
            trailing: Metrics.spacing4)
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }()

    let saveButton = Button(variant: .base, label: "addCreditCard.button.save".localized)

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup
    private func setupView() {
        backgroundColor = Colors.gray200

        // Header - fixed at top
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        setupBackButtonGlassEffect()
        headerItemsView.addSubview(headerTitleLabel)

        // Scroll view - between header and footer
        addSubview(scrollView)
        scrollView.addSubview(scrollContentView)

        scrollContentView.addSubview(formCardView)
        formCardView.addSubview(formStackView)

        formStackView.addArrangedSubview(createLabeledField(label: "addCreditCard.input.name".localized, field: nameInput))
        formStackView.addArrangedSubview(createLabeledField(label: "addCreditCard.input.lastFourDigits".localized, field: lastFourInput, hint: "addCreditCard.input.lastFourDigits.hint".localized))
        formStackView.addArrangedSubview(createLabeledField(label: "addCreditCard.input.brand".localized, field: brandSelector))
        formStackView.addArrangedSubview(createLabeledField(label: "addCreditCard.input.closingDay".localized, field: closingDayInput, hint: "addCreditCard.input.closingDay.hint".localized))
        formStackView.addArrangedSubview(createLabeledField(label: "addCreditCard.input.dueDay".localized, field: dueDayInput, hint: "addCreditCard.input.dueDay.hint".localized))
        formStackView.addArrangedSubview(createLabeledField(label: "addCreditCard.input.creditLimit".localized, field: creditLimitInput))
        setupColorSelector()
        formStackView.addArrangedSubview(createLabeledField(label: "addCreditCard.input.color".localized, field: colorStackView))
        formStackView.addArrangedSubview(createDefaultSwitchRow())

        // Footer - fixed at bottom
        addSubview(actionButtonsContainerView)
        actionButtonsContainerView.addSubview(footerBorderView)
        actionButtonsContainerView.addSubview(actionButtonsStackView)

        setupConstraints()
        setupActions()

        nameInput.addDoneButtonToolbar()
        lastFourInput.addDoneButtonToolbar()
        creditLimitInput.addDoneButtonToolbar()
    }

    private func setupColorSelector() {
        for color in CardColor.allCases {
            let button = UIButton()
            button.backgroundColor = color.startColor
            button.layer.cornerRadius = 16
            button.clipsToBounds = true
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
            button.tag = CardColor.allCases.firstIndex(of: color) ?? 0
            button.addTarget(self, action: #selector(colorSelected(_:)), for: .touchUpInside)
            if color == selectedColor {
                button.layer.borderWidth = 3
                button.layer.borderColor = Colors.mainMagenta.cgColor
            }
            colorButtons.append(button)
            colorStackView.addArrangedSubview(button)
        }
    }

    @objc private func colorSelected(_ sender: UIButton) {
        selectedColor = CardColor.allCases[sender.tag]
        colorButtons.forEach {
            $0.layer.borderWidth = 0
            $0.layer.borderColor = nil
        }
        sender.layer.borderWidth = 3
        sender.layer.borderColor = Colors.mainMagenta.cgColor
    }

    private func createLabeledField(label: String, field: UIView, hint: String? = nil) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = label
        titleLabel.font = Fonts.textSM.font
        titleLabel.textColor = Colors.gray600
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        var views: [UIView] = [titleLabel, field]

        if let hint = hint {
            let hintLabel = UILabel()
            hintLabel.text = hint
            hintLabel.font = Fonts.textXS.font
            hintLabel.textColor = Colors.gray400
            hintLabel.translatesAutoresizingMaskIntoConstraints = false
            views.append(hintLabel)
        }

        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = Metrics.spacing1
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func createDefaultSwitchRow() -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = "addCreditCard.input.defaultCard".localized
        titleLabel.font = Fonts.textSM.font
        titleLabel.textColor = Colors.gray600
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let hintLabel = UILabel()
        hintLabel.text = "addCreditCard.input.defaultCard.hint".localized
        hintLabel.font = Fonts.textXS.font
        hintLabel.textColor = Colors.gray400
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        let labelStack = UIStackView(arrangedSubviews: [titleLabel, hintLabel])
        labelStack.axis = .vertical
        labelStack.spacing = Metrics.spacing1
        labelStack.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [labelStack, defaultSwitch])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Metrics.spacing3
        row.translatesAutoresizingMaskIntoConstraints = false

        return row
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Header - fixed at top
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

            backButtonGlassContainer.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
            backButtonGlassContainer.leadingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
            backButtonGlassContainer.widthAnchor.constraint(equalToConstant: 36),
            backButtonGlassContainer.heightAnchor.constraint(equalToConstant: 36),

            backButton.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
            backButton.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
            backButton.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
            backButton.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),

            headerTitleLabel.leadingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
            headerTitleLabel.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),

            // Scroll view - between header and footer
            scrollView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionButtonsContainerView.topAnchor),

            // Scroll content view
            scrollContentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            scrollContentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            scrollContentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            scrollContentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            scrollContentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Form card
            formCardView.topAnchor.constraint(equalTo: scrollContentView.topAnchor, constant: Metrics.spacing5),
            formCardView.leadingAnchor.constraint(equalTo: scrollContentView.leadingAnchor, constant: Metrics.spacing4),
            formCardView.trailingAnchor.constraint(equalTo: scrollContentView.trailingAnchor, constant: -Metrics.spacing4),
            formCardView.bottomAnchor.constraint(equalTo: scrollContentView.bottomAnchor, constant: -Metrics.spacing5),

            // Form stack inside card
            formStackView.topAnchor.constraint(equalTo: formCardView.topAnchor, constant: Metrics.spacing5),
            formStackView.leadingAnchor.constraint(equalTo: formCardView.leadingAnchor, constant: Metrics.spacing5),
            formStackView.trailingAnchor.constraint(equalTo: formCardView.trailingAnchor, constant: -Metrics.spacing5),
            formStackView.bottomAnchor.constraint(equalTo: formCardView.bottomAnchor, constant: -Metrics.spacing5),

            // Footer - fixed at bottom
            actionButtonsContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            actionButtonsContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionButtonsContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            footerBorderView.topAnchor.constraint(equalTo: actionButtonsContainerView.topAnchor),
            footerBorderView.leadingAnchor.constraint(equalTo: actionButtonsContainerView.leadingAnchor),
            footerBorderView.trailingAnchor.constraint(equalTo: actionButtonsContainerView.trailingAnchor),
            footerBorderView.heightAnchor.constraint(equalToConstant: 1),

            actionButtonsStackView.topAnchor.constraint(equalTo: footerBorderView.bottomAnchor),
            actionButtonsStackView.leadingAnchor.constraint(equalTo: actionButtonsContainerView.leadingAnchor),
            actionButtonsStackView.trailingAnchor.constraint(equalTo: actionButtonsContainerView.trailingAnchor),
            actionButtonsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func setupBackButtonGlassEffect() {
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .clear)
            glassEffect.isInteractive = true
            let glassView = UIVisualEffectView(effect: glassEffect)
            glassView.translatesAutoresizingMaskIntoConstraints = false
            backButtonGlassContainer.insertSubview(glassView, at: 0)
            backButtonGlassContainer.layer.cornerRadius = 18
            backButtonGlassContainer.clipsToBounds = true
            NSLayoutConstraint.activate([
                glassView.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
                glassView.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
                glassView.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),
            ])
        }
    }

    private func setupActions() {
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        let backTapGesture = UITapGestureRecognizer(target: self, action: #selector(backTapped))
        backButtonGlassContainer.addGestureRecognizer(backTapGesture)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
    }

    @objc private func backTapped() { delegate?.didTapBack() }
    @objc private func saveTapped() { delegate?.didTapSave() }

    // MARK: - Validation

    /// Validates all required inputs. Returns true if valid.
    /// Sets error state on invalid inputs and scrolls to the first one.
    func validateInputs() -> Bool {
        // Clear previous errors
        let requiredInputs: [Input] = [nameInput, lastFourInput, closingDayInput, dueDayInput]
        requiredInputs.forEach { $0.setError(false) }

        var firstInvalidInput: Input?

        // Name: non-empty
        let name = nameInput.text ?? ""
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            nameInput.setError(true)
            if firstInvalidInput == nil { firstInvalidInput = nameInput }
        }

        // Last four digits: exactly 4 digits
        let lastFour = lastFourInput.text ?? ""
        if lastFour.count != 4 {
            lastFourInput.setError(true)
            if firstInvalidInput == nil { firstInvalidInput = lastFourInput }
        }

        // Closing day: must have a value selected
        let closingText = closingDayInput.text ?? ""
        if closingText.isEmpty {
            closingDayInput.setError(true)
            if firstInvalidInput == nil { firstInvalidInput = closingDayInput }
        }

        // Due day: must have a value selected
        let dueText = dueDayInput.text ?? ""
        if dueText.isEmpty {
            dueDayInput.setError(true)
            if firstInvalidInput == nil { firstInvalidInput = dueDayInput }
        }

        if let target = firstInvalidInput {
            scrollToInput(target)
            return false
        }

        return true
    }

    private func scrollToInput(_ input: Input) {
        let inputFrame = input.convert(input.bounds, to: scrollContentView)
        let visibleRect = CGRect(
            x: inputFrame.origin.x,
            y: max(0, inputFrame.origin.y - Metrics.spacing4),
            width: inputFrame.width,
            height: inputFrame.height + 2 * Metrics.spacing4
        )
        scrollView.scrollRectToVisible(visibleRect, animated: true)
    }

    // MARK: - Edit Mode
    func configureForEdit(_ card: CreditCard) {
        headerTitleLabel.text = "editCreditCard.header.title".localized
        headerTitleLabel.applyStyle()
        saveButton.setTitle("editCreditCard.button.save".localized, for: .normal)

        nameInput.text = card.name
        lastFourInput.text = card.lastFourDigits
        closingDayInput.text = "\(card.closingDay)"
        dueDayInput.text = "\(card.dueDay)"
        if let limit = card.creditLimit {
            creditLimitInput.setCentsValue(limit)
        }

        if let brandIndex = CardBrand.allCases.firstIndex(of: card.cardBrand) {
            brandSelector.selectPickerValue(at: brandIndex)
        }

        defaultSwitch.isOn = card.isDefault

        selectedColor = card.cardColor
        colorButtons.forEach { $0.layer.borderWidth = 0 }
        if let colorIndex = CardColor.allCases.firstIndex(of: card.cardColor),
           colorIndex < colorButtons.count {
            colorButtons[colorIndex].layer.borderWidth = 3
            colorButtons[colorIndex].layer.borderColor = Colors.mainMagenta.cgColor
        }
    }
}
