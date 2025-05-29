//
//  TransactionCell.swift
//  FinanceApp
//
//  Created by Arthur Rios on 15/05/25.
//

import Foundation
import UIKit

final public class TransactionCell: UITableViewCell {
    static let reuseID = "TransactionCell"
        
    var onDelete: (() -> Void)?
    
    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = Colors.mainMagenta
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let iconContainerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = CornerRadius.medium
        view.backgroundColor = Colors.gray200
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.borderWidth = 1
        view.layer.masksToBounds = true
        view.heightAnchor.constraint(equalToConstant: Metrics.spacing8).isActive = true
        view.widthAnchor.constraint(equalToConstant: Metrics.spacing8).isActive = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let titleStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = Metrics.spacing1
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
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
    
    private let transactionTypeIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.heightAnchor.constraint(equalToConstant: 14).isActive = true
        imageView.widthAnchor.constraint(equalToConstant: 14).isActive = true
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
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
    
    private var actionWidthConstraint: NSLayoutConstraint!
    private var panStartX: CGFloat = 0
    
    private lazy var panGR: UIPanGestureRecognizer = {
        let g = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        g.delegate = self
        g.cancelsTouchesInView = false
        g.delaysTouchesBegan = false
        g.delaysTouchesEnded = false
        return g
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
        
        contentView.addGestureRecognizer(panGR)
    }
    
    public override func prepareForReuse() {
        super.prepareForReuse()
        contentView.transform = .identity
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        contentView.backgroundColor = Colors.gray100
        
        contentView.addSubview(iconContainerView)
        iconContainerView.addSubview(iconView)
        contentView.addSubview(titleStackView)
        titleStackView.addArrangedSubview(titleLabel)
        titleStackView.addArrangedSubview(dateLabel)
        contentView.addSubview(valueStackView)
        valueStackView.addArrangedSubview(valueLabel)
        valueStackView.addArrangedSubview(transactionTypeIconView)
        contentView.addSubview(trashIconView)
        
        contentView.addSubview(actionContainerView)
        actionContainerView.addSubview(actionIconView)
        actionContainerView.addSubview(actionLabel)
        
        actionWidthConstraint = actionContainerView.widthAnchor
            .constraint(equalTo: contentView.widthAnchor)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueStackView.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueStackView.setContentHuggingPriority(.required, for: .horizontal)
        
        trashIconView.setContentHuggingPriority(.required, for: .horizontal)
        trashIconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleStackView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        let titleToValue = titleStackView.trailingAnchor
            .constraint(equalTo: valueStackView.leadingAnchor,
                        constant: -Metrics.spacing4)
        titleToValue.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            iconContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.spacing5),
            iconContainerView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            iconView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.spacing5),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.spacing5),
            
            titleStackView.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: Metrics.spacing4),
            titleStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleToValue,
            
            trashIconView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.spacing5),
            trashIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            trashIconView.widthAnchor.constraint(equalToConstant: Metrics.spacing4),
            
            valueStackView.trailingAnchor.constraint(equalTo: trashIconView.leadingAnchor, constant: -Metrics.spacing3),
            valueStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            actionContainerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            actionContainerView.leadingAnchor.constraint(equalTo: contentView.trailingAnchor),
            actionContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            actionWidthConstraint,
            
            actionIconView.leadingAnchor.constraint(equalTo: actionContainerView.leadingAnchor, constant: Metrics.spacing6),
            actionIconView.centerYAnchor.constraint(equalTo: actionContainerView.centerYAnchor),
            actionIconView.heightAnchor.constraint(equalToConstant: Metrics.spacing5),
            actionIconView.widthAnchor.constraint(equalToConstant: Metrics.spacing5),
            
            actionLabel.leadingAnchor.constraint(equalTo: actionIconView.trailingAnchor, constant: Metrics.spacing3),
            actionLabel.centerYAnchor.constraint(equalTo: actionContainerView.centerYAnchor)
        ])
    }
    
    func configure(category: TransactionCategory, title: String, date: Date, value: Int, transactionType: TransactionType) {
        self.titleLabel.text = title
        self.dateLabel.text = DateFormatter.fullDateFormatter.string(from: date)
        
        let symbolFont = Fonts.textXS.font
        self.valueLabel.attributedText = value.currencyAttributedString(symbolFont: symbolFont, font: Fonts.titleMD)
        self.valueLabel.accessibilityLabel = value.currencyString
        
        self.iconView.image = UIImage(named: category.iconName)
        
        if transactionType == .income {
            self.transactionTypeIconView.image = UIImage(named: "arrowUp")
            self.transactionTypeIconView.tintColor = Colors.mainGreen
        } else {
            self.transactionTypeIconView.image = UIImage(named: "arrowDown")
            self.transactionTypeIconView.tintColor = Colors.mainRed
        }
    }
    
    @objc
    private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translationX = gesture.translation(in: contentView).x
        let fullWidth = contentView.bounds.width

        switch gesture.state {
        case .began:
            panStartX = contentView.frame.origin.x

        case .changed:
            let rawX = panStartX + translationX
            let clampedX = max(-fullWidth, min(0, rawX))
            contentView.frame.origin.x = clampedX

        case .ended, .cancelled:
            let finalX = contentView.frame.origin.x
            let shouldOpen = abs(finalX) >= fullWidth * 0.5

            UIView.animate(withDuration: 0.2, animations: {
                self.contentView.frame.origin.x = shouldOpen ? -fullWidth : 0
            }, completion: { _ in
                if shouldOpen {
                    self.onDelete?()
                }
            })

        default:
            break
        }
    }
}

extension TransactionCell {
    public override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      guard gestureRecognizer === panGR,
            let otherPan = otherGestureRecognizer as? UIPanGestureRecognizer else {
        return false
      }

      let vel = otherPan.velocity(in: contentView)
      return abs(vel.y) > abs(vel.x)
    }
    
    public override func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
      guard let pan = gr as? UIPanGestureRecognizer else { return true }
      let v = pan.velocity(in: contentView)
      return abs(v.x) > abs(v.y)
    }
    
    public override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      guard gestureRecognizer === panGR,
            let otherPan = otherGestureRecognizer as? UIPanGestureRecognizer else {
        return false
      }
      let vel = otherPan.velocity(in: contentView)

      return abs(vel.y) > abs(vel.x)
    }
}
