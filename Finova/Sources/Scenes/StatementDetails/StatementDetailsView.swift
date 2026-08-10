//
//  StatementDetailsView.swift
//  Finova
//

import UIKit

protocol StatementDetailsViewDelegate: AnyObject {
    func didTapBack()
    func didTapPayStatement()
    func didTapMarkAsPaid()
    func didTapTransaction(_ transaction: Transaction)
    func didRequestDeleteTransaction(_ transaction: Transaction, completion: @escaping (Bool) -> Void)
}

final class StatementDetailsView: UIView {
    weak var delegate: StatementDetailsViewDelegate?

    private var transactions: [Transaction] = []
    private var earlyPaidIds: Set<Int> = []

    private var currentViewModel: StatementDetailsViewModel?
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
        label.textColor = Colors.gray700
        label.textAlignment = .left
        // A long card name truncates rather than pushing past the hide-values button.
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Scroll View
    private let scrollView: UIScrollView = {
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

    // MARK: - Summary Card
    private let summaryCard: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.layer.borderWidth = 1
        view.layer.borderColor = Colors.gray300.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let summaryStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let cardLabel = StatementDetailsView.createInfoRow(title: "statementDetails.card".localized)
    private let periodLabel = StatementDetailsView.createInfoRow(title: "statementDetails.period".localized)
    private let closingDateLabel = StatementDetailsView.createInfoRow(title: "statementDetails.closingDate".localized)
    private let dueDateLabel = StatementDetailsView.createInfoRow(title: "statementDetails.dueDate".localized)
    private let totalLabel = StatementDetailsView.createInfoRow(title: "statementDetails.total".localized)
    private let statusLabel = StatementDetailsView.createInfoRow(title: "statementDetails.status".localized)

    private let paidInfoLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.textAlignment = .center
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Transactions Section
    private lazy var transactionsHeaderView = CardHeader(
        headerTitle: "allocation.details.transactions.header".localized)

    private lazy var transactionsTableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Colors.gray100
        tableView.layer.cornerRadius = CornerRadius.extraLarge
        tableView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        tableView.layer.borderWidth = 1
        tableView.layer.borderColor = Colors.gray300.cgColor
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets.zero
        tableView.clipsToBounds = true
        tableView.separatorColor = Colors.gray300
        tableView.isScrollEnabled = true
        tableView.showsVerticalScrollIndicator = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(TransactionCell.self, forCellReuseIdentifier: TransactionCell.reuseID)
        tableView.dataSource = self
        tableView.delegate = self
        return tableView
    }()

