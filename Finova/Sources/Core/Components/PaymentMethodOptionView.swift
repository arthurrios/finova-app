//
//  PaymentMethodOptionView.swift
//  Finova
//

import UIKit

final class PaymentMethodOptionView: UIView {
    var onTap: (() -> Void)?

    private(set) var isSelectedOption: Bool = false

    private let radioView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 10
        view.layer.borderWidth = 2
        view.layer.borderColor = Colors.gray400.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let radioFill: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 5
        view.backgroundColor = Colors.mainMagenta
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSMBold.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        titleLabel.text = title
        subtitleLabel.text = subtitle
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = Colors.gray200
        layer.cornerRadius = CornerRadius.large
        layer.borderWidth = 1
        layer.borderColor = Colors.gray300.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(radioView)
        radioView.addSubview(radioFill)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Metrics.inputHeight),

            radioView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            radioView.centerYAnchor.constraint(equalTo: centerYAnchor),
            radioView.widthAnchor.constraint(equalToConstant: 20),
            radioView.heightAnchor.constraint(equalToConstant: 20),

            radioFill.centerXAnchor.constraint(equalTo: radioView.centerXAnchor),
            radioFill.centerYAnchor.constraint(equalTo: radioView.centerYAnchor),
            radioFill.widthAnchor.constraint(equalToConstant: 10),
            radioFill.heightAnchor.constraint(equalToConstant: 10),

            textStack.leadingAnchor.constraint(equalTo: radioView.trailingAnchor, constant: Metrics.spacing3),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
    }

    @objc private func tapped() { onTap?() }

    /// For options whose subtitle is only known after construction — a card's name and last four
    /// digits, for instance, which depend on which series the screen was opened for.
    func setSubtitle(_ subtitle: String) {
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty
    }

    func setSelected(_ selected: Bool) {
        isSelectedOption = selected
        radioFill.isHidden = !selected
        radioView.layer.borderColor = selected ? Colors.mainMagenta.cgColor : Colors.gray400.cgColor
        layer.borderColor = selected ? Colors.mainMagenta.cgColor : Colors.gray300.cgColor
    }
}
