//
//  AllocationTagEditView.swift
//  Finova
//
//  Created by Arthur Rios on 04/08/26.
//

import UIKit

final class AllocationTagEditView: UIView {

    weak var delegate: AllocationTagEditViewDelegate?

    /// The assets offered as tag icons. The whole `lucide_icon*` set the app already ships, in the
    /// order categories are declared, with the default glyph first. No new artwork.
    static let iconAssetNames: [String] = {
        let candidates = TransactionCategory.allCases.map { $0.iconName }
        var seen = Set<String>()
        // `iconName` falls back to lucide_iconDollar for cases with no asset, so dedupe rather than
        // showing the dollar glyph three times.
        return candidates.filter { seen.insert($0).inserted }
    }()

    private(set) var selectedColorIndex: Int = 0
    /// `nil` means the default glyph.
    private(set) var selectedIconAssetName: String?

    private var colorButtons: [UIButton] = []
    private var iconButtons: [UIButton] = []

    // MARK: - Header

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

    private lazy var backButtonGlassContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.text = "allocationTags.edit.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Fields

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = false
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.layer.borderWidth = 1
        view.layer.borderColor = Colors.gray300.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let nameInput = ValidatedInput(
        type: .name, placeholder: "allocationTags.create.namePlaceholder".localized)

    /// A display name the user types to replace a bad machine translation.
    ///
    /// A plain `Input`, not a `ValidatedInput`: there is nothing to validate, and empty is a
    /// meaningful value rather than an error - it means "use the automatic translation".
    ///
    /// The trick that makes this explain itself without extra chrome is the **placeholder**: it holds
    /// the current machine translation, so an untouched field shows the automatic result in grey, and
    /// a set override shows in normal dark input text. The difference between "what the machine did"
    /// and "what I wrote" is visible without a word of instruction.
    let translatedNameInput = Input(placeholder: "")

    private let translatedNameLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray600
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let translationNoteLabel: UILabel = {
        let label = UILabel()
        label.text = "allocationTags.edit.translation.note".localized
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Only shown once an override exists. Clearing the field does the same thing, but that is
    /// discoverable rather than obvious, and reverting a generated result should be easy to find.
    let resetTranslationButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        // Set through the configuration, not `titleLabel.font`: a UIButton.Configuration rebuilds the
        // title from its own attributes and silently discards a font assigned to the label, which
        // renders this at the 17pt system default next to textXS body copy.
        configuration.attributedTitle = AttributedString(
            "allocationTags.edit.translation.reset".localized,
            attributes: AttributeContainer([.font: Fonts.textXS.font]))
        configuration.baseForegroundColor = Colors.mainMagenta
        // Padding to a 44pt target: at textXS this is otherwise a sub-minimum tap area.
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 12, leading: 0, bottom: 12, trailing: 0)
        let button = UIButton(configuration: configuration)
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.contentHorizontalAlignment = .trailing
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()

