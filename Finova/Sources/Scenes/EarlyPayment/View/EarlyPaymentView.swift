//
//  EarlyPaymentView.swift
//  Finova
//

import UIKit

protocol EarlyPaymentViewDelegate: AnyObject {
    func didTapBack()
    func didToggleInstallment(id: Int)
    func didToggleSelectAll()
    func didChangeDestination(chargeToOpenStatement: Bool)
    func didTapContinue()
}

final class EarlyPaymentView: UIView {
    weak var delegate: EarlyPaymentViewDelegate?

    /// Rows are rebuilt only when the set of installments changes; a selection change just restyles
    /// the existing row, so tapping a checkbox never rebuilds the list under the user's finger.
    private var rowsById: [Int: EarlyPaymentInstallmentRow] = [:]

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
        label.text = "earlyPayment.header.title".localized
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
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Everything inside the scroll view, as one stack.
    ///
    /// The sections here are conditional (there may be no installments left, and a series with no
    /// card has no destination choice). Outside a stack view, `isHidden` leaves a view's height in
    /// the layout, so hiding a section would leave a gap where it used to be; arranged subviews
    /// collapse properly.
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

    private lazy var installmentsSection = Self.section(
        [installmentsHeaderView, installmentsCard])
    private lazy var paymentSection = Self.section([paymentHeaderView, paymentCard])

    private let introLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Installments

    private lazy var installmentsHeaderView = CardHeader(
        headerTitle: "earlyPayment.installments.header".localized)

    private lazy var installmentsCard: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.backgroundColor = Colors.gray100
        stack.layer.borderWidth = 1
        stack.layer.borderColor = Colors.gray300.cgColor
        stack.layer.cornerRadius = CornerRadius.extraLarge
        stack.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        stack.clipsToBounds = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var selectAllRow: EarlyPaymentInstallmentRow = {
        let row = EarlyPaymentInstallmentRow()
        row.onTap = { [weak self] in self?.delegate?.didToggleSelectAll() }
        return row
    }()

    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.text = "earlyPayment.empty".localized
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Payment settings

    private lazy var paymentHeaderView = CardHeader(
        headerTitle: "earlyPayment.payment.header".localized)

    private lazy var paymentCard: UIStackView = {
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
    }()

    private let dateFieldLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray600
        label.text = "earlyPayment.date.label".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let dateInput = Input(
        type: .date(style: .fullDate),
        placeholder: "00/00/0000",
        icon: UIImage(named: "calendar")
    )

    private let destinationLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray600
        label.text = "earlyPayment.destination.label".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var openStatementOption = PaymentMethodOptionView(
        title: "earlyPayment.destination.openStatement".localized, subtitle: "")

    private lazy var standaloneOption = PaymentMethodOptionView(
        title: "earlyPayment.destination.standalone".localized,
        subtitle: "earlyPayment.destination.standalone.subtitle".localized)

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

    private let totalTitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray600
        label.text = "earlyPayment.footer.total".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let totalValueLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let selectedCountLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    lazy var continueButton = Button(
        variant: .base, label: "earlyPayment.button.continue".localized)

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = Colors.gray200

        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        setupBackButtonGlassEffect()
        headerItemsView.addSubview(headerTitleLabel)

        addSubview(scrollView)
        scrollView.addSubview(scrollContentView)

        scrollContentView.addArrangedSubview(introLabel)
        scrollContentView.addArrangedSubview(installmentsSection)
        scrollContentView.addArrangedSubview(emptyStateLabel)
        scrollContentView.addArrangedSubview(paymentSection)

        paymentCard.addArrangedSubview(labelledRow(dateFieldLabel, control: dateInput))
        paymentCard.addArrangedSubview(destinationLabel)
        paymentCard.addArrangedSubview(openStatementOption)
        paymentCard.addArrangedSubview(standaloneOption)

        addSubview(footerContainerView)
        footerContainerView.addSubview(footerBorderView)
        footerContainerView.addSubview(totalTitleLabel)
        footerContainerView.addSubview(totalValueLabel)
        footerContainerView.addSubview(selectedCountLabel)
        footerContainerView.addSubview(continueButton)

