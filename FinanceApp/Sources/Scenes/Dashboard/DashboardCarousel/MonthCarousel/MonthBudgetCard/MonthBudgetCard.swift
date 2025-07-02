//
//  MonthBudgetCard.swift
//  FinanceApp
//
//  Created by Arthur Rios on 10/05/25.
//

import Foundation
import UIKit
import SwiftUI

enum BalanceDisplayMode {
    case final     // Final balance (available value)
    case current   // Current balance (budget limit - used)
}

class MonthBudgetCard: UIView {
    weak var delegate: MonthBudgetCardDelegate?
    private var budgetDate: Date?
    
    private var displayMode: BalanceDisplayMode = .final
    private var currentMonthData: MonthBudgetCardType?
    
    private var animatedNumberHost: UIHostingController<AnimatedNumberLabel>?
    private var animatedNumberContainer: UIView?
    private var currentDisplayValue: Int = 0
    
    private let gradientLayer = Colors.gradientBlack
    
    private lazy var mainStackView = UIStackView(
        axis: .vertical,
        arrangedSubviews: [
            headerHorizontalStackView, separator, availableBudgetStackView, footerStackView
        ])
    
    private lazy var headerHorizontalStackView = UIStackView(
        axis: .horizontal, arrangedSubviews: [headerDateStackView, configIcon])
    
    private lazy var headerDateStackView = UIStackView(
        axis: .horizontal, spacing: Metrics.spacing2, alignment: .center,
        arrangedSubviews: [monthLabel, yearLabel])
    
    private lazy var availableBudgetStackView = UIStackView(
        axis: .vertical, spacing: Metrics.spacing3,
        arrangedSubviews: [availableBudgetTextLabel, availableBudgetValueWithToggleContainer, defineBudgetButton])
    
    private lazy var availableBudgetValueWithToggleContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(availableBudgetValueLabel)
        availableBudgetValueLabel.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(balanceToggleContainer)
        balanceToggleContainer.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            availableBudgetValueLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            availableBudgetValueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            balanceToggleContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            balanceToggleContainer.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            balanceToggleContainer.leadingAnchor.constraint(greaterThanOrEqualTo: availableBudgetValueLabel.trailingAnchor, constant: 8),
            