    private lazy var translationSection: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [
            translatedNameLabel, translatedNameInput, translationNoteLabel, resetTranslationButton,
        ])
        stack.axis = .vertical
        stack.spacing = Metrics.spacing2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        return stack
    }()

    private let colorStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Metrics.spacing3
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// Scrolls, unlike the colour row: 27-odd icons cannot fit across a phone at a tappable size. It
    /// stays a `UIStackView` of buttons - the app has no grid pickers, and this is not the place to
    /// introduce one.
    private let iconScrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private let iconStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Metrics.spacing3
        // `.fill` with fixed widths, never `.fillEqually` - that would squash 20+ buttons into the
        // visible width instead of letting the scroll view do its job.
        stack.distribution = .fill
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var categoriesRow: UIControl = {
        let row = UIControl()
        row.backgroundColor = Colors.gray200
        row.layer.cornerRadius = CornerRadius.medium
        row.layer.borderWidth = 1
        row.layer.borderColor = Colors.gray300.cgColor
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: Metrics.inputHeight).isActive = true

        let title = UILabel()
        title.text = "allocationTags.edit.categories.row".localized
        title.font = Fonts.textSM.font
        title.textColor = Colors.gray700
        title.translatesAutoresizingMaskIntoConstraints = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = Colors.gray400
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(title)
        row.addSubview(categoryCountLabel)
        row.addSubview(chevron)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Metrics.spacing4),
            title.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Metrics.spacing4),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12),

            categoryCountLabel.trailingAnchor.constraint(
                equalTo: chevron.leadingAnchor, constant: -Metrics.spacing2),
            categoryCountLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        row.addTarget(self, action: #selector(categoriesTapped), for: .touchUpInside)
        return row
    }()

    private let categoryCountLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Restyled to red after init rather than using `Button(variant: .outlined)` as-is: that variant
    /// hardcodes `mainMagenta`, and a destructive action must not wear the brand's primary colour. The
    /// app has no destructive `Button` variant, and `GroupDetailsView` solves the same problem the same
    /// way - `Colors.mainRed` applied at the call site.
    let deleteButton: Button = {
        let button = Button(
            variant: .outlined, label: "allocationTags.edit.delete.button".localized)
        button.setTitleColor(Colors.mainRed, for: .normal)
        button.layer.borderColor = Colors.mainRed.cgColor
        button.backgroundColor = Colors.lightRed
        return button
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colors.gray200
        setupView()
        setupLayout()
        buildColorSelector()
        buildIconSelector()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButtonGlassContainer)
        backButtonGlassContainer.addSubview(backButton)
        headerItemsView.addSubview(headerTitleLabel)

        addSubview(scrollView)
        scrollView.addSubview(cardView)

        iconScrollView.addSubview(iconStackView)

        let fieldsStack = UIStackView(arrangedSubviews: [
            labeledField(label: "allocationTags.edit.input.name".localized, field: nameInput),
            // Right after Name: it is a naming concern, and the two fields only make sense read
            // together - one is what you typed, the other is what gets shown.
            translationSection,
            labeledField(label: "allocationTags.edit.input.color".localized, field: colorStackView),
            labeledField(label: "allocationTags.edit.input.icon".localized, field: iconScrollView),
            categoriesRow,
            deleteButton,
        ])
        fieldsStack.axis = .vertical
        fieldsStack.spacing = Metrics.spacing5
        fieldsStack.translatesAutoresizingMaskIntoConstraints = false
        fieldsStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing5, leading: Metrics.spacing5, bottom: Metrics.spacing5,
            trailing: Metrics.spacing5)
        fieldsStack.isLayoutMarginsRelativeArrangement = true
        cardView.addSubview(fieldsStack)
        fieldsStack.pinToSuperview()

        if #available(iOS 26.0, *) {
            let backGlass = UIGlassEffect(style: .clear)
            backGlass.isInteractive = true
            let backGlassView = UIVisualEffectView(effect: backGlass)
            backGlassView.translatesAutoresizingMaskIntoConstraints = false
            backButtonGlassContainer.insertSubview(backGlassView, at: 0)
            backGlassView.pinToSuperview()
            backButtonGlassContainer.layer.cornerRadius = 18
            backButtonGlassContainer.clipsToBounds = true
        }

        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        nameInput.textField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        translatedNameInput.textField.addTarget(
            self, action: #selector(translatedNameChanged), for: .editingChanged)
        resetTranslationButton.addTarget(
            self, action: #selector(resetTranslationTapped), for: .touchUpInside)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),

            backButtonGlassContainer.topAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
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
            headerTitleLabel.centerYAnchor.constraint(
                equalTo: backButtonGlassContainer.centerYAnchor),
            headerTitleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: headerItemsView.layoutMarginsGuide.trailingAnchor),

            scrollView.topAnchor.constraint(
                equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),

            cardView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            cardView.leadingAnchor.constraint(
                equalTo: scrollView.leadingAnchor, constant: Metrics.spacing4),
            cardView.trailingAnchor.constraint(
                equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing4),
            cardView.bottomAnchor.constraint(
                equalTo: scrollView.bottomAnchor, constant: -Metrics.spacing6),
            cardView.widthAnchor.constraint(
                equalTo: scrollView.widthAnchor, constant: -Metrics.spacing8),

            nameInput.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.inputHeight),
            translatedNameInput.heightAnchor.constraint(
                greaterThanOrEqualToConstant: Metrics.inputHeight),

            iconScrollView.heightAnchor.constraint(equalToConstant: 32),
            iconStackView.topAnchor.constraint(equalTo: iconScrollView.topAnchor),
            iconStackView.bottomAnchor.constraint(equalTo: iconScrollView.bottomAnchor),
            iconStackView.leadingAnchor.constraint(equalTo: iconScrollView.leadingAnchor),
            iconStackView.trailingAnchor.constraint(equalTo: iconScrollView.trailingAnchor),
            iconStackView.heightAnchor.constraint(equalTo: iconScrollView.heightAnchor),
        ])
    }

    private func labeledField(label: String, field: UIView) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = label
        titleLabel.font = Fonts.textSM.font
        titleLabel.textColor = Colors.gray600
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [titleLabel, field])
        stack.axis = .vertical
        stack.spacing = Metrics.spacing2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    // MARK: - Selectors

    private func buildColorSelector() {
        for index in 0..<AllocationTagPalette.count {
            let button = UIButton()
            // The `ink` tone, not `arc`: this form sits on gray100, and the bright ring tones are
            // built for the dark card.
            button.backgroundColor = AllocationTagPalette.entry(at: index).ink
            button.layer.cornerRadius = 16
            button.clipsToBounds = true
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
            button.tag = index
            button.accessibilityLabel = AllocationTagPalette.entry(at: index).name
            button.addTarget(self, action: #selector(colorSelected(_:)), for: .touchUpInside)
            colorButtons.append(button)
            colorStackView.addArrangedSubview(button)
        }
        refreshColorSelection()
    }

    private func buildIconSelector() {
        // Index 0 is the default glyph; the rest map onto `iconAssetNames` by offset.
        let defaultButton = makeIconButton(
            image: UIImage(systemName: AllocationTag.defaultSymbolName), tag: 0)
        iconButtons.append(defaultButton)
        iconStackView.addArrangedSubview(defaultButton)

        for (offset, assetName) in Self.iconAssetNames.enumerated() {
            let button = makeIconButton(
                image: UIImage(named: assetName)?.withRenderingMode(.alwaysTemplate),
                tag: offset + 1)
            iconButtons.append(button)
            iconStackView.addArrangedSubview(button)
        }
        refreshIconSelection()
    }

    private func makeIconButton(image: UIImage?, tag: Int) -> UIButton {
        let button = UIButton()
        button.setImage(image, for: .normal)
        button.tintColor = Colors.gray500
        button.backgroundColor = Colors.gray200
        button.layer.cornerRadius = 16
        button.layer.borderWidth = 1
        button.layer.borderColor = Colors.gray300.cgColor
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.tag = tag
        button.addTarget(self, action: #selector(iconSelected(_:)), for: .touchUpInside)
        return button
    }

    @objc private func colorSelected(_ sender: UIButton) {
        selectedColorIndex = sender.tag
        refreshColorSelection()
        delegate?.didChangeColorIndex(selectedColorIndex)
    }

    @objc private func iconSelected(_ sender: UIButton) {
        selectedIconAssetName = sender.tag == 0 ? nil : Self.iconAssetNames[sender.tag - 1]
        refreshIconSelection()
        delegate?.didChangeIconAssetName(selectedIconAssetName)
    }

    /// Same 3pt magenta ring the credit-card colour row uses, so selection reads identically.
    private func refreshColorSelection() {
        for button in colorButtons {
            let isSelected = button.tag == selectedColorIndex
            button.layer.borderWidth = isSelected ? 3 : 0
            button.layer.borderColor = isSelected ? Colors.mainMagenta.cgColor : nil
        }
    }

    private func refreshIconSelection() {
        let selectedTag =
            selectedIconAssetName.flatMap { Self.iconAssetNames.firstIndex(of: $0).map { $0 + 1 } } ?? 0
        for button in iconButtons {
            let isSelected = button.tag == selectedTag
            button.layer.borderWidth = isSelected ? 3 : 1
            button.layer.borderColor =
                isSelected ? Colors.mainMagenta.cgColor : Colors.gray300.cgColor
            button.tintColor = isSelected ? Colors.mainMagenta : Colors.gray500
        }
    }

    // MARK: - Configuration

    func configure(with tag: AllocationTag, categoryCount: Int) {
        nameInput.textField.text = tag.name
        selectedColorIndex = AllocationTagPalette.clampIndex(tag.colorIndex)
        selectedIconAssetName = tag.iconAssetName
        refreshColorSelection()
        refreshIconSelection()
        updateCategoryCount(categoryCount)
    }

    func updateCategoryCount(_ count: Int) {
        categoryCountLabel.text = "\(count)"
    }

    /// Shows or hides the "shown in <language>" field.
    ///
    /// - Parameters:
    ///   - languageName: the phone's language, for the field's label.
    ///   - automaticName: what the tag would be called with no override - the placeholder.
    ///   - override: what the user typed, if anything.
    func configureTranslation(languageName: String, automaticName: String, override: String?) {
        translationSection.isHidden = false
        translatedNameLabel.text = String(
            format: "allocationTags.edit.input.translatedName".localized, languageName)
        translatedNameInput.textField.placeholder = automaticName
        translatedNameInput.textField.text = override
        translatedNameInput.textField.accessibilityLabel = translatedNameLabel.text
        resetTranslationButton.isHidden = (override ?? "").isEmpty
    }

    func hideTranslationField() {
        translationSection.isHidden = true
    }

    var isTranslationFieldHidden: Bool { translationSection.isHidden }

    /// Called as the user types, so the revert affordance appears the moment there is something to
    /// revert rather than only after the edit is committed.
    func refreshResetTranslationButton() {
        let text = translatedNameInput.textField.text ?? ""
        resetTranslationButton.isHidden = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func clearTranslationOverride() {
        translatedNameInput.textField.text = ""
        refreshResetTranslationButton()
    }

    @objc private func backTapped() { delegate?.didTapBackButton() }
    @objc private func deleteTapped() { delegate?.didTapDeleteTag() }
    @objc private func categoriesTapped() { delegate?.didTapCategories() }
    @objc private func nameChanged() {
        delegate?.didChangeName(nameInput.textField.text ?? "")
    }

    @objc private func translatedNameChanged() {
        refreshResetTranslationButton()
    }

    @objc private func resetTranslationTapped() {
        clearTranslationOverride()
        delegate?.didResetTranslationOverride()
    }
}
