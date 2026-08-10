//
//  StatementPaymentView.swift
//  Finova
//

import UIKit

protocol StatementPaymentViewDelegate: AnyObject {
    func didTapBack()
    func didChangeAmount(cents: Int)
    func didChangeSchedule(payToday: Bool)
    func didTapContinue()
}

final class StatementPaymentView: UIView {
    weak var delegate: StatementPaymentViewDelegate?

    private var currentViewModel: StatementPaymentViewModel?
    private var visibilityObservation: ValueVisibilityObservation?
    private let hideValuesButton = HideValuesButton(style: .onHeader)

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

    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.text = "statementPayment.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Scroll

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.showsVerticalScrollIndicator = false
        view.keyboardDismissMode = .interactive
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let scrollContentView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing5
        stack.layoutMargins = UIEdgeInsets(
            top: Metrics.spacing4, left: Metrics.spacing4,
            bottom: Metrics.spacing6, right: Metrics.spacing4)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// A CardHeader sits flush on top of its card, so each pair is its own zero-spacing stack.
    private static func section(_ views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private static func card() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing3
        stack.layoutMargins = UIEdgeInsets(
            top: Metrics.spacing4, left: Metrics.spacing4,
            bottom: Metrics.spacing4, right: Metrics.spacing4)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.backgroundColor = Colors.gray100
        stack.layer.borderWidth = 1
        stack.layer.borderColor = Colors.gray300.cgColor
        stack.layer.cornerRadius = CornerRadius.extraLarge
        stack.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        stack.clipsToBounds = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private let introLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Invoice summary

    private lazy var invoiceHeaderView = CardHeader(
        headerTitle: "statementPayment.invoice.header".localized)
    private lazy var invoiceCard = Self.card()
    private lazy var invoiceSection = Self.section([invoiceHeaderView, invoiceCard])

    private lazy var cardRow = Self.infoRow("statementPayment.invoice.card".localized)
    private lazy var dueDateRow = Self.infoRow("statementPayment.invoice.dueDate".localized)
    private lazy var balanceRow = Self.infoRow("statementPayment.invoice.balance".localized)

    // MARK: - Payment

    private lazy var paymentHeaderView = CardHeader(
        headerTitle: "statementPayment.payment.header".localized)
    private lazy var paymentCard = Self.card()
    private lazy var paymentSection = Self.section([paymentHeaderView, paymentCard])

    private lazy var amountFieldLabel = Self.fieldLabel("statementPayment.amount.label".localized)

    let amountInput = Input(type: .currency, placeholder: "0")

    private let amountErrorLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.mainRed
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var whenLabel = Self.fieldLabel("statementPayment.when.label".localized)

    private lazy var todayOption = PaymentMethodOptionView(
        title: "statementPayment.when.today".localized,
        subtitle: "statementPayment.when.today.subtitle".localized)

    private lazy var scheduleOption = PaymentMethodOptionView(
        title: "statementPayment.when.scheduled".localized,
        subtitle: "statementPayment.when.scheduled.subtitle".localized)

    private lazy var dateFieldLabel = Self.fieldLabel("statementPayment.date.label".localized)

    let dateInput = Input(
        type: .date(style: .fullDate),
        placeholder: "00/00/0000",
        icon: UIImage(named: "calendar")
    )

    private lazy var dateRow = labelledRow(dateFieldLabel, control: dateInput)

    // MARK: - Footer

    private lazy var footerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let footerBorderView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let remainingTitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray600
        label.text = "statementPayment.footer.remaining".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let remainingValueLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let footerNoteLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    lazy var continueButton = Button(
        variant: .base, label: "statementPayment.button.continue".localized)

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func fieldLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray600
        label.text = text
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// A title/value pair on one line, as the statement summary card uses.
    private static func infoRow(_ title: String) -> (container: UIView, value: UILabel) {
        let titleLabel = UILabel()
        titleLabel.font = Fonts.textSM.font
        titleLabel.textColor = Colors.gray500
        titleLabel.text = title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.font = Fonts.textSM.font
        valueLabel.textColor = Colors.gray700
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Metrics.spacing3
        stack.translatesAutoresizingMaskIntoConstraints = false
        return (stack, valueLabel)
    }

    private func setupView() {
        backgroundColor = Colors.gray200

        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        setupBackButtonGlassEffect()
        headerItemsView.addSubview(hideValuesButton)
        headerItemsView.addSubview(headerTitleLabel)

        addSubview(scrollView)
        scrollView.addSubview(scrollContentView)

        scrollContentView.addArrangedSubview(introLabel)
        scrollContentView.addArrangedSubview(invoiceSection)
        scrollContentView.addArrangedSubview(paymentSection)

        invoiceCard.addArrangedSubview(cardRow.container)
        invoiceCard.addArrangedSubview(dueDateRow.container)
        invoiceCard.addArrangedSubview(balanceRow.container)

        paymentCard.addArrangedSubview(labelledRow(amountFieldLabel, control: amountInput))
        paymentCard.addArrangedSubview(amountErrorLabel)
        paymentCard.addArrangedSubview(whenLabel)
        paymentCard.addArrangedSubview(todayOption)
        paymentCard.addArrangedSubview(scheduleOption)
        paymentCard.addArrangedSubview(dateRow)

        addSubview(footerContainerView)
        footerContainerView.addSubview(footerBorderView)
        footerContainerView.addSubview(remainingTitleLabel)
        footerContainerView.addSubview(remainingValueLabel)
        footerContainerView.addSubview(footerNoteLabel)
        footerContainerView.addSubview(continueButton)

        setupConstraints()
        setupActions()
    }

    /// A label stacked above its control, so each field keeps the same height as everywhere else.
    private func labelledRow(_ label: UILabel, control: UIView) -> UIView {
        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .vertical
        stack.spacing = Metrics.spacing2
        stack.translatesAutoresizingMaskIntoConstraints = false
        control.heightAnchor.constraint(equalToConstant: Metrics.inputHeight).isActive = true
        return stack
    }

    private func setupConstraints() {
        remainingValueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

            backButtonGlassContainer.topAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
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

            headerTitleLabel.leadingAnchor.constraint(
                equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
            headerTitleLabel.trailingAnchor.constraint(
                equalTo: hideValuesButton.leadingAnchor, constant: -Metrics.spacing3),
            headerTitleLabel.centerYAnchor.constraint(
                equalTo: backButtonGlassContainer.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerContainerView.topAnchor),

            scrollContentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            scrollContentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            scrollContentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            scrollContentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            scrollContentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            footerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            footerBorderView.topAnchor.constraint(equalTo: footerContainerView.topAnchor),
            footerBorderView.leadingAnchor.constraint(equalTo: footerContainerView.leadingAnchor),
            footerBorderView.trailingAnchor.constraint(equalTo: footerContainerView.trailingAnchor),
            footerBorderView.heightAnchor.constraint(equalToConstant: 1),

            remainingTitleLabel.topAnchor.constraint(
                equalTo: footerBorderView.bottomAnchor, constant: Metrics.spacing4),
            remainingTitleLabel.leadingAnchor.constraint(
                equalTo: footerContainerView.leadingAnchor, constant: Metrics.spacing4),

            remainingValueLabel.centerYAnchor.constraint(
                equalTo: remainingTitleLabel.centerYAnchor),
            remainingValueLabel.trailingAnchor.constraint(
                equalTo: footerContainerView.trailingAnchor, constant: -Metrics.spacing4),
            remainingValueLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: remainingTitleLabel.trailingAnchor,
                constant: Metrics.spacing3),

            footerNoteLabel.topAnchor.constraint(
                equalTo: remainingTitleLabel.bottomAnchor, constant: Metrics.spacing1),
            footerNoteLabel.leadingAnchor.constraint(equalTo: remainingTitleLabel.leadingAnchor),
            footerNoteLabel.trailingAnchor.constraint(
                equalTo: footerContainerView.trailingAnchor, constant: -Metrics.spacing4),

            continueButton.topAnchor.constraint(
                equalTo: footerNoteLabel.bottomAnchor, constant: Metrics.spacing4),
            continueButton.leadingAnchor.constraint(
                equalTo: footerContainerView.leadingAnchor, constant: Metrics.spacing4),
            continueButton.trailingAnchor.constraint(
                equalTo: footerContainerView.trailingAnchor, constant: -Metrics.spacing4),
            continueButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func setupBackButtonGlassEffect() {
        backButtonGlassContainer.applyClearGlass(cornerRadius: 18)
    }

    private func setupActions() {
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButtonGlassContainer.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(backTapped)))
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        // `Input` updates `centsValue` on its own `.editingChanged` handler, which is registered
        // first, so by the time this fires the value is already the new one.
        amountInput.textField.addTarget(
            self, action: #selector(amountChanged), for: .editingChanged)
        amountInput.addDoneButtonToolbar()
        todayOption.onTap = { [weak self] in self?.delegate?.didChangeSchedule(payToday: true) }
        scheduleOption.onTap = { [weak self] in self?.delegate?.didChangeSchedule(payToday: false) }
    }

    @objc private func backTapped() { delegate?.didTapBack() }
    @objc private func continueTapped() { delegate?.didTapContinue() }
    @objc private func amountChanged() {
        delegate?.didChangeAmount(cents: amountInput.centsValue)
    }

    // MARK: - Configuration

    func configure(with viewModel: StatementPaymentViewModel) {
        currentViewModel = viewModel
        if visibilityObservation == nil {
            visibilityObservation = ValueVisibilityStore.shared.observe { [weak self] _ in
                guard let self, let viewModel = self.currentViewModel else { return }
                // The balance row and the footer both carry amounts.
                self.refresh(with: viewModel)
            }
        }

        introLabel.text = String(
            format: "statementPayment.intro".localized, viewModel.statementLabel)

        cardRow.value.text = viewModel.cardLabel
        dueDateRow.value.text = viewModel.dueDateText

        amountInput.setCentsValue(viewModel.amount)

        // Seeded once, here: the picked date lives in the field until the user confirms, and
        // re-seeding it from `refresh` would overwrite what they chose every time they typed a digit.
        dateInput.text = DateFormatter.fullDateFormatter.string(from: viewModel.paymentDate)
        dateInput.setInitialDateFromTextField()
        dateInput.setDateRestrictions(minimumDate: viewModel.minimumPaymentDate, maximumDate: nil)

        refresh(with: viewModel)
    }

    /// Everything that changes as the user types or switches between today and scheduled.
    func refresh(with viewModel: StatementPaymentViewModel) {
        let isValueHidden = ValueMask.isActive

        balanceRow.value.attributedText = viewModel.remainingBalance
            .maskedCurrencyAttributedString(
                symbolFont: Fonts.textXS.font, font: Fonts.textSM, hidden: isValueHidden)
        balanceRow.value.accessibilityLabel = isValueHidden
            ? ValueMask.accessibilityLabel
            : viewModel.remainingBalance.currencyString

        remainingValueLabel.attributedText = viewModel.balanceAfterPayment
            .maskedCurrencyAttributedString(
                symbolFont: Fonts.textXS.font, font: Fonts.titleMD, hidden: isValueHidden)
        remainingValueLabel.accessibilityLabel = isValueHidden
            ? ValueMask.accessibilityLabel
            : viewModel.balanceAfterPayment.currencyString

        footerNoteLabel.text = viewModel.paysInFull
            ? "statementPayment.footer.paysInFull".localized
            : "statementPayment.footer.partial".localized

        amountErrorLabel.text = viewModel.amountErrorText
        amountErrorLabel.isHidden = viewModel.amountErrorText == nil
        amountInput.setError(viewModel.exceedsBalance)

        todayOption.setSelected(viewModel.payToday)
        scheduleOption.setSelected(!viewModel.payToday)
        // Hidden rather than disabled: paying today has no date to pick, and an inert field beside a
        // selected "Pay today" reads as something the user failed to fill in.
        dateRow.isHidden = viewModel.payToday

        continueButton.isEnabled = viewModel.canContinue
        continueButton.alpha = viewModel.canContinue ? 1.0 : 0.5
    }

    // MARK: - Loading

    func startLoading() { continueButton.startLoading() }
    func stopLoading() { continueButton.stopLoading() }
}