    private var transactionsTableHeightConstraint: NSLayoutConstraint?
    private let maxTransactionsTableHeight: CGFloat = 300

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
            arrangedSubviews: [payStatementButton, markAsPaidButton]
        )
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing4, leading: Metrics.spacing4, bottom: Metrics.spacing4,
            trailing: Metrics.spacing4)
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }()

    /// The primary action: it records a real payment — a debit for the money and a credit against the
    /// invoice. `markAsPaidButton` below only flips a flag and moves nothing, so it is demoted to the
    /// outlined variant rather than removed; users who reconcile elsewhere still want it.
    let payStatementButton = Button(
        variant: .base, label: "statementDetails.button.payStatement".localized)

    let markAsPaidButton = Button(variant: .outlined, label: "statementDetails.button.markAsPaid".localized)

    override init(frame: CGRect) {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = Colors.gray200

        // Header - fixed at top
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        setupBackButtonGlassEffect()
        headerItemsView.addSubview(hideValuesButton)
        headerItemsView.addSubview(headerTitleLabel)

        // Scroll view - between header and footer
        addSubview(scrollView)
        scrollView.addSubview(scrollContentView)

        // Summary card
        scrollContentView.addSubview(summaryCard)
        summaryCard.addSubview(summaryStackView)
        summaryStackView.addArrangedSubview(cardLabel.container)
        summaryStackView.addArrangedSubview(periodLabel.container)
        summaryStackView.addArrangedSubview(closingDateLabel.container)
        summaryStackView.addArrangedSubview(dueDateLabel.container)
        summaryStackView.addArrangedSubview(totalLabel.container)
        summaryStackView.addArrangedSubview(statusLabel.container)

        scrollContentView.addSubview(paidInfoLabel)

        // Transactions section
        scrollContentView.addSubview(transactionsHeaderView)
        scrollContentView.addSubview(transactionsTableView)

        // Footer - fixed at bottom
        addSubview(actionButtonsContainerView)
        actionButtonsContainerView.addSubview(footerBorderView)
        actionButtonsContainerView.addSubview(actionButtonsStackView)

        setupConstraints()
        setupActions()
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

            hideValuesButton.trailingAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.trailingAnchor),
            // Centred on the back button, not on headerItemsView: this header is 12pt shorter than
            // the others, so centring on the container would leave the two buttons misaligned.
            hideValuesButton.centerYAnchor.constraint(
                equalTo: backButtonGlassContainer.centerYAnchor),

            headerTitleLabel.leadingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
            headerTitleLabel.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),
            // This label had no trailing constraint at all, so it sized to its intrinsic content -
            // and its text interpolates a user-entered card name, which will overrun a right-side
            // button.
            headerTitleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: hideValuesButton.leadingAnchor, constant: -Metrics.spacing3),

            // Scroll view - between header and footer
            scrollView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionButtonsContainerView.topAnchor),

            // Content view inside scroll view
            scrollContentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            scrollContentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            scrollContentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            scrollContentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            scrollContentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Summary card
            summaryCard.topAnchor.constraint(equalTo: scrollContentView.topAnchor, constant: Metrics.spacing4),
            summaryCard.leadingAnchor.constraint(equalTo: scrollContentView.leadingAnchor, constant: Metrics.spacing4),
            summaryCard.trailingAnchor.constraint(equalTo: scrollContentView.trailingAnchor, constant: -Metrics.spacing4),

            summaryStackView.topAnchor.constraint(equalTo: summaryCard.topAnchor, constant: Metrics.spacing4),
            summaryStackView.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: Metrics.spacing4),
            summaryStackView.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -Metrics.spacing4),
            summaryStackView.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: -Metrics.spacing4),

            // Paid info label
            paidInfoLabel.topAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: Metrics.spacing3),
            paidInfoLabel.leadingAnchor.constraint(equalTo: scrollContentView.leadingAnchor, constant: Metrics.spacing4),
            paidInfoLabel.trailingAnchor.constraint(equalTo: scrollContentView.trailingAnchor, constant: -Metrics.spacing4),

            // Transactions section
            transactionsHeaderView.topAnchor.constraint(equalTo: paidInfoLabel.bottomAnchor, constant: Metrics.spacing4),
            transactionsHeaderView.leadingAnchor.constraint(equalTo: scrollContentView.leadingAnchor, constant: Metrics.spacing4),
            transactionsHeaderView.trailingAnchor.constraint(equalTo: scrollContentView.trailingAnchor, constant: -Metrics.spacing4),

            transactionsTableView.topAnchor.constraint(equalTo: transactionsHeaderView.bottomAnchor),
            transactionsTableView.leadingAnchor.constraint(equalTo: transactionsHeaderView.leadingAnchor),
            transactionsTableView.trailingAnchor.constraint(equalTo: transactionsHeaderView.trailingAnchor),
            transactionsTableView.bottomAnchor.constraint(equalTo: scrollContentView.bottomAnchor, constant: -Metrics.spacing4),

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

        // Dynamic table height
        transactionsTableHeightConstraint = transactionsTableView.heightAnchor.constraint(equalToConstant: 0)
        transactionsTableHeightConstraint?.isActive = true
    }

    private func setupBackButtonGlassEffect() {
        backButtonGlassContainer.applyClearGlass(cornerRadius: 18)
    }

    private func setupActions() {
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        let backTap = UITapGestureRecognizer(target: self, action: #selector(backTapped))
        backButtonGlassContainer.addGestureRecognizer(backTap)
        markAsPaidButton.addTarget(self, action: #selector(markAsPaidTapped), for: .touchUpInside)
        payStatementButton.addTarget(self, action: #selector(payStatementTapped), for: .touchUpInside)
    }

    @objc private func backTapped() { delegate?.didTapBack() }
    @objc private func markAsPaidTapped() { delegate?.didTapMarkAsPaid() }
    @objc private func payStatementTapped() { delegate?.didTapPayStatement() }

    // MARK: - Configuration
    func configure(with viewModel: StatementDetailsViewModel) {
        currentViewModel = viewModel
        if visibilityObservation == nil {
            visibilityObservation = ValueVisibilityStore.shared.observe { [weak self] _ in
                guard let self, let viewModel = self.currentViewModel else { return }
                self.configure(with: viewModel)
            }
        }

        headerTitleLabel.text = String(format: "statementDetails.header.title".localized, viewModel.card.name)
        headerTitleLabel.applyStyle()

        cardLabel.valueLabel.text = "\(viewModel.card.name) ****\(viewModel.card.lastFourDigits)"
        periodLabel.valueLabel.text = viewModel.periodText
        closingDateLabel.valueLabel.text = viewModel.closingDateText
        dueDateLabel.valueLabel.text = viewModel.dueDateText
        totalLabel.valueLabel.attributedText = viewModel.statementTotal
            .maskedCurrencyAttributedString(
                symbolFont: Fonts.textXS.font, font: Fonts.titleMD)

        statusLabel.valueLabel.text = viewModel.statusText
        statusLabel.valueLabel.textColor = viewModel.statusColor

        // Footer visibility
        markAsPaidButton.isHidden = viewModel.isPaid
        // Nothing to pay on an invoice whose charges are already fully offset by credits. It can
        // happen without the paid flag — a refund covering the whole balance — and offering to pay
        // zero would just fail the amount check.
        payStatementButton.isHidden = viewModel.statementTotal <= 0
        actionButtonsContainerView.isHidden = viewModel.isPaid

        if let paidText = viewModel.paidDateText {
            paidInfoLabel.text = paidText
            paidInfoLabel.isHidden = false
        } else {
            paidInfoLabel.isHidden = true
        }

        // Transactions
        transactions = viewModel.transactions
        earlyPaidIds = viewModel.earlyPaidIds

        transactionsHeaderView.configure(
            headerTitle: "allocation.details.transactions.header".localized,
            itemsQuantity: "\(transactions.count)"
        )

        if transactions.isEmpty {
            transactionsTableView.isHidden = true
            transactionsTableHeightConstraint?.constant = 0
        } else {
            transactionsTableView.isHidden = false

            let cellHeight: CGFloat = 67
            let separatorHeight = CGFloat(max(0, transactions.count - 1)) * 1.0
            let contentHeight = CGFloat(transactions.count) * cellHeight + separatorHeight
            let finalHeight = min(contentHeight, maxTransactionsTableHeight)
            transactionsTableHeightConstraint?.constant = finalHeight

            transactionsTableView.isScrollEnabled = contentHeight > maxTransactionsTableHeight

            transactionsTableView.reloadData()
        }
    }

    // MARK: - Info Row Helper
    private static func createInfoRow(title: String) -> (container: UIView, valueLabel: UILabel) {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = Fonts.textSM.font
        titleLabel.textColor = Colors.gray500
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.font = Fonts.textSMBold.font
        valueLabel.textColor = Colors.gray700
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: Metrics.spacing3),
        ])

        return (container, valueLabel)
    }

}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension StatementDetailsView: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return transactions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: TransactionCell.reuseID, for: indexPath) as! TransactionCell

        let transaction = transactions[indexPath.row]

        let configuration = TransactionCellConfiguration(
            category: transaction.category,
            title: transaction.title,
            date: transaction.date,
            value: transaction.amount,
            transactionType: transaction.type,
            transactionMode: transaction.mode,
            installmentNumber: transaction.installmentNumber,
            totalInstallments: transaction.totalInstallments,
            isCreditCardStatement: false,
            statementTransactionCount: nil,
            creditCardId: transaction.creditCardId,
            // An installment paid ahead of schedule stays listed so the statement's history reads
            // correctly, but it is dimmed to show it is no longer part of what this invoice charges.
            isSettledEarly: transaction.id.map(earlyPaidIds.contains) ?? false
        )

        cell.configure(with: configuration)

        cell.onDelete = { [weak self] completion in
            self?.delegate?.didRequestDeleteTransaction(transaction, completion: completion)
        }

        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 67
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let transaction = transactions[indexPath.row]
        delegate?.didTapTransaction(transaction)
    }
}
