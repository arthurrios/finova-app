//
//  MonthBudgetCard.swift
//  FinanceApp
//
//  Created by Arthur Rios on 10/05/25.
//

import Foundation
import SwiftUI
import UIKit

enum BalanceDisplayMode: Equatable {
    case final  // Final balance (available value)
    case current  // Current balance (budget limit - used)
    case daySpecific(day: Int)  // Balance for a specific day
}

class MonthBudgetCard: UIView {
    weak var delegate: MonthBudgetCardDelegate?
    weak var flipDelegate: MonthCardFlipDelegate?
    private var budgetDate: Date?
    
    private var displayMode: BalanceDisplayMode = .final
    private var currentMonthData: MonthBudgetCardType?
    private var isValuesHidden: Bool = false
    private var isShowingBudgetView = false
    
    private var animatedNumberHost: UIHostingController<AnimatedNumberLabel>?
    private var animatedNumberContainer: UIView?
    private var currentDisplayValue: Int = 0
    
    // Day slider properties
    private var daySlider: DaySlider?
    private var isDaySliderVisible: Bool = false
    private var currentSelectedDay: Int = 1
    private var lastUpdateTime: TimeInterval = 0
    private var hideValuesTapGesture: UITapGestureRecognizer?
    private var headerToggleTapGesture: UITapGestureRecognizer?
    private var headerToggleIcon: UIImageView?
    
    // Filter state properties
    private var isFilterActive: Bool = false
    private var filteredSum: Int = 0
    
    private let gradientLayer = Colors.gradientBlack
    
    // MARK: - Computed Properties
    
    var currentMonth: String {
        currentMonthData?.month ?? ""
    }
    
    var currentYear: String {
        guard let date = currentMonthData?.date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }
    
    private lazy var mainStackView = UIStackView(
        axis: .vertical,
        arrangedSubviews: [
            headerHorizontalStackView, separator, availableBudgetStackView, footerStackView,
        ])
    
    private lazy var headerHorizontalStackView = UIStackView(
        axis: .horizontal,
        alignment: .center,
        arrangedSubviews: [headerDateStackView, headerToggleContainer, budgetViewToggleButton, configIcon])
    
    private lazy var headerDateStackView = UIStackView(
        axis: .horizontal, spacing: Metrics.spacing2, alignment: .center,
        arrangedSubviews: [monthLabel, yearLabel])
    
    private lazy var availableBudgetStackView = UIStackView(
        axis: .vertical, spacing: Metrics.spacing3,
        arrangedSubviews: [
            availableBudgetTextLabelContainer, availableBudgetValueWithToggleContainer, defineBudgetButton,
        ])
    
    private lazy var availableBudgetTextLabelContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(availableBudgetTextLabel)
        availableBudgetTextLabel.translatesAutoresizingMaskIntoConstraints = false
        
        filteredIndicatorContainer.addArrangedSubview(filteredIndicatorBadge)
        filteredIndicatorContainer.addArrangedSubview(filteredTextLabel)
        container.addSubview(filteredIndicatorContainer)
        
        NSLayoutConstraint.activate([
            availableBudgetTextLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            availableBudgetTextLabel.topAnchor.constraint(equalTo: container.topAnchor),
            availableBudgetTextLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            availableBudgetTextLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            
            filteredIndicatorContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            filteredIndicatorContainer.topAnchor.constraint(equalTo: container.topAnchor),
            filteredIndicatorContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            filteredIndicatorContainer.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ])
        
