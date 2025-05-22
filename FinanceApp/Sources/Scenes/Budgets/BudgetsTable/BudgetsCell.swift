//
//  TransactionCell.swift
//  FinanceApp
//
//  Created by Arthur Rios on 15/05/25.
//

import Foundation
import UIKit

public class BudgetsCell: UITableViewCell {
    weak var delegate: BudgetsCellDelegate?
    
    static let reuseID = "BudgetsCell"
        
    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "calendar")
        imageView.tintColor = Colors.gray700
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let titleStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let monthLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.numberOfLines = 0
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let yearLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray600
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let valueStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Metrics.spacing1
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let valueLabel: UILabel = {
        let label = UILabel()
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let trashIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "trash")
        imageView.heightAnchor.constraint(equalToConstant: Metrics.spacing4).isActive = true
        imageView.tintColor = Colors.mainMagenta
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let actionContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.mainMagenta
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let actionIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "trash")
        imageView.tintColor = Colors.gray100
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let actionLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.buttonSM.font
        label.textColor = Colors.gray100
        label.text = "delete.action.label".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var actionContainerWidthConstraint: NSLayoutConstraint!
    private var panStartX: CGFloat = 0

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
        setupPanGesture()
        clipsToBounds = false
        contentView.clipsToBounds = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        contentView.backgroundColor = Colors.gray100
        
        contentView.addSubview(iconView)
        contentView.addSubview(titleStackView)
        titleStackView.addArrangedSubview(monthLabel)
        titleStackView.addArrangedSubview(yearLabel)
        contentView.addSubview(valueStackView)
        valueStackView.addArrangedSubview(valueLabel)

        contentView.addSubview(trashIconView)
        contentView.addSubview(actionContainerView)
        actionContainerView.addSubview(actionIconView)
        actionContainerView.addSubview(actionLabel)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing5),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.spacing5),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.spacing5),
            
            titleStackView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Metrics.spacing3),
            titleStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            trashIconView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing5),
            trashIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            valueStackView.trailingAnchor.constraint(equalTo: trashIconView.leadingAnchor, constant: -Metrics.spacing3),
            valueStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            actionContainerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            actionContainerView.leadingAnchor.constraint(equalTo: contentView.trailingAnchor),
            actionContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            actionIconView.leadingAnchor.constraint(equalTo: actionContainerView.leadingAnchor, constant: Metrics.spacing6),
            actionIconView.centerYAnchor.constraint(equalTo: actionContainerView.centerYAnchor),
            actionIconView.heightAnchor.constraint(equalToConstant: Metrics.spacing5),
            actionIconView.widthAnchor.constraint(equalToConstant: Metrics.spacing5),
            
            actionLabel.leadingAnchor.constraint(equalTo: actionIconView.trailingAnchor, constant: Metrics.spacing3),
            actionLabel.centerYAnchor.constraint(equalTo: actionContainerView.centerYAnchor)
        ])
        
        actionContainerWidthConstraint = actionContainerView.widthAnchor.constraint(equalTo: contentView.widthAnchor)
        actionContainerWidthConstraint.isActive = true
    }
    
    func configure(date: Date, value: Int) {
        let month = DateFormatter.monthFormatter.string(from: date)
        let year = DateFormatter.yearFormatter.string(from: date)

        monthLabel.text = month
        yearLabel.text = year
        
        let symbolFont = Fonts.textXS.font
        self.valueLabel.attributedText = value.currencyAttributedString(symbolFont: symbolFont, font: Fonts.titleMD)
        self.valueLabel.accessibilityLabel = value.currencyString
        
        let isPreviousMonth = DateUtils.isPastMonth(date: date)
        applyStyleForDate(isPreviousMonth: isPreviousMonth)
    }
    
    private func setupPanGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        contentView.addGestureRecognizer(pan)
    }
    
    private func applyStyleForDate(isPreviousMonth: Bool) {
        if isPreviousMonth {
            monthLabel.textColor = Colors.gray400
            yearLabel.textColor = Colors.gray400
            valueLabel.textColor = Colors.gray400
            iconView.tintColor = Colors.gray400
            trashIconView.isHidden = true
        } else {
            monthLabel.textColor = Colors.gray700
            yearLabel.textColor = Colors.gray600
            valueLabel.textColor = Colors.gray700
            iconView.tintColor = Colors.gray700
        }
    }
    
    @objc
    private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translationX = gesture.translation(in: self).x
        let fullWidth    = contentView.bounds.width
        
        switch gesture.state {
        case .began:
            panStartX = contentView.frame.origin.x
            
        case .changed:
            let rawX = panStartX + translationX
            let clampedX = max(-fullWidth, min(0, rawX))
            contentView.frame.origin.x = clampedX
            
        case .ended, .cancelled:
            let shouldOpen = contentView.frame.origin.x < -fullWidth / 2
            UIView.animate(withDuration: 0.2, animations: {
                self.contentView.frame.origin.x = shouldOpen ? -fullWidth : 0
            }, completion: { _ in
                if shouldOpen && self.contentView.frame.origin.x <= -fullWidth + 0.1 {
                    self.delegate?.budgetCellDidRequestDelete(self)
                }
            })
            
        default:
            break
        }
    }
}
