//
//  CoachMarkGuidesViewController.swift
//  Finova
//

import UIKit

protocol CoachMarkGuidesFlowDelegate: AnyObject {
    func dismissGuides()
}

/// Every guide, for anyone, at any time. A row starts its guide on the dashboard; a checkmark says
/// the setup behind it is done, not that the row is used up.
final class CoachMarkGuidesViewController: UIViewController {
    weak var flowDelegate: CoachMarkGuidesFlowDelegate?

    private let contentView = CoachMarkGuidesView()

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
        contentView.onBack = { [weak self] in self?.flowDelegate?.dismissGuides() }
        contentView.onSelect = { guide in CoachMarkCenter.shared.startReplay(guide) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        contentView.reload { CoachMarkCenter.shared.isSetupDone($0) }
    }
}

final class CoachMarkGuidesView: UIView {
    var onBack: (() -> Void)?
    var onSelect: ((CoachMarkGuideID) -> Void)?

    private let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight - 12).isActive = true
        return view
    }()

    private let headerItemsView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing4, leading: Metrics.spacing5, bottom: Metrics.spacing5,
            trailing: Metrics.spacing5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronLeft")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 26.0, *) {
            button.tintColor = Colors.gray700
        } else {
            button.tintColor = Colors.gray500
        }
        return button
    }()

    private let backButtonGlassContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.text = "settings.guides.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private let rowsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing3
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var rows: [CoachMarkGuideID: CoachMarkGuideRow] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = Colors.gray200

        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        backButtonGlassContainer.applyClearGlass(cornerRadius: 18)
        headerItemsView.addSubview(headerTitleLabel)
        addSubview(scrollView)
        scrollView.addSubview(rowsStackView)

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.accessibilityLabel = "settings.guides.back".localized

        let footer = UILabel()
        footer.text = "settings.guides.footer".localized
        footer.font = Fonts.textXS.font
        footer.adjustsFontForContentSizeCategory = true
        footer.textColor = Colors.gray500
        footer.numberOfLines = 0

        for guide in CoachMarkGuideID.allCases {
            let row = CoachMarkGuideRow(guide: guide)
            row.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
            rows[guide] = row
            rowsStackView.addArrangedSubview(row)
        }
        rowsStackView.addArrangedSubview(footer)

        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

            backButtonGlassContainer.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
            backButtonGlassContainer.leadingAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
            backButtonGlassContainer.widthAnchor.constraint(equalToConstant: 36),
            backButtonGlassContainer.heightAnchor.constraint(equalToConstant: 36),

            backButton.topAnchor.constraint(equalTo: backButtonGlassContainer.topAnchor),
            backButton.leadingAnchor.constraint(equalTo: backButtonGlassContainer.leadingAnchor),
            backButton.trailingAnchor.constraint(equalTo: backButtonGlassContainer.trailingAnchor),
            backButton.bottomAnchor.constraint(equalTo: backButtonGlassContainer.bottomAnchor),

            headerTitleLabel.leadingAnchor.constraint(
                equalTo: backButtonGlassContainer.trailingAnchor, constant: Metrics.spacing4),
            headerTitleLabel.centerYAnchor.constraint(equalTo: backButtonGlassContainer.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            rowsStackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Metrics.spacing4),
            rowsStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Metrics.spacing4),
            rowsStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing4),
            rowsStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Metrics.spacing4),
            rowsStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * Metrics.spacing4),
        ])
    }

    func reload(isDone: (CoachMarkGuideID) -> Bool) {
        rows.forEach { guide, row in row.isDone = isDone(guide) }
    }

    @objc private func backTapped() {
        onBack?()
    }

    @objc private func rowTapped(_ sender: CoachMarkGuideRow) {
        onSelect?(sender.guide)
    }
}

/// A control rather than a tappable view, so VoiceOver and the highlight come for free.
private final class CoachMarkGuideRow: UIControl {
    let guide: CoachMarkGuideID

    var isDone = false {
        didSet {
            statusIcon.image = UIImage(systemName: isDone ? "checkmark.circle.fill" : "chevron.right")
            statusIcon.tintColor = isDone ? Colors.mainGreen : Colors.gray400
            accessibilityValue = isDone ? "settings.guides.done".localized : nil
        }
    }

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.titleSM.font
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Colors.gray700
        label.numberOfLines = 0
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textXS.font
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        return label
    }()

    private let statusIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        return imageView
    }()

    init(guide: CoachMarkGuideID) {
        self.guide = guide
        super.init(frame: .zero)

        backgroundColor = Colors.gray100
        layer.cornerRadius = CornerRadius.large
        titleLabel.text = guide.titleKey.localized
        subtitleLabel.text = guide.subtitleKey.localized
        accessibilityIdentifier = "coachMark.guides.\(guide.rawValue)"
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = titleLabel.text
        accessibilityHint = subtitleLabel.text

        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = Metrics.spacing1
        labels.isUserInteractionEnabled = false
        labels.translatesAutoresizingMaskIntoConstraints = false

        addSubview(labels)
        addSubview(statusIcon)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 56),

            labels.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.spacing3),
            labels.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.spacing3),
            labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            labels.trailingAnchor.constraint(equalTo: statusIcon.leadingAnchor, constant: -Metrics.spacing3),

            statusIcon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            statusIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 16),
            statusIcon.heightAnchor.constraint(equalToConstant: 16),
        ])
        defer { isDone = false }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }
}
