//
//  CoachMarkReminderBanner.swift
//  Finova
//

import UIKit

/// The small strip that reminds a new user of a setup they left. It floats over the list rather than
/// pushing it down, and it asks for nothing: `CoachMarkGating.reminderGuide` decides when it shows.
final class CoachMarkReminderBanner: UIView {
    var onOpen: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let openButton = UIButton(type: .system)
    private let dismissButton = UIButton(type: .system)

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Colors.gray100
        layer.cornerRadius = CornerRadius.extraLarge
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 2)

        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.contentHorizontalAlignment = .leading
        openButton.titleLabel?.font = Fonts.textSMBold.font
        openButton.titleLabel?.numberOfLines = 2
        openButton.setTitle(title, for: .normal)
        openButton.setTitleColor(Colors.gray700, for: .normal)
        openButton.addAction(UIAction { [weak self] _ in self?.onOpen?() }, for: .touchUpInside)

        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        dismissButton.tintColor = Colors.gray500
        dismissButton.accessibilityLabel = "coachMarks.reminder.dismiss".localized
        dismissButton.addAction(UIAction { [weak self] _ in self?.onDismiss?() }, for: .touchUpInside)

        addSubview(openButton)
        addSubview(dismissButton)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            openButton.topAnchor.constraint(equalTo: topAnchor),
            openButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            openButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            openButton.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor),
            dismissButton.topAnchor.constraint(equalTo: topAnchor),
            dismissButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 44),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension Input {
    /// Marks this field as a guide's target, and tells the guide when it has been filled in.
    func reportCoachMarkFill(as target: CoachMarkTarget) {
        accessibilityIdentifier = target.rawValue
        textField.addAction(
            UIAction { [weak self] _ in
                guard self?.textField.text?.isEmpty == false else { return }
                CoachMarkCenter.shared.post(.fieldFilled(target))
            }, for: .editingDidEnd)
    }
}
