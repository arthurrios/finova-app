//
//  CreditCardCell.swift
//  Finova
//

import UIKit

final class CreditCardCell: UIView {
    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?

    private let cardPreview: UIView = {
        let view = UIView()
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let cardNameLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleSM.font
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let lastFourLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = UIColor.white.withAlphaComponent(0.8)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let brandLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = UIColor.white.withAlphaComponent(0.7)
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let defaultBadge: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        view.layer.cornerRadius = CornerRadius.small
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private let defaultBadgeLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.title2XS.font
        label.textColor = .white
        label.text = "creditCards.cell.default".localized
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let infoLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = Colors.gray100
        layer.cornerRadius = CornerRadius.extraLarge
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(cardPreview)
        cardPreview.addSubview(cardNameLabel)
        cardPreview.addSubview(lastFourLabel)
        cardPreview.addSubview(brandLabel)
        defaultBadge.addSubview(defaultBadgeLabel)
        cardPreview.addSubview(defaultBadge)
        addSubview(infoLabel)

        NSLayoutConstraint.activate([
            cardPreview.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.spacing3),
            cardPreview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing3),
            cardPreview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing3),
            cardPreview.heightAnchor.constraint(equalToConstant: 100),

            cardNameLabel.topAnchor.constraint(equalTo: cardPreview.topAnchor, constant: Metrics.spacing4),
            cardNameLabel.leadingAnchor.constraint(equalTo: cardPreview.leadingAnchor, constant: Metrics.spacing4),

            defaultBadge.centerYAnchor.constraint(equalTo: cardNameLabel.centerYAnchor),
            defaultBadge.trailingAnchor.constraint(equalTo: cardPreview.trailingAnchor, constant: -Metrics.spacing4),

            defaultBadgeLabel.topAnchor.constraint(equalTo: defaultBadge.topAnchor, constant: Metrics.spacing1),
            defaultBadgeLabel.bottomAnchor.constraint(equalTo: defaultBadge.bottomAnchor, constant: -Metrics.spacing1),
            defaultBadgeLabel.leadingAnchor.constraint(equalTo: defaultBadge.leadingAnchor, constant: Metrics.spacing2),
            defaultBadgeLabel.trailingAnchor.constraint(equalTo: defaultBadge.trailingAnchor, constant: -Metrics.spacing2),

            lastFourLabel.bottomAnchor.constraint(equalTo: cardPreview.bottomAnchor, constant: -Metrics.spacing4),
            lastFourLabel.leadingAnchor.constraint(equalTo: cardPreview.leadingAnchor, constant: Metrics.spacing4),

            brandLabel.bottomAnchor.constraint(equalTo: cardPreview.bottomAnchor, constant: -Metrics.spacing4),
            brandLabel.trailingAnchor.constraint(equalTo: cardPreview.trailingAnchor, constant: -Metrics.spacing4),

            infoLabel.topAnchor.constraint(equalTo: cardPreview.bottomAnchor, constant: Metrics.spacing3),
            infoLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            infoLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            infoLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.spacing3),
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        addGestureRecognizer(longPress)
    }

    func configure(with card: CreditCard) {
        cardNameLabel.text = card.name.uppercased()
        lastFourLabel.text = "**** **** **** \(card.lastFourDigits)"
        brandLabel.text = card.cardBrand.displayName
        defaultBadge.isHidden = !card.isDefault

        // Gradient background
        let gradient = CAGradientLayer()
        gradient.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width - 2 * (Metrics.spacing4 + Metrics.spacing3), height: 100)
        gradient.colors = [card.cardColor.startColor.cgColor, card.cardColor.endColor.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.cornerRadius = CornerRadius.extraLarge
        cardPreview.layer.sublayers?.removeAll(where: { $0 is CAGradientLayer })
        cardPreview.layer.insertSublayer(gradient, at: 0)

        let closesText = String(format: "creditCards.cell.closes".localized, "\(card.closingDay)")
        let dueText = String(format: "creditCards.cell.due".localized, "\(card.dueDay)")
        var info = "\(closesText) · \(dueText)"
        if let limit = card.creditLimit {
            let limitText = String(format: "creditCards.cell.limit".localized, limit.currencyString)
            info += " · \(limitText)"
        }
        infoLabel.text = info
    }

    @objc private func handleTap() { onTap?() }
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { onDelete?() }
    }
}