        return container
    }()
    
    private lazy var availableBudgetValueWithToggleContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(availableBudgetValueLabel)
        availableBudgetValueLabel.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(hideValuesToggleContainer)
        hideValuesToggleContainer.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            availableBudgetValueLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            availableBudgetValueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            hideValuesToggleContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hideValuesToggleContainer.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            hideValuesToggleContainer.leadingAnchor.constraint(
                greaterThanOrEqualTo: availableBudgetValueLabel.trailingAnchor, constant: 8),
            
            container.heightAnchor.constraint(equalTo: hideValuesToggleContainer.heightAnchor),
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
    
    private let hideValuesIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.gray100
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private lazy var hideValuesToggleContainer: UIView = {
        let container = UIView()
        container.backgroundColor = .clear
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = true
        
        container.addSubview(hideValuesIcon)
        NSLayoutConstraint.activate([
            hideValuesIcon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            hideValuesIcon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            hideValuesIcon.widthAnchor.constraint(equalToConstant: 24),
            hideValuesIcon.heightAnchor.constraint(equalToConstant: 24),
            
            container.widthAnchor.constraint(equalToConstant: 36),
            container.heightAnchor.constraint(equalToConstant: 36),
        ])
        
        return container
    }()
    
    private lazy var headerToggleContainer: UIView = {
        let container = UIView()
        container.backgroundColor = .clear
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = true
        container.isHidden = true
        
        let headerIcon = UIImageView()
        headerIcon.contentMode = .scaleAspectFit
        headerIcon.tintColor = Colors.gray100
        headerIcon.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(headerIcon)
        NSLayoutConstraint.activate([
            headerIcon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            headerIcon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            headerIcon.widthAnchor.constraint(equalToConstant: 24),
            headerIcon.heightAnchor.constraint(equalToConstant: 24),
            
            container.widthAnchor.constraint(equalToConstant: 36),
            container.heightAnchor.constraint(equalToConstant: 36),
        ])
        
        // Store reference to the icon for updating
        headerToggleIcon = headerIcon
        
        return container
    }()
    
    private lazy var budgetViewToggleButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        button.setImage(UIImage(systemName: "chart.pie.fill", withConfiguration: config), for: .normal)
        button.tintColor = Colors.gray100
        button.addTarget(self, action: #selector(toggleBudgetView), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let configIcon: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "settingsIcon"))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.gray100
        imageView.widthAnchor.constraint(equalToConstant: Metrics.spacing6).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: Metrics.spacing6).isActive = true
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
        label.numberOfLines = 1
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()
    
    private lazy var filteredIndicatorContainer: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Metrics.spacing2
        stackView.alignment = .center
        stackView.isHidden = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let filteredIndicatorBadge: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.mainMagenta
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let iconImageView = UIImageView()
        iconImageView.image = UIImage(named: "filter")?.withRenderingMode(.alwaysTemplate)
        iconImageView.tintColor = Colors.gray100
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(iconImageView)
        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 12),
            iconImageView.heightAnchor.constraint(equalToConstant: 12),
            view.widthAnchor.constraint(equalToConstant: 20),
            view.heightAnchor.constraint(equalToConstant: 20),
        ])
        
        return view
    }()
    
    private let filteredTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.mainMagenta
        label.text = "filter.result.label".localized
        label.numberOfLines = 1
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()
    
    private var availableBudgetValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleLG.font
        label.textColor = Colors.gray100
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()
    
    // MARK: - Commented out balance toggle button
    /*
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
     
     // Aplicar cornerRadius desde o início
     container.layer.cornerRadius = 18
     container.layer.masksToBounds = true
     
     container.addSubview(balanceToggleIcon)
     NSLayoutConstraint.activate([
     balanceToggleIcon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
     balanceToggleIcon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
     balanceToggleIcon.widthAnchor.constraint(equalToConstant: 24),
     balanceToggleIcon.heightAnchor.constraint(equalToConstant: 24),
     
     container.widthAnchor.constraint(equalToConstant: 36),
     container.heightAnchor.constraint(equalToConstant: 36),
     ])
     
     return container
     }()
     */
    
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
    
    private let progressBar: RoundedProgressBar = {
        let progressBar = RoundedProgressBar()
        progressBar.trackTintColor = Colors.gray600
        progressBar.progressTintColor = Colors.mainMagenta
        progressBar.cornerRadius = 4.0
        return progressBar
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.insertSublayer(gradientLayer, at: 0)
        layer.cornerRadius = CornerRadius.extraLarge
        layer.masksToBounds = true
        
        setupView()
        setupAnimatedNumberContainer()
        setupDaySlider()
        setupGestureRecognizers()
        setupNotificationObserver()
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
        
        // Initialize hide values state
        isValuesHidden = UserDefaultsManager.getHideValues()
        updateTogglePositioning(with: data)
        updateHideValuesIcon()
        
        usedBudgetValueLabel.text =
        isValuesHidden ? getHiddenValueString() : data.usedValue.currencyString
        
        // Setup day slider only if budget is set
        if data.budgetLimit != nil && data.budgetLimit! > 0 {
            setupDaySliderForMonth(data: data)
        } else {
            hideDaySlider()
        }
        
        // Calculate the correct day for this month (same logic as refresh)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let today = Date()
        let monthDate = data.date
        
        let totalDaysInMonth: Int
        if let range = calendar.range(of: .day, in: .month, for: monthDate) {
            totalDaysInMonth = range.count
        } else {
            totalDaysInMonth = 31
        }
        
        let isCurrent = isCurrentMonth()
        let correctDay: Int
        if isCurrent {
            correctDay = calendar.component(.day, from: today)
        } else {
            correctDay = totalDaysInMonth
        }
        
        currentSelectedDay = correctDay
        
        // Set display mode based on month type and day slider state
        // Use isDaySliderVisible directly - don't wait for hasDayIndicators() since
        // indicators are created during layout which happens after configure()
        if isCurrentMonth() {
            if isDaySliderVisible {
                displayMode = .daySpecific(day: correctDay)
            } else {
                displayMode = UserDefaultsManager.getBalanceDisplayMode()
            }
        } else {
            if isDaySliderVisible {
                displayMode = .daySpecific(day: correctDay)
            } else {
                displayMode = .final
            }
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
        
        limitBudgetValueLabel.text =
        isValuesHidden ? getHiddenValueString() : budgetLimit.currencyString
        limitBudgetValueLabel.isHidden = false
        infinitySymbol.isHidden = true
        progressBar.isHidden = false
        defineBudgetButton.isHidden = true
        
        let rawFraction = Float(data.usedValue) / Float(budgetLimit)
        let clampedFraction = min(max(rawFraction, 0), 1)

        DispatchQueue.main.async {
            self.progressBar.setProgress(clampedFraction, animated: true)

            // Status-based colors: magenta (under), amber (near), red (over)
            if rawFraction > 1.0 {
                self.progressBar.progressTintColor = Colors.mainRed
            } else if rawFraction >= 0.75 {
                self.progressBar.progressTintColor = Colors.warningAmber
            } else {
                self.progressBar.progressTintColor = Colors.mainMagenta
            }
        }
    }
    
    private func updateAvailableBudgetDisplay() {
        logDebug("updateAvailableBudgetDisplay called with displayMode = \(displayMode)")
        guard let data = currentMonthData else { return }
        
        if data.budgetLimit != nil && data.budgetLimit! > 0 {
            // Budget is set - show budget information
            availableBudgetValueLabel.isHidden = false
            availableBudgetValueWithToggleContainer.isHidden = false
            availableBudgetTextLabelContainer.isHidden = false
            availableBudgetTextLabel.isHidden = false
            defineBudgetButton.isHidden = true

            let displayValue: Int
            let textKey: String

            switch displayMode {
            case .final:
                displayValue = data.finalBalance ?? (data.budgetLimit! - data.usedValue)
                // Use day-specific format for final balance (last day of month)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone.current
                let lastDay = calendar.range(of: .day, in: .month, for: data.date)?.upperBound ?? 31
                textKey = formatBalanceOnDayString(for: lastDay)

            case .current:
                displayValue = data.currentBalance ?? (data.previousBalance ?? 0)
                // Use day-specific format instead of old text key
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone.current
                let today = calendar.component(.day, from: Date())
                textKey = formatBalanceOnDayString(for: today)

            case .daySpecific(let day):
                displayValue = calculateBalanceForDay(day)
                textKey = formatBalanceOnDayString(for: day)
            }

            // Use animated SwiftUI view for all months
            if isValuesHidden {
                animatedNumberContainer?.isHidden = true
                availableBudgetValueLabel.isHidden = false
                availableBudgetValueLabel.text = getHiddenValueString()
            } else {
                animatedNumberContainer?.isHidden = false
                availableBudgetValueLabel.isHidden = true
                setupOrUpdateAnimatedNumber(value: displayValue)
            }

            availableBudgetTextLabel.text = textKey.localized
        } else {
            // No budget defined - hide budget information and show define button
            availableBudgetValueLabel.isHidden = true
            availableBudgetValueWithToggleContainer.isHidden = true
            availableBudgetTextLabelContainer.isHidden = true
            animatedNumberContainer?.isHidden = true
            defineBudgetButton.isHidden = false
        }
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
        mainStackView.setCustomSpacing(Metrics.spacing2, after: availableBudgetStackView)

        // Add spacing between header icons
        headerHorizontalStackView.setCustomSpacing(Metrics.spacing2, after: headerToggleContainer)
        headerHorizontalStackView.setCustomSpacing(Metrics.spacing3, after: budgetViewToggleButton)
        
        // Set high priority to prevent compression of the main stack view
        mainStackView.setContentHuggingPriority(.required, for: .vertical)
        mainStackView.setContentCompressionResistancePriority(.required, for: .vertical)
        
        setupProgressBar()
    }
    
    private func setupProgressBar() {
        addSubview(progressBar)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 8.0),  // Ensure visible height
        ])
    }
    
    private func setupGestureRecognizers() {
        let configTapGesture = UITapGestureRecognizer(
            target: self, action: #selector(handleConfigTapGesture))
        configIcon.addGestureRecognizer(configTapGesture)
        
        defineBudgetButton.addTarget(
            self, action: #selector(defineBudgetButtonTapped), for: .touchUpInside)
        
        // MARK: - Commented out balance toggle gesture recognizer
        /*
         let toggleBalanceTapGesture = UITapGestureRecognizer(
         target: self, action: #selector(toggleBalanceDisplay))
         balanceToggleContainer.addGestureRecognizer(toggleBalanceTapGesture)
         balanceToggleContainer.isUserInteractionEnabled = true
         */
        
        hideValuesTapGesture = UITapGestureRecognizer(
            target: self, action: #selector(toggleHideValues))
        hideValuesToggleContainer.addGestureRecognizer(hideValuesTapGesture!)
        
        headerToggleTapGesture = UITapGestureRecognizer(
            target: self, action: #selector(toggleHideValues))
        headerToggleContainer.addGestureRecognizer(headerToggleTapGesture!)

        let longPressGesture = UILongPressGestureRecognizer(
            target: self, action: #selector(handleBalanceLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        availableBudgetValueWithToggleContainer.addGestureRecognizer(longPressGesture)
    }
    
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBalanceVisibilityChanged),
            name: NSNotification.Name("BalanceVisibilityChanged"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCurrencyDidChange),
            name: .currencyDidChange,
            object: nil
        )
    }

    @objc private func handleBalanceVisibilityChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let isHidden = userInfo["isHidden"] as? Bool
        else { return }

        // Only update if the visibility state is different from current state
        if isHidden != isValuesHidden {
            updateBalanceVisibility(isHidden)
        }
    }

    @objc private func handleCurrencyDidChange() {
        // Force refresh the animated number label with the new currency format
        // by recreating the SwiftUI view
        logDebug("MonthBudgetCard received currencyDidChange, isValuesHidden: \(isValuesHidden), host exists: \(animatedNumberHost != nil)")
        guard !isValuesHidden, let host = animatedNumberHost else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let currentFont = self.availableBudgetValueLabel.font ?? Fonts.titleLG.font
            let currentColor = self.availableBudgetValueLabel.textColor ?? Colors.gray100
            logDebug("MonthBudgetCard updating with currencyCode: \(AppConfig.currencyCode)")
            host.rootView = AnimatedNumberLabel(
                value: self.currentDisplayValue,
                font: currentFont,
                color: currentColor,
                currencyCode: AppConfig.currencyCode
            )
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupAnimatedNumberContainer() {
        animatedNumberContainer = UIView()
        animatedNumberContainer?.backgroundColor = .clear
        animatedNumberContainer?.translatesAutoresizingMaskIntoConstraints = false
        animatedNumberContainer?.setContentHuggingPriority(.required, for: .horizontal)
        animatedNumberContainer?.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        animatedNumberContainer?.isHidden = true
        
        guard let container = animatedNumberContainer else { return }
        availableBudgetValueWithToggleContainer.addSubview(container)
        
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(
                equalTo: availableBudgetValueLabel.leadingAnchor),
            container.centerYAnchor.constraint(
                equalTo: availableBudgetValueWithToggleContainer.centerYAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])
        
        // Ensure toggle is initially in the budget value container
        if !availableBudgetValueWithToggleContainer.subviews.contains(hideValuesToggleContainer) {
            availableBudgetValueWithToggleContainer.addSubview(hideValuesToggleContainer)
            setupToggleConstraintsInBudgetContainer()
        }
        
        // Ensure gesture recognizer is set up initially
        ensureToggleGestureRecognizer()
        
        // Initialize header toggle icon
        let iconName = isValuesHidden ? "eye" : "eye-closed"
        headerToggleIcon?.image = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate)
    }
    
    private func setupDaySlider() {
        daySlider = DaySlider()
        daySlider?.delegate = self
        daySlider?.translatesAutoresizingMaskIntoConstraints = false
        daySlider?.isHidden = true
    }
    
    private func setupOrUpdateAnimatedNumber(value: Int) {
        guard let container = animatedNumberContainer else { return }
        
        currentDisplayValue = value
        let currentFont = availableBudgetValueLabel.font ?? Fonts.titleLG.font
        let currentColor = availableBudgetValueLabel.textColor ?? Colors.gray100
        
        if animatedNumberHost == nil {
            let swiftUIView = AnimatedNumberLabel(value: value, font: currentFont, color: currentColor, currencyCode: AppConfig.currencyCode)
            let hostController = UIHostingController(rootView: swiftUIView)
            hostController.view.backgroundColor = .clear
            hostController.view.setContentHuggingPriority(.required, for: .horizontal)
            hostController.view.setContentCompressionResistancePriority(.required, for: .horizontal)
            animatedNumberHost = hostController
            
            container.addSubview(hostController.view)
            hostController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostController.view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                hostController.view.widthAnchor.constraint(equalToConstant: 180),
                hostController.view.heightAnchor.constraint(equalTo: container.heightAnchor),
            ])
        } else {
            let swiftUIView = AnimatedNumberLabel(value: value, font: currentFont, color: currentColor, currencyCode: AppConfig.currencyCode)
            animatedNumberHost?.rootView = swiftUIView
        }
    }
    
    private func isCurrentMonth() -> Bool {
        guard let monthDate = currentMonthData?.date else { return false }
        
        // Use user's current timezone for consistency with monthAnchor calculations
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        
        let today = Date()
        let month = calendar.component(.month, from: monthDate)
        let year = calendar.component(.year, from: monthDate)
        let todayMonth = calendar.component(.month, from: today)
        let todayYear = calendar.component(.year, from: today)
        let isCurrent = (month == todayMonth) && (year == todayYear)
        
        return isCurrent
    }
    
    // MARK: - Actions
    
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
    private func handleBalanceLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        delegate?.didLongPressBalance()
    }
    
    @objc
    private func toggleBudgetView() {
        flipDelegate?.didRequestFlip(isShowingBudgetView: !isShowingBudgetView)
    }
    
    func setShowingBudgetView(_ showing: Bool) {
        isShowingBudgetView = showing
        let imageName = showing ? "creditcard.fill" : "chart.pie.fill"
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        budgetViewToggleButton.setImage(UIImage(systemName: imageName, withConfiguration: config), for: .normal)
    }
    
    // MARK: - Commented out balance toggle method
    /*
     @objc
     private func toggleBalanceDisplay() {
     switch displayMode {
     case .final:
     displayMode = .current
     case .current:
     displayMode = .final
     case .daySpecific(let day):
     // If in day-specific mode, toggle back to current
     displayMode = .current
     }
     
     // Only save to UserDefaults if it's a standard mode (not day-specific)
     switch displayMode {
     case .final, .current:
     UserDefaultsManager.setBalanceDisplayMode(displayMode)
     case .daySpecific:
     // Don't save day-specific mode to UserDefaults
     break
     }
     
     updateAvailableBudgetDisplay()
     }
     */
    
    @objc
    private func toggleHideValues() {
        isValuesHidden.toggle()
        UserDefaultsManager.setHideValues(isValuesHidden)
        updateHideValuesIcon()
        updateAvailableBudgetDisplay()
        updateLimitSection(with: currentMonthData!)
        
        // Update used value directly
        if let data = currentMonthData {
            usedBudgetValueLabel.text =
            isValuesHidden ? getHiddenValueString() : data.usedValue.currencyString
        }
        
        // Notify delegate to update all other cards
        delegate?.didToggleBalanceVisibility(isValuesHidden)
    }
    
    private func updateHideValuesIcon() {
        let iconName = isValuesHidden ? "eye" : "eye-closed"
        let iconImage = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate)
        
        // Update main toggle icon
        hideValuesIcon.image = iconImage
        
        // Update header toggle icon as well
        headerToggleIcon?.image = iconImage
    }
    
    private func getHiddenValueString() -> String {
        return "••••••"
    }
    
    private func updateTogglePositioning(with data: MonthBudgetCardType) {
        // Use separate toggles for header and budget value area
        if data.budgetLimit == nil || data.budgetLimit! <= 0 {
            // Show toggle in header (left of config icon) when no budget
            headerToggleContainer.isHidden = false
            hideValuesToggleContainer.isHidden = true
        } else {
            // Show toggle in budget value area when budget is set
            headerToggleContainer.isHidden = true
            hideValuesToggleContainer.isHidden = false
            
            // Ensure toggle is in budget value container
            if !availableBudgetValueWithToggleContainer.subviews.contains(hideValuesToggleContainer) {
                availableBudgetValueWithToggleContainer.addSubview(hideValuesToggleContainer)
                setupToggleConstraintsInBudgetContainer()
            }
        }
    }
    
    private func setupToggleConstraintsInBudgetContainer() {
        hideValuesToggleContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hideValuesToggleContainer.trailingAnchor.constraint(
                equalTo: availableBudgetValueWithToggleContainer.trailingAnchor),
            hideValuesToggleContainer.centerYAnchor.constraint(
                equalTo: availableBudgetValueWithToggleContainer.centerYAnchor),
            hideValuesToggleContainer.leadingAnchor.constraint(
                greaterThanOrEqualTo: availableBudgetValueLabel.trailingAnchor, constant: 8),
        ])
        
        // Ensure gesture recognizer is properly set up
        ensureToggleGestureRecognizer()
    }
    
    private func ensureToggleGestureRecognizer() {
        // Ensure both toggles have their gesture recognizers
        if hideValuesTapGesture == nil {
            hideValuesTapGesture = UITapGestureRecognizer(
                target: self, action: #selector(toggleHideValues))
            hideValuesToggleContainer.addGestureRecognizer(hideValuesTapGesture!)
        }
        
        if headerToggleTapGesture == nil {
            headerToggleTapGesture = UITapGestureRecognizer(
                target: self, action: #selector(toggleHideValues))
            headerToggleContainer.addGestureRecognizer(headerToggleTapGesture!)
        }
        
        hideValuesToggleContainer.isUserInteractionEnabled = true
        headerToggleContainer.isUserInteractionEnabled = true
    }
    
    func updateBalanceVisibility(_ isHidden: Bool) {
        isValuesHidden = isHidden
        updateHideValuesIcon()
        
        // Update used value directly
        if let data = currentMonthData {
            usedBudgetValueLabel.text =
            isValuesHidden ? getHiddenValueString() : data.usedValue.currencyString
        }
        
        // Update limit section
        updateLimitSection(with: currentMonthData!)
        
        // Update available budget display with visibility state
        updateAvailableBudgetDisplayWithVisibility()
        
        // Ensure gesture recognizer is maintained after visibility update
        ensureToggleGestureRecognizer()
    }
    
    // MARK: - Filter State
    
    /// Updates the card to show filtered transaction sum
    /// - Parameters:
    ///   - isActive: Whether filters are currently active
    ///   - sum: The sum of filtered transactions (in cents)
    func updateFilteredState(isActive: Bool, sum: Int) {
        isFilterActive = isActive
        filteredSum = sum
        
        if isActive {
            // Show container and filtered indicator, hide normal label
            availableBudgetTextLabelContainer.isHidden = false
            availableBudgetTextLabel.isHidden = true
            filteredIndicatorContainer.isHidden = false
            availableBudgetValueWithToggleContainer.isHidden = false
            
            // Update the value to show filtered sum
            if isValuesHidden {
                availableBudgetValueLabel.text = getHiddenValueString()
                availableBudgetValueLabel.isHidden = false
                animatedNumberContainer?.isHidden = true
            } else {
                setupOrUpdateAnimatedNumber(value: sum)
                animatedNumberContainer?.isHidden = false
                availableBudgetValueLabel.isHidden = true
            }
            
            // Hide the toggle icon when filtering
            hideValuesToggleContainer.isHidden = true
        } else {
            // Restore normal display
            filteredIndicatorContainer.isHidden = true
            
            // Restore normal budget display (this handles container visibility based on budget state)
            updateAvailableBudgetDisplay()
        }
    }
    
    /// Clears the filter state and restores normal display
    func clearFilteredState() {
        // Only update if filter was actually active to avoid redundant recalculations
        guard isFilterActive else { return }
        updateFilteredState(isActive: false, sum: 0)
    }
    
    private func updateAvailableBudgetDisplayWithVisibility() {
        guard let data = currentMonthData else { return }
        
        if data.budgetLimit != nil && data.budgetLimit! > 0 {
            // Budget is set - show budget information
            availableBudgetValueLabel.isHidden = false
            availableBudgetValueWithToggleContainer.isHidden = false
            availableBudgetTextLabelContainer.isHidden = false
            availableBudgetTextLabel.isHidden = false
            defineBudgetButton.isHidden = true
            
            let displayValue: Int
            let textKey: String
            
            switch displayMode {
            case .final:
                displayValue = data.finalBalance ?? (data.budgetLimit! - data.usedValue)
                // Use day-specific format for final balance (last day of month)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone.current
                let lastDay = calendar.range(of: .day, in: .month, for: data.date)?.upperBound ?? 31
                textKey = formatBalanceOnDayString(for: lastDay)
                
            case .current:
                displayValue = data.currentBalance ?? (data.previousBalance ?? 0)
                // Use day-specific format instead of old text key
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone.current
                let today = calendar.component(.day, from: Date())
                textKey = formatBalanceOnDayString(for: today)
                
            case .daySpecific(let day):
                displayValue = calculateBalanceForDay(day)
                textKey = formatBalanceOnDayString(for: day)
            }
            
            availableBudgetTextLabel.text = textKey.localized
            
            // Use animated SwiftUI view for all months
            if isValuesHidden {
                animatedNumberContainer?.isHidden = true
                availableBudgetValueLabel.isHidden = false
                availableBudgetValueLabel.text = getHiddenValueString()
            } else {
                animatedNumberContainer?.isHidden = false
                availableBudgetValueLabel.isHidden = true
                setupOrUpdateAnimatedNumber(value: displayValue)
            }
        } else {
            // No budget defined - hide budget information and show define button
            availableBudgetValueLabel.isHidden = true
            availableBudgetValueWithToggleContainer.isHidden = true
            availableBudgetTextLabelContainer.isHidden = true
            animatedNumberContainer?.isHidden = true
            defineBudgetButton.isHidden = false
        }
    }
    
    private func formatBalanceOnDayString(for day: Int) -> String {
        let currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        
        if currentLanguage == "en" {
            // English: Use ordinal suffixes (1st, 2nd, 3rd, etc.)
            return String(format: "monthCard.balanceOnDay".localized, dayWithOrdinalSuffix(day))
        } else {
            // Other languages: Use plain number
            return String(format: "monthCard.balanceOnDay".localized, String(day))
        }
    }
    
    private func dayWithOrdinalSuffix(_ day: Int) -> String {
        let suffix: String
        if day >= 11 && day <= 13 {
            suffix = "th"
        } else {
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }
    
    private func setupDaySliderForMonth(data: MonthBudgetCardType) {
        guard let slider = daySlider else { return }
        
        // Calculate current day and total days in month
        // Use the exact same calendar configuration as TransactionLedgerService
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let today = Date()
        let monthDate = data.date
        
        // Calculate total days in month using the correct method
        let totalDaysInMonth: Int
        if let range = calendar.range(of: .day, in: .month, for: monthDate) {
            totalDaysInMonth = range.count
        } else {
            totalDaysInMonth = 31  // fallback
        }
        
        // Calculate the actual current day of the month (for current month only)
        let currentMonthDay: Int = isCurrentMonth() ? calendar.component(.day, from: today) : 0
        
        // Determine the current day for this month (selected day)
        let currentDay: Int
        let isCurrent = isCurrentMonth()
        if isCurrent {
            // For current month, use today's day
            currentDay = calendar.component(.day, from: today)
        } else {
            // For all other months (past and future), default to the last day
            currentDay = totalDaysInMonth
        }
        
        // Add slider to the stack view if not already added
        if !isDaySliderVisible {
            availableBudgetStackView.addArrangedSubview(slider)
            isDaySliderVisible = true
            
            // Set up constraints
            NSLayoutConstraint.activate([
                slider.heightAnchor.constraint(equalToConstant: 40),
                slider.leadingAnchor.constraint(equalTo: availableBudgetStackView.leadingAnchor),
                slider.trailingAnchor.constraint(equalTo: availableBudgetStackView.trailingAnchor),
            ])
        }
        
        // Configure the slider
        slider.configure(
            currentDay: currentDay, totalDaysInMonth: totalDaysInMonth, currentMonthDay: currentMonthDay)
        slider.isHidden = false
        currentSelectedDay = currentDay
    }
    
    // MARK: - Public Methods
    
    /// Recalculates the current day for the day slider when dashboard appears in foreground
    /// Returns true if a refresh was needed, false if slider was already on current day
    @discardableResult
    func recalculateCurrentDay(animated: Bool = false) -> Bool {
        logDebug("recalculateCurrentDay called with animated: \(animated)")
        guard let data = currentMonthData, isCurrentMonth() else {
            logDebug("recalculateCurrentDay: No data or not current month")
            return false
        }
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let today = Date()
        let monthDate = data.date
        let totalDaysInMonth = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 31
        
        // Calculate the actual current day of the month
        let currentMonthDay = calendar.component(.day, from: today)
        
        // For current month, use today's day
        let currentDay = currentMonthDay
        
        // Check if slider is already on current day - if so, no refresh needed
        if currentSelectedDay == currentDay && isDaySliderVisible {
            return false
        }
        
        // Update the slider if it's visible
        if let slider = daySlider, isDaySliderVisible {
            // Check if we need to animate - always animate if explicitly requested
            let shouldAnimate = animated
            let dayChanged = currentSelectedDay != currentDay
            
            // Check if day indicators are already set up
            if slider.hasDayIndicators() {
                // Day indicators already exist, just update the current day without reconfiguring
                currentSelectedDay = currentDay
                
                // Update the display mode to show the correct balance for the new day
                displayMode = .daySpecific(day: currentDay)
                
                // If we need to animate, animate to the new day
                if shouldAnimate {
                    if dayChanged {
                        slider.setDay(currentDay, animated: true)
                    } else {
                        // Day hasn't changed, but we want to show refresh animation
                        slider.animateForegroundRefresh()
                    }
                }
            } else {
                // Day indicators not set up, use configure to set them up
                slider.configure(
                    currentDay: currentDay,
                    totalDaysInMonth: totalDaysInMonth,
                    currentMonthDay: currentMonthDay
                )
                currentSelectedDay = currentDay
                
                // Update the display mode to show the correct balance for the new day
                displayMode = .daySpecific(day: currentDay)
            }
        }
        
        return true  // Refresh was needed
    }
    
    private func hideDaySlider() {
        guard let slider = daySlider, isDaySliderVisible else {
            return
        }
        
        slider.isHidden = true
        availableBudgetStackView.removeArrangedSubview(slider)
        slider.removeFromSuperview()
        isDaySliderVisible = false
    }
    
    /// Resets the card state for cell reuse to ensure consistent layout
    func resetForReuse() {
        // Force remove day slider from stack view regardless of isDaySliderVisible flag
        // This handles edge cases where the flag might be out of sync with view hierarchy
        if let slider = daySlider {
            if availableBudgetStackView.arrangedSubviews.contains(slider) {
                availableBudgetStackView.removeArrangedSubview(slider)
            }
            slider.removeFromSuperview()
            slider.isHidden = true
        }
        isDaySliderVisible = false
        
        // Remove all views from stack and re-add in correct order
        // This ensures clean state with no residual spacing issues
        availableBudgetStackView.arrangedSubviews.forEach { view in
            availableBudgetStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        // Re-add views in correct order
        availableBudgetStackView.addArrangedSubview(availableBudgetTextLabelContainer)
        availableBudgetStackView.addArrangedSubview(availableBudgetValueWithToggleContainer)
        availableBudgetStackView.addArrangedSubview(defineBudgetButton)
        
        // Reset visibility to default (no budget) state
        availableBudgetTextLabelContainer.isHidden = true
        availableBudgetValueWithToggleContainer.isHidden = true
        defineBudgetButton.isHidden = false
        filteredIndicatorContainer.isHidden = true
        animatedNumberContainer?.isHidden = true
        
        // Reset filter state
        isFilterActive = false
        filteredSum = 0
        
        // Force complete layout invalidation
        availableBudgetStackView.setNeedsLayout()
        availableBudgetStackView.layoutIfNeeded()
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    private func calculateBalanceForDay(_ day: Int) -> Int {
        logDebug("calculateBalanceForDay called with day: \(day)")
        guard let data = currentMonthData else {
            logDebug("calculateBalanceForDay: No currentMonthData, returning 0")
            return 0
        }
        
        // Use the TransactionLedgerService to calculate balance for specific day
        let ledgerService = TransactionLedgerService()
        
        if isCurrentMonth() {
            // For current month, use the existing method
            let result = ledgerService.calculateCurrentMonthBalanceForDay(day: day)
            return result
        } else {
            // For other months, calculate balance for that specific day in that month
            let monthAnchor = data.date.monthAnchor
            
            // Get previous month's final balance
            // Calculate previous month anchor properly (go back one month, not just subtract 1 from timestamp)
            let calendar = Calendar.current
            guard let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: data.date) else {
                return 0
            }
            let previousMonthAnchor = previousMonthDate.monthAnchor
            let previousMonthData = ledgerService.getMonthlyData(for: previousMonthAnchor)
            let previousBalance = previousMonthData?.finalBalance ?? 0
            
            let result = ledgerService.calculateBalanceForDay(
                day: day, monthAnchor: monthAnchor, previousMonthBalance: previousBalance)
            return result
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        
        // MARK: - Commented out balance toggle layout updates
        /*
         // Garantir que o botão de toggle seja sempre redondo
         // Usar valor fixo baseado na constraint de largura (36)
         balanceToggleContainer.layer.cornerRadius = 18
         balanceToggleContainer.layer.masksToBounds = true
         */
    }
    
    // MARK: - Enhanced Refresh with Animation
    
    /// Refreshes the card data with smooth animations
    func refresh(with data: MonthBudgetCardType) {
        logDebug("refresh called with budgetLimit: \(data.budgetLimit ?? 0)")
        currentMonthData = data
        budgetDate = data.date
        
        // Animate text changes
        UIView.transition(with: monthLabel, duration: 0.3, options: .transitionCrossDissolve) {
            self.monthLabel.text = data.month
            self.monthLabel.applyStyle()
        }
        
        UIView.transition(with: yearLabel, duration: 0.3, options: .transitionCrossDissolve) {
            self.yearLabel.text = "/ " + DateFormatter.yearFormatter.string(from: data.date)
        }
        
        UIView.transition(with: usedBudgetValueLabel, duration: 0.3, options: .transitionCrossDissolve)
        {
            self.usedBudgetValueLabel.text =
            self.isValuesHidden ? self.getHiddenValueString() : data.usedValue.currencyString
        }
        
        // Store the current display mode before any changes
        let previousDisplayMode = displayMode
        
        // Update toggle positioning based on budget status
        updateTogglePositioning(with: data)
        
        // Update toggle icons
        updateHideValuesIcon()
        
        // Setup day slider only if budget is set
        if data.budgetLimit != nil && data.budgetLimit! > 0 {
            
            // Check if day slider exists and is configured (not just visible in view hierarchy)
            if let slider = daySlider, slider.superview != nil {
                
                // Always reconfigure the slider to ensure correct day indicator and day count
                // This is important for all months to ensure correct state
                setupDaySliderForMonth(data: data)
            } else {
                setupDaySliderForMonth(data: data)
            }
        } else {
            hideDaySlider()
        }
        
        // Calculate the correct day for this month
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let today = Date()
        let monthDate = data.date
        
        // Calculate total days in month
        let totalDaysInMonth: Int
        if let range = calendar.range(of: .day, in: .month, for: monthDate) {
            totalDaysInMonth = range.count
        } else {
            totalDaysInMonth = 31  // fallback
        }
        
        // Calculate the correct day for this month
        let isCurrent = isCurrentMonth()
        let correctDay: Int
        if isCurrent {
            correctDay = calendar.component(.day, from: today)
        } else {
            correctDay = totalDaysInMonth
        }
        
        // Update currentSelectedDay to match the correct day for this month
        currentSelectedDay = correctDay
        
        // Set display mode based on month type and day slider state
        // Use isDaySliderVisible directly - don't wait for hasDayIndicators() since
        // indicators are created during layout which happens after configure/refresh
        if isCurrentMonth() {
            // For current month, use day-specific mode if day slider is visible
            if isDaySliderVisible {
                // Set to day-specific mode with the correct day for this month
                displayMode = .daySpecific(day: correctDay)
            } else {
                let newMode = UserDefaultsManager.getBalanceDisplayMode()
                displayMode = newMode
            }
        } else {
            // For non-current months, use day-specific mode if day slider is visible
            if isDaySliderVisible {
                // Set to day-specific mode with the correct day for this month
                displayMode = .daySpecific(day: correctDay)
            } else {
                displayMode = .final
            }
        }
        
        // Update available budget display first
        updateAvailableBudgetDisplay()
        
        // Animate balance update with enhanced effect
        animateAvailableBudgetUpdate()
        updateLimitSection(with: data)
    }
    
    private func animateAvailableBudgetUpdate() {
        guard let data = currentMonthData else { return }
        
        let targetValue: Int
        switch displayMode {
        case .final:
            targetValue = data.finalBalance ?? 0
        case .current:
            targetValue = data.currentBalance ?? 0
        case .daySpecific(let day):
            targetValue = calculateBalanceForDay(day)
        }
        
        // Add a subtle scale animation to draw attention to the changing value
        UIView.animate(
            withDuration: 0.2,
            animations: {
                if let container = self.animatedNumberContainer {
                    container.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
                }
            }
        ) { _ in
            // Update only the animated value without overriding the text label
            self.updateAnimatedValue(targetValue)
            
            // Scale back to normal
            UIView.animate(withDuration: 0.2) {
                if let container = self.animatedNumberContainer {
                    container.transform = .identity
                }
            }
        }
    }
    
    private func updateAnimatedValue(_ value: Int) {
        currentDisplayValue = value
        
        // Update the text label based on current display mode
        let textKey: String
        switch displayMode {
        case .final:
            // Use day-specific format for final balance (last day of month)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone.current
            let monthDate = currentMonthData?.date ?? Date()
            let lastDay = calendar.range(of: .day, in: .month, for: monthDate)?.upperBound ?? 31
            textKey = formatBalanceOnDayString(for: lastDay)
        case .current:
            // Use day-specific format for current balance (today)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone.current
            let today = calendar.component(.day, from: Date())
            textKey = formatBalanceOnDayString(for: today)
        case .daySpecific(let day):
            textKey = formatBalanceOnDayString(for: day)
        }
        
        // Check if budget is set for this specific cell before showing labels
        guard let data = currentMonthData, data.budgetLimit != nil && data.budgetLimit! > 0 else {
            availableBudgetTextLabelContainer.isHidden = true
            availableBudgetValueLabel.isHidden = true
            availableBudgetValueWithToggleContainer.isHidden = true
            animatedNumberContainer?.isHidden = true
            return
        }
        availableBudgetTextLabel.text = textKey.localized
        
        // Update only the animated SwiftUI view without touching the text label
        if isValuesHidden {
            // If values are hidden, show the regular label with hidden text
            animatedNumberContainer?.isHidden = true
            availableBudgetValueLabel.isHidden = false
            availableBudgetValueLabel.text = getHiddenValueString()
        } else {
            // If values are visible, show the animated view for all months
            animatedNumberContainer?.isHidden = false
            availableBudgetValueLabel.isHidden = true
            
            if let host = animatedNumberHost {
                let currentFont = availableBudgetValueLabel.font ?? Fonts.titleLG.font
                let currentColor = availableBudgetValueLabel.textColor ?? Colors.gray100

                host.rootView = AnimatedNumberLabel(
                    value: value,
                    font: currentFont,
                    color: currentColor,
                    currencyCode: AppConfig.currencyCode
                )
            }
        }
    }
}

// MARK: - DaySliderDelegate
extension MonthBudgetCard: DaySliderDelegate {
    func daySlider(_ slider: DaySlider, didSelectDay day: Int) {
        currentSelectedDay = day
        displayMode = .daySpecific(day: day)
        // Always update on final selection to ensure correct state
        updateAvailableBudgetDisplay()
    }
    
    func daySlider(_ slider: DaySlider, didReachCurrentDay day: Int) {
        // Optional: Add any special handling when reaching current day
        // For example, could show a brief animation or change color
    }
    
    func daySlider(_ slider: DaySlider, didChangeDay day: Int) {
        // Real-time updates during sliding with throttling
        currentSelectedDay = day
        displayMode = .daySpecific(day: day)
        
        // Throttle updates to improve performance
        let currentTime = CACurrentMediaTime()
        if currentTime - lastUpdateTime > 0.05 {  // Update at most 20 times per second
            lastUpdateTime = currentTime
            updateAvailableBudgetDisplay()
        }
    }
}