        setupConstraints()
        setupActions()
    }

    /// A label stacked above its control, so the date field keeps the same height as everywhere else.
    private func labelledRow(_ label: UILabel, control: UIView) -> UIView {
        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .vertical
        stack.spacing = Metrics.spacing2
        stack.translatesAutoresizingMaskIntoConstraints = false
        control.heightAnchor.constraint(equalToConstant: Metrics.inputHeight).isActive = true
        return stack
    }

    private func setupConstraints() {
        totalValueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

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

            headerTitleLabel.leadingAnchor.constraint(
                equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
            headerTitleLabel.trailingAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.trailingAnchor),
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

            totalTitleLabel.topAnchor.constraint(
                equalTo: footerBorderView.bottomAnchor, constant: Metrics.spacing4),
            totalTitleLabel.leadingAnchor.constraint(
                equalTo: footerContainerView.leadingAnchor, constant: Metrics.spacing4),

            totalValueLabel.centerYAnchor.constraint(equalTo: totalTitleLabel.centerYAnchor),
            totalValueLabel.trailingAnchor.constraint(
                equalTo: footerContainerView.trailingAnchor, constant: -Metrics.spacing4),
            totalValueLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: totalTitleLabel.trailingAnchor, constant: Metrics.spacing3),

            selectedCountLabel.topAnchor.constraint(
                equalTo: totalTitleLabel.bottomAnchor, constant: Metrics.spacing1),
            selectedCountLabel.leadingAnchor.constraint(equalTo: totalTitleLabel.leadingAnchor),

            continueButton.topAnchor.constraint(
                equalTo: selectedCountLabel.bottomAnchor, constant: Metrics.spacing4),
            continueButton.leadingAnchor.constraint(
                equalTo: footerContainerView.leadingAnchor, constant: Metrics.spacing4),
            continueButton.trailingAnchor.constraint(
                equalTo: footerContainerView.trailingAnchor, constant: -Metrics.spacing4),
            continueButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
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
        backButtonGlassContainer.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(backTapped)))
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        openStatementOption.onTap = { [weak self] in
            self?.delegate?.didChangeDestination(chargeToOpenStatement: true)
        }
        standaloneOption.onTap = { [weak self] in
            self?.delegate?.didChangeDestination(chargeToOpenStatement: false)
        }
    }

    @objc private func backTapped() { delegate?.didTapBack() }
    @objc private func continueTapped() { delegate?.didTapContinue() }

    // MARK: - Configuration

    func configure(with viewModel: EarlyPaymentViewModel) {
        introLabel.text = String(
            format: "earlyPayment.intro".localized, viewModel.seriesTitle)

        rebuildRowsIfNeeded(with: viewModel)
        refreshSelection(with: viewModel)

        emptyStateLabel.isHidden = viewModel.hasInstallments
        installmentsSection.isHidden = !viewModel.hasInstallments
        installmentsHeaderView.configure(
            headerTitle: "earlyPayment.installments.header".localized,
            itemsQuantity: "\(viewModel.rows.count)"
        )

        refreshDestination(with: viewModel)

        // Seeding the date field belongs to first configuration only — see `refreshDestination`.
        dateInput.text = DateFormatter.fullDateFormatter.string(from: viewModel.paymentDate)
        dateInput.setInitialDateFromTextField()
        dateInput.setDateRestrictions(minimumDate: viewModel.minimumPaymentDate, maximumDate: nil)
    }

    /// Restyles the destination radios only.
    ///
    /// Kept separate from `configure` so switching destination does not re-seed the date field: the
    /// picked date lives in the field until the user confirms, and re-running `configure` would
    /// overwrite it with the view model's untouched default.
    func refreshDestination(with viewModel: EarlyPaymentViewModel) {
        // No card means no open statement to charge to, so the whole choice is meaningless.
        let showsDestination = viewModel.card != nil
        destinationLabel.isHidden = !showsDestination
        openStatementOption.isHidden = !showsDestination
        standaloneOption.isHidden = !showsDestination

        if let card = viewModel.card {
            openStatementOption.setSubtitle("\(card.name) ****\(card.lastFourDigits)")
        }
        openStatementOption.setSelected(viewModel.chargeToOpenStatement)
        standaloneOption.setSelected(!viewModel.chargeToOpenStatement)
    }

    /// Refreshes only what a selection change affects: the checkboxes, the footer and the button.
    func refreshSelection(with viewModel: EarlyPaymentViewModel) {
        for row in viewModel.rows {
            rowsById[row.id]?.setSelected(row.isSelected)
        }

        selectAllRow.configure(
            title: "earlyPayment.selectAll".localized,
            amount: nil,
            isSelected: viewModel.allSelected
        )

        totalValueLabel.attributedText = viewModel.selectedTotal.currencyAttributedString(
            symbolFont: Fonts.textXS.font, font: Fonts.titleMD)
        totalValueLabel.accessibilityLabel = viewModel.selectedTotal.currencyString

        selectedCountLabel.text = String(
            format: viewModel.selectedCount == 1
                ? "earlyPayment.footer.count.singular".localized
                : "earlyPayment.footer.count.plural".localized,
            viewModel.selectedCount)

        continueButton.isEnabled = viewModel.canContinue
        continueButton.alpha = viewModel.canContinue ? 1.0 : 0.5
    }

    private func rebuildRowsIfNeeded(with viewModel: EarlyPaymentViewModel) {
        let ids = viewModel.rows.map { $0.id }
        guard Set(ids) != Set(rowsById.keys) || installmentsCard.arrangedSubviews.isEmpty else { return }

        installmentsCard.arrangedSubviews.forEach {
            installmentsCard.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        rowsById.removeAll()

        guard viewModel.hasInstallments else { return }

        installmentsCard.addArrangedSubview(selectAllRow)
        installmentsCard.addArrangedSubview(separator())

        for (index, row) in viewModel.rows.enumerated() {
            let rowView = EarlyPaymentInstallmentRow()
            let id = row.id
            rowView.onTap = { [weak self] in self?.delegate?.didToggleInstallment(id: id) }
            rowView.configure(title: row.title, amount: row.amount, isSelected: row.isSelected)
            rowsById[id] = rowView
            installmentsCard.addArrangedSubview(rowView)
            if index < viewModel.rows.count - 1 {
                installmentsCard.addArrangedSubview(separator())
            }
        }
    }

    private func separator() -> UIView {
        let view = UIView()
        view.backgroundColor = Colors.gray300
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    // MARK: - Loading

    func startLoading() { continueButton.startLoading() }
    func stopLoading() { continueButton.stopLoading() }
}