            container.heightAnchor.constraint(equalTo: balanceToggleContainer.heightAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualTo: availableBudgetValueLabel.widthAnchor)
        ])
        
        return container
    }()
    
    private lazy var footerStackView = UIStackView(
        axis: .horizontal, arrangedSubviews: [usedBudgetStackView, limitBudgetStackView])
    
    private lazy var usedBudgetStackView = UIStackView(
        axis: .vertical, spacing: Metrics.spacing2,
        arrangedSubviews: [usedBudgetTextLabel, usedBudgetValueLabel])
    
    private lazy var limitBudgetStackView = UIStackView(
        axis: .vertical, spacing: Metrics.spacing2, alignment: .trailing,
        arrangedSubviews: [limitBudgetTextLabel, limitBudgetValueLabel, infinitySymbol])
    
    private let monthLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.textColor = Colors.gray100
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()
    
    private let yearLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleXS.font
        label.textColor = Colors.gray400
        return label
    }()
    
    private let configIcon: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "settingsIcon"))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.gray100
        imageView.widthAnchor.constraint(equalToConstant: Metrics.spacing5).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: Metrics.spacing5).isActive = true
        imageView.isUserInteractionEnabled = true
        return imageView
    }()
    
    private let separator: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.opaqueWhite
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let availableBudgetTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray400
        return label 
    }()
    
    private var availableBudgetValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleLG.font
        label.textColor = Colors.gray100
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()
    
    private let balanceToggleIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "lucide_arrowRightLeft")
        imageView.tintColor = Colors.gray100
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var balanceToggleContainer: UIView = {
        let container = UIView()
        container.backgroundColor = Colors.gray600
        container.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(balanceToggleIcon)
        NSLayoutConstraint.activate([
            balanceToggleIcon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            balanceToggleIcon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            balanceToggleIcon.widthAnchor.constraint(equalToConstant: 24),
            balanceToggleIcon.heightAnchor.constraint(equalToConstant: 24),
            
            container.widthAnchor.constraint(equalToConstant: 36),
            container.heightAnchor.constraint(equalToConstant: 36)
        ])
        
        return container
    }()
    
    private let defineBudgetButton = Button(
        variant: .outlined, label: "monthCard.defineBudget".localized)
    
    private let usedBudgetTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.text = "monthCard.usedBudget".localized
        label.textColor = Colors.gray400
        return label
    }()
    
    private var usedBudgetValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray100
        return label
    }()
    
    private let limitBudgetTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.text = "monthCard.limitBudget".localized
        label.textColor = Colors.gray400
        return label
    }()
    
    private var limitBudgetValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray100
        return label
    }()
    
    private let infinitySymbol: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "infinity")
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.gray100
        return imageView
    }()
    
    private let progressBar: UIProgressView = {
        let progressBar = UIProgressView(progressViewStyle: .bar)
        progressBar.progressViewStyle = .bar
        progressBar.trackTintColor = Colors.gray600
        progressBar.progressTintColor = Colors.mainMagenta
        return progressBar
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.insertSublayer(gradientLayer, at: 0)
        layer.cornerRadius = CornerRadius.extraLarge
        layer.masksToBounds = true
        
        setupView()
        setupAnimatedNumberContainer()
        setupGestureRecognizers()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(data: MonthBudgetCardType) {
        budgetDate = data.date
        currentMonthData = data
        monthLabel.text = data.month
        monthLabel.applyStyle()
        yearLabel.text = "/ " + DateFormatter.yearFormatter.string(from: data.date)
        
        usedBudgetValueLabel.text = data.usedValue.currencyString
        
        if isCurrentMonth() {
            displayMode = UserDefaultsManager.getBalanceDisplayMode()
        } else {
            displayMode = .final
        }
        
        updateAvailableBudgetDisplay()
        updateLimitSection(with: data)
    }
    
    private func updateLimitSection(with data: MonthBudgetCardType) {
        guard let budgetLimit = data.budgetLimit, budgetLimit > 0 else {
            limitBudgetValueLabel.isHidden = true
            progressBar.isHidden = true
            infinitySymbol.isHidden = false
            defineBudgetButton.isHidden = false
            availableBudgetValueLabel.isHidden = true
            
            let isPreviousMonth = DateUtils.isPastMonth(date: data.date)
            applyButtonStyle(isPreviousMonth: isPreviousMonth)
            return
        }
        
        limitBudgetValueLabel.text = budgetLimit.currencyString
        limitBudgetValueLabel.isHidden = false
        infinitySymbol.isHidden = true
        progressBar.isHidden = false
        defineBudgetButton.isHidden = true
        
        let rawFraction = Float(data.usedValue) / Float(budgetLimit)
        let clampedFraction = min(max(rawFraction, 0), 1)
        
        let availableValue = data.finalBalance ?? (budgetLimit - data.usedValue)
        let isAlertState = data.usedValue > budgetLimit || availableValue < 0
        
        DispatchQueue.main.async {
            self.progressBar.setProgress(clampedFraction, animated: true)
            self.progressBar.progressTintColor =
            isAlertState
            ? Colors.mainRed
            : Colors.mainMagenta
        }
    }
    
    private func updateAvailableBudgetDisplay() {
        guard let data = currentMonthData else { return }
        
        let shouldShowToggleButton = data.budgetLimit != nil &&
        data.budgetLimit! > 0 &&
        isCurrentMonth()
        
        availableBudgetValueLabel.isHidden = false
        
        balanceToggleContainer.isHidden = !shouldShowToggleButton
        
        if data.budgetLimit != nil && data.budgetLimit! > 0 {
            let displayValue: Int
            let textKey: String
            
            if shouldShowToggleButton {
                switch displayMode {
                case .final:
                    displayValue = data.finalBalance ?? (data.budgetLimit! - data.usedValue)
                    textKey = "monthCard.availableBudget"
                    balanceToggleContainer.backgroundColor = Colors.gray600

                case .current:
                    displayValue = data.currentBalance ?? (data.previousBalance ?? 0)
                    textKey = "monthCard.currentBalance"
                    balanceToggleContainer.backgroundColor = Colors.mainMagenta.withAlphaComponent(0.7)
                }
                
                // Use animated SwiftUI view for current month
                animatedNumberContainer?.isHidden = false
                availableBudgetValueLabel.isHidden = true
                setupOrUpdateAnimatedNumber(value: displayValue)
                
            } else {
                // Other months - use regular UIKit label (no animation)
                displayValue = data.finalBalance ?? (data.budgetLimit! - data.usedValue)
                textKey = "monthCard.availableBudget"
                
                animatedNumberContainer?.isHidden = true
                availableBudgetValueLabel.isHidden = false
                availableBudgetValueLabel.text = displayValue.currencyString
            }
            
            availableBudgetTextLabel.text = textKey.localized
            availableBudgetValueWithToggleContainer.isHidden = false
            defineBudgetButton.isHidden = true
            
            if !availableBudgetStackView.arrangedSubviews.contains(availableBudgetValueWithToggleContainer) {
                availableBudgetStackView.insertArrangedSubview(availableBudgetValueWithToggleContainer, at: 1)
            }
            
        } else {
            // No budget - hide everything
            animatedNumberContainer?.isHidden = true
            availableBudgetValueWithToggleContainer.isHidden = true
            defineBudgetButton.isHidden = false
            
            if availableBudgetStackView.arrangedSubviews.contains(availableBudgetValueWithToggleContainer) {
                availableBudgetStackView.removeArrangedSubview(availableBudgetValueWithToggleContainer)
            }
        }
    }
    
    func refresh(with data: MonthBudgetCardType) {
        currentMonthData = data
        updateAvailableBudgetDisplay()
        updateLimitSection(with: data)
    }
    
    private func applyButtonStyle(isPreviousMonth: Bool) {
        if isPreviousMonth {
            defineBudgetButton.variant = .outlinedDisabled
        } else {
            defineBudgetButton.variant = .outlined
        }
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        
        setupMainStackView()
    }
    
    private func setupMainStackView() {
        addSubview(mainStackView)
        mainStackView.pinToSuperview(
            with: UIEdgeInsets(
                top: Metrics.spacing6, left: Metrics.spacing6, bottom: Metrics.spacing7,
                right: Metrics.spacing6))
        mainStackView.setCustomSpacing(Metrics.spacing4, after: headerHorizontalStackView)
        mainStackView.setCustomSpacing(Metrics.spacing3, after: separator)
        mainStackView.setCustomSpacing(Metrics.spacing5, after: availableBudgetStackView)
        
        setupProgressBar()
    }
    
    private func setupProgressBar() {
        addSubview(progressBar)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor)
        ])
    }
    
    private func setupGestureRecognizers() {
        let configTapGesture = UITapGestureRecognizer(
            target: self, action: #selector(handleConfigTapGesture))
        configIcon.addGestureRecognizer(configTapGesture)
        
        defineBudgetButton.addTarget(
            self, action: #selector(defineBudgetButtonTapped), for: .touchUpInside)
        
        let toggleBalanceTapGesture = UITapGestureRecognizer(target: self, action: #selector(toggleBalanceDisplay))
        balanceToggleContainer.addGestureRecognizer(toggleBalanceTapGesture)
        balanceToggleContainer.isUserInteractionEnabled = true
    }
    
    private func setupAnimatedNumberContainer() {
        animatedNumberContainer = UIView()
        animatedNumberContainer?.backgroundColor = .clear
        animatedNumberContainer?.translatesAutoresizingMaskIntoConstraints = false
        
        animatedNumberContainer?.isHidden = true
        
        guard let container = animatedNumberContainer else { return }
        availableBudgetValueWithToggleContainer.addSubview(container)
        
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: availableBudgetValueLabel.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: availableBudgetValueLabel.trailingAnchor),
            container.topAnchor.constraint(equalTo: availableBudgetValueLabel.topAnchor),
            container.bottomAnchor.constraint(equalTo: availableBudgetValueLabel.bottomAnchor)
        ])
    }
    
    private func setupOrUpdateAnimatedNumber(value: Int) {
        guard let container = animatedNumberContainer else { return }
        
        currentDisplayValue = value
        let currentFont = availableBudgetValueLabel.font ?? Fonts.titleLG.font
        let currentColor = availableBudgetValueLabel.textColor ?? Colors.gray100
        
        if animatedNumberHost == nil {
            let swiftUIView = AnimatedNumberLabel(value: value, font: currentFont, color: currentColor)
            let hostController = UIHostingController(rootView: swiftUIView)
            hostController.view.backgroundColor = .clear
            animatedNumberHost = hostController
            
            container.addSubview(hostController.view)
            hostController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostController.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hostController.view.topAnchor.constraint(equalTo: container.topAnchor),
                hostController.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        } else {
            let swiftUIView = AnimatedNumberLabel(value: value, font: currentFont, color: currentColor)
            animatedNumberHost?.rootView = swiftUIView
        }
    }
    
    private func isCurrentMonth() -> Bool {
        guard let monthDate = currentMonthData?.date else { return false }
        let utcCalendar = Calendar(identifier: .gregorian)
        var utc = utcCalendar
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        
        let today = Date()
        let month = utc.component(.month, from: monthDate)
        let year = utc.component(.year, from: monthDate)
        let todayMonth = utc.component(.month, from: today)
        let todayYear = utc.component(.year, from: today)
        let isCurrent = (month == todayMonth) && (year == todayYear)
        return isCurrent
    }
    
    @objc
    private func handleConfigTapGesture() {
        delegate?.didTapConfigButton()
    }
    
    @objc
    private func defineBudgetButtonTapped() {
        guard let budgetDate else { return }
        delegate?.didTapDefineBudgetButton(budgetDate: budgetDate)
    }
    
    @objc
    private func toggleBalanceDisplay() {
        displayMode = displayMode == .final ? .current : .final
        UserDefaultsManager.setBalanceDisplayMode(displayMode)
        updateAvailableBudgetDisplay()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        progressBar.roundRightCornersFixedHeight(Metrics.spacing2)
        balanceToggleContainer.layer.cornerRadius = balanceToggleContainer.frame.width / 2
    }
}
