//
//  BudgetCard.swift
//  Finova
//
//  Created by Arthur Rios on 02/02/26.
//

import UIKit

final class BudgetCard: UIView {

    // MARK: - Properties

    weak var delegate: MonthCardFlipDelegate?
    private let gradientLayer = Colors.gradientBlack

    // MARK: - UI Components

    private lazy var placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "budget.allocations.title".localized
        label.font = Fonts.titleMD.font
        label.textColor = Colors.gray100
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var flipBackButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.setImage(UIImage(systemName: "creditcard.fill", withConfiguration: config), for: .normal)
        button.tintColor = Colors.gray100
        button.addTarget(self, action: #selector(flipBack), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // Apply gradient background like MonthBudgetCard
        layer.insertSublayer(gradientLayer, at: 0)
        layer.cornerRadius = CornerRadius.extraLarge
        clipsToBounds = true

        addSubview(flipBackButton)
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            flipBackButton.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.spacing6),
            flipBackButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing6),

            placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
    
    @objc
    private func flipBack() {
        delegate?.didRequestFlip(isShowingBudgetView: false)
    }
    
    // MARK: Configuration (stub)
    
    func configure(
        month: String,
        year: String,
        allocations: [BudgetAllocation],
        unallocatedSummary: UnallocatedBudgetSummary
    ) {
        placeholderLabel.text = String(
            format: "budget.allocations.month.format".localized,
            month,
            allocations.count,
        )
    }
}
