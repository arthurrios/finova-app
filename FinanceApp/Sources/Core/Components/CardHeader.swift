//
//  CardHeader.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/05/25.
//

import Foundation
import UIKit

class CardHeader: UIView {
    private let cardHeaderStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.layer.cornerRadius = CornerRadius.extraLarge
        stackView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        stackView.backgroundColor = Colors.gray100
        stackView.layoutMargins = UIEdgeInsets(top: 0, left: Metrics.spacing5, bottom: 0, right: Metrics.spacing4)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.distribution = .equalSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let cardHeaderTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.title2XS
        label.textColor = Colors.gray500
        label.text = "transactions.header.title".localized
        label.applyStyle()
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let itemsQuantityContainerView: UIStackView = {
        let stackView = UIStackView()
        stackView.isHidden = true
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        stackView.layoutMargins = UIEdgeInsets(top: 0, left: Metrics.spacing2, bottom: 0, right: Metrics.spacing2)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.backgroundColor = Colors.gray300
        stackView.clipsToBounds = true
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let itemsQuantityLabel: UILabel = {
        let label = UILabel()
        label.isHidden = true
        label.font = Fonts.titleXS.font
        label.textColor = Colors.gray600
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    init(headerTitle: String, itemsQuantity: String? = nil) {
        super.init(frame: .zero)
        setupViews()
        
        configure(headerTitle: headerTitle, itemsQuantity: itemsQuantity)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(headerTitle: String, itemsQuantity: String? = nil) {
        cardHeaderTitleLabel.text = headerTitle
        cardHeaderTitleLabel.applyStyle()
        
        if let quantity = itemsQuantity {
            itemsQuantityLabel.text = quantity
            itemsQuantityContainerView.isHidden = false
            itemsQuantityLabel.isHidden = false
        }
    }
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(cardHeaderStackView)
        cardHeaderStackView.addArrangedSubview(cardHeaderTitleLabel)
        cardHeaderStackView.addArrangedSubview(itemsQuantityContainerView)
        itemsQuantityContainerView.addArrangedSubview(itemsQuantityLabel)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            cardHeaderStackView.topAnchor.constraint(equalTo: topAnchor),
            cardHeaderStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardHeaderStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardHeaderStackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            cardHeaderStackView.heightAnchor.constraint(equalToConstant: Metrics.cardHeaderHeight),
        ])
    }
    
    private func addBordersExceptBottom(to view: UIView, color: UIColor, width: CGFloat = 1.0) {
        view.layer.sublayers?.removeAll(where: { $0.name == "customBorder" })
        
        let bounds = view.bounds
        let cornerRadius = view.layer.cornerRadius
        
        let path = UIBezierPath()
        
        path.move(to: CGPoint(x: 0, y: bounds.height))
        
        path.addLine(to: CGPoint(x: 0, y: cornerRadius))
        
        path.addArc(withCenter: CGPoint(x: cornerRadius, y: cornerRadius),
                    radius: cornerRadius,
                    startAngle: .pi,
                    endAngle: 3 * .pi / 2,
                    clockwise: true)
        
        path.addLine(to: CGPoint(x: bounds.width - cornerRadius, y: 0))
        
        path.addArc(withCenter: CGPoint(x: bounds.width - cornerRadius, y: cornerRadius),
                    radius: cornerRadius,
                    startAngle: 3 * .pi / 2,
                    endAngle: 0,
                    clockwise: true)
        
        path.addLine(to: CGPoint(x: bounds.width, y: bounds.height))
        
        let borderLayer = CAShapeLayer()
        borderLayer.name = "customBorder"
        borderLayer.path = path.cgPath
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = color.cgColor
        borderLayer.lineWidth = width
        borderLayer.frame = bounds
        
        view.layer.addSublayer(borderLayer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        itemsQuantityContainerView.layoutIfNeeded()
        
        let size = min(itemsQuantityContainerView.bounds.width, itemsQuantityContainerView.bounds.height)
        itemsQuantityContainerView.layer.cornerRadius = size / 2
        
        itemsQuantityContainerView.clipsToBounds = true
        
        cardHeaderStackView.layer.sublayers?.removeAll(where: { $0 is CAShapeLayer })
        cardHeaderStackView.layoutIfNeeded()
        addBordersExceptBottom(to: cardHeaderStackView, color: Colors.gray300)
    }
}
