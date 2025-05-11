//
//  MonthBudgetCard.swift
//  FinanceApp
//
//  Created by Arthur Rios on 10/05/25.
//

import Foundation
import UIKit

class MonthBudgetCard: UIView {
    
    private let gradientLayer = Colors.gradientBlack
    
    private let mainStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let headerHorizontalStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let monthLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.textColor = Colors.gray100
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
    
    private let availableBudgetStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let availableBudgetTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.text = "Orçamento disponível"
        label.textColor = Colors.gray400
        return label
    }()
    
    private var availableBudgetValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleLG.font
        label.textColor = Colors.gray100
        return label
    }()
    
    private let defineBudgetButton = Button(variant: .outlined, label: "Definir orçamento")
    
    private let footerStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let usedBudgetStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = Metrics.spacing2
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let usedBudgetTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.text = "Usado"
        label.textColor = Colors.gray400
        return label
    }()
    
    private var usedBudgetValueLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray100
        return label
    }()
    
    private let limitBudgetStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .trailing
        stackView.spacing = Metrics.spacing2
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let limitBudgetTextLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.text = "Limite"
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
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.insertSublayer(gradientLayer, at: 0)
        layer.cornerRadius = CornerRadius.extraLarge
        layer.masksToBounds = true
        
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(month: String,
                   availableValue: Int? = nil,
                   usedValue: Int,
                   budgetLimit: Int? = nil) {
        monthLabel.text = month
        availableBudgetValueLabel.text = availableValue?.currencyString
        usedBudgetValueLabel.text = usedValue.currencyString
        
        if availableValue == nil {
            availableBudgetValueLabel.isHidden = true
        } else {
            defineBudgetButton.isHidden = true
        }
        
        if budgetLimit == nil {
            limitBudgetValueLabel.isHidden = true
        } else {
            limitBudgetValueLabel.text = budgetLimit?.currencyString
            infinitySymbol.isHidden = true
        }
        
        monthLabel.applyStyle()
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        
        setupMainStackView()
        setupHeaderStackView()
        setupAvailableBudgetStackView()
        setupFooterStackView()
    }
    
    private func setupMainStackView() {
        addSubview(mainStackView)
        mainStackView.pinToSuperview(with: UIEdgeInsets(top: Metrics.spacing6, left: Metrics.spacing6, bottom: Metrics.spacing7, right: Metrics.spacing6))
        mainStackView.addArrangedSubview(headerHorizontalStackView)
        mainStackView.setCustomSpacing(Metrics.spacing4, after: headerHorizontalStackView)
        mainStackView.addArrangedSubview(separator)
        mainStackView.setCustomSpacing(Metrics.spacing3, after: separator)
        mainStackView.addArrangedSubview(availableBudgetStackView)
        mainStackView.addArrangedSubview(footerStackView)
        mainStackView.setCustomSpacing(Metrics.spacing5, after: availableBudgetStackView)
    }
    
    private func setupHeaderStackView() {
        headerHorizontalStackView.addArrangedSubview(monthLabel)
        headerHorizontalStackView.addArrangedSubview(configIcon)
    }
    
    private func setupAvailableBudgetStackView() {
        availableBudgetStackView.addArrangedSubview(availableBudgetTextLabel)
        availableBudgetStackView.addArrangedSubview(availableBudgetValueLabel)
        availableBudgetStackView.addArrangedSubview(defineBudgetButton)
        
        availableBudgetStackView.setCustomSpacing(Metrics.spacing3, after: availableBudgetTextLabel)
    }
    
    private func setupFooterStackView() {
        footerStackView.addArrangedSubview(usedBudgetStackView)
        footerStackView.addArrangedSubview(limitBudgetStackView)
        usedBudgetStackView.addArrangedSubview(usedBudgetTextLabel)
        usedBudgetStackView.addArrangedSubview(usedBudgetValueLabel)
        limitBudgetStackView.addArrangedSubview(limitBudgetTextLabel)
        limitBudgetStackView.addArrangedSubview(limitBudgetValueLabel)
        limitBudgetStackView.addArrangedSubview(infinitySymbol)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
}
