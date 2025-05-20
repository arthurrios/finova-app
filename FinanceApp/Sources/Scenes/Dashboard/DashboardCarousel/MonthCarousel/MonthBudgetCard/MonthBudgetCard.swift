//
//  MonthBudgetCard.swift
//  FinanceApp
//
//  Created by Arthur Rios on 10/05/25.
//

import Foundation
import UIKit

class MonthBudgetCard: UIView {
    weak var delegate: MonthBudgetCardDelegate?
    private var budgetDate: Date?
    
    private let gradientLayer = Colors.gradientBlack
    
    private lazy var mainStackView = UIStackView(axis: .vertical, arrangedSubviews: [headerHorizontalStackView, separator, availableBudgetStackView, footerStackView])
    
    private lazy var headerHorizontalStackView = UIStackView(axis: .horizontal, arrangedSubviews: [headerDateStackView, configIcon])
    
    private lazy var headerDateStackView = UIStackView(axis: .horizontal, spacing: Metrics.spacing2, alignment: .center, arrangedSubviews: [monthLabel, yearLabel])
    
    private lazy var availableBudgetStackView = UIStackView(axis: .vertical, spacing: Metrics.spacing3, arrangedSubviews: [availableBudgetTextLabel, availableBudgetValueLabel, defineBudgetButton])
    
    private lazy var footerStackView = UIStackView(axis: .horizontal, arrangedSubviews: [usedBudgetStackView, limitBudgetStackView])
    
    private lazy var usedBudgetStackView = UIStackView(axis: .vertical, spacing: Metrics.spacing2, arrangedSubviews: [usedBudgetTextLabel, usedBudgetValueLabel])
    
    private lazy var limitBudgetStackView = UIStackView(axis: .vertical, spacing: Metrics.spacing2, alignment: .trailing, arrangedSubviews: [limitBudgetTextLabel, limitBudgetValueLabel, infinitySymbol])
    
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
        label.text = "monthCard.availableBudget".localized
        label.textColor = Colors.gray400
        return label
    }()
    
    private var availableBudgetValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleLG.font
        label.textColor = Colors.gray100
        return label
    }()
    
    private let defineBudgetButton = Button(variant: .outlined, label: "monthCard.defineBudget".localized)
    
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
        setupGestureRecognizers()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(data: MonthBudgetCardType) {
        budgetDate = data.date
                
        monthLabel.text = data.month
        monthLabel.applyStyle()
        
        yearLabel.text = "/ " + DateFormatter.yearFormatter.string(from: data.date)
        
        if let availableValue = data.availableValue {
            availableBudgetValueLabel.text = availableValue.currencyString
            availableBudgetValueLabel.isHidden = false
            defineBudgetButton.isHidden = true
        } else {
            availableBudgetValueLabel.isHidden = true
            defineBudgetButton.isHidden = false
        }
        
        usedBudgetValueLabel.text = data.usedValue.currencyString
        
        if let budgetLimit = data.budgetLimit {
            limitBudgetValueLabel.text = budgetLimit.currencyString
            limitBudgetValueLabel.isHidden = false
            infinitySymbol.isHidden = true
            progressBar.isHidden = false
            
            if let availableValue = data.availableValue, budgetLimit != 0 {
                progressBar.setProgress(Float(data.usedValue) / Float(budgetLimit), animated: true)
                if availableValue < 0, data.usedValue >= budgetLimit {
                    progressBar.progress = 1
                    progressBar.progressTintColor = Colors.mainRed
                }
            } else {
                progressBar.progress = 0
            }
            
        } else {
            availableBudgetValueLabel.isHidden = true
            defineBudgetButton.isHidden = false
            limitBudgetValueLabel.isHidden = true
            progressBar.isHidden = true
            infinitySymbol.isHidden = false
            
            let isPreviousMonth = DateUtils.isPastMonth(date: data.date)
            applyButtonStyle(isPreviousMonth: isPreviousMonth)
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
        mainStackView.pinToSuperview(with: UIEdgeInsets(top: Metrics.spacing6, left: Metrics.spacing6, bottom: Metrics.spacing7, right: Metrics.spacing6))
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
            progressBar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
        ])
    }
    
    private func setupGestureRecognizers() {
        let configTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleConfigTapGesture))
        configIcon.addGestureRecognizer(configTapGesture)
        
        defineBudgetButton.addTarget(self, action: #selector(defineBudgetButtonTapped), for: .touchUpInside)
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
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        progressBar.roundRightCornersFixedHeight(Metrics.spacing2)
    }
}
