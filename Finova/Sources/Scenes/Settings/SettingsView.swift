//
//  SettingsView.swift
//  Finova
//
//  Created by Arthur Rios on 17/07/25.
//

import UIKit

final class SettingsView: UIView {
    weak var delegate: SettingsViewDelegate?
    
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Metrics.spacing4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Metrics.settingsHeaderHeight).isActive = true
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
        
        if let originalImage = UIImage(named: "chevronLeft") {
            let size = CGSize(width: Metrics.backButtonSize, height: Metrics.backButtonSize)
            UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
            originalImage.draw(in: CGRect(origin: .zero, size: size))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            button.setImage(resizedImage, for: .normal)
        } else {
            button.setImage(UIImage(named: "chevronLeft"), for: .normal)
        }
        
        button.imageView?.contentMode = .scaleAspectFit
        button.tintColor = Colors.gray500
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.text = "settings.header.title".localized
        label.applyStyle()
        label.textColor = Colors.gray700
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Security Section
    private let securityHeaderView = createSectionHeader(title: "settings.section.security".localized)
    
    let biometricContainer = createSettingContainer()
    private let biometricIconView = createIconView(imageName: "faceid")
    let biometricLabel = createSettingLabel(text: "Face ID / Touch ID")
    let biometricSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.onTintColor = Colors.mainMagenta
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }()
    
    // About Section
    private let aboutHeaderView = createSectionHeader(title: "settings.section.about".localized)
    
    private let versionContainer = createSettingContainer()
    private let versionIconView = createIconView(imageName: "info.circle")
    private let versionTitleLabel = createSettingLabel(text: "settings.version.title".localized)
    let versionLabel = createDetailLabel(text: "1.0.1")
    
    override init(frame: CGRect) {
        super.init(frame: .zero)
        setupView()
        setupActions()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        backgroundColor = Colors.gray200
        
        backButton.addTarget(self, action: #selector(handleDidTapBackButton), for: .touchUpInside)
        
        addSubview(scrollView)
        scrollView.addSubview(headerContainerView)
        scrollView.addSubview(contentStackView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButton)
        headerItemsView.addSubview(headerTitleLabel)
        
        setupSections()
        setupConstraints()
    }
    
    private func setupSections() {
        // Security section
        contentStackView.addArrangedSubview(securityHeaderView)
        setupBiometricContainer()
        contentStackView.addArrangedSubview(biometricContainer)
        
        // About section
        contentStackView.addArrangedSubview(aboutHeaderView)
        setupVersionContainer()
        contentStackView.addArrangedSubview(versionContainer)
    }
    
    private func setupBiometricContainer() {
        biometricContainer.addSubview(biometricIconView)
        biometricContainer.addSubview(biometricLabel)
        biometricContainer.addSubview(biometricSwitch)
        
        NSLayoutConstraint.activate([
            biometricIconView.leadingAnchor.constraint(equalTo: biometricContainer.leadingAnchor, constant: Metrics.spacing4),
            biometricIconView.centerYAnchor.constraint(equalTo: biometricContainer.centerYAnchor),
            
            biometricLabel.leadingAnchor.constraint(equalTo: biometricIconView.trailingAnchor, constant: Metrics.spacing3),
            biometricLabel.centerYAnchor.constraint(equalTo: biometricContainer.centerYAnchor),
            
            biometricSwitch.trailingAnchor.constraint(equalTo: biometricContainer.trailingAnchor, constant: -Metrics.spacing4),
            biometricSwitch.centerYAnchor.constraint(equalTo: biometricContainer.centerYAnchor)
        ])
    }
    
    private func setupVersionContainer() {
        versionContainer.addSubview(versionIconView)
        versionContainer.addSubview(versionTitleLabel)
        versionContainer.addSubview(versionLabel)
        
        NSLayoutConstraint.activate([
            versionIconView.leadingAnchor.constraint(equalTo: versionContainer.leadingAnchor, constant: Metrics.spacing4),
            versionIconView.centerYAnchor.constraint(equalTo: versionContainer.centerYAnchor),
            
            versionTitleLabel.leadingAnchor.constraint(equalTo: versionIconView.trailingAnchor, constant: Metrics.spacing3),
            versionTitleLabel.centerYAnchor.constraint(equalTo: versionContainer.centerYAnchor),
            
            versionLabel.trailingAnchor.constraint(equalTo: versionContainer.trailingAnchor, constant: -Metrics.spacing4),
            versionLabel.centerYAnchor.constraint(equalTo: versionContainer.centerYAnchor)
        ])
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            
            headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            
            backButton.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
            backButton.leadingAnchor.constraint(
                equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
            
            headerTitleLabel.leadingAnchor.constraint(
                equalTo: backButton.trailingAnchor, constant: Metrics.spacing4),
            headerTitleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            
            contentStackView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing4),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Metrics.spacing4),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Metrics.spacing4),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: Metrics.spacing4),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -2 * Metrics.spacing4)
        ])
    }
    
    private func setupActions() {
        biometricSwitch.addTarget(self, action: #selector(biometricToggled), for: .valueChanged)
    }
    
    @objc
    private func biometricToggled() {
        delegate?.didToggleBiometric(biometricSwitch.isOn)
    }
    
    @objc
    private func handleDidTapBackButton() {
        delegate?.handleDidTapBackButton()
    }
}


// MARK: - Factory Methods
extension SettingsView {
    
    private static func createSectionHeader(title: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.text = title.uppercased()
        label.font = Fonts.textXS.font
        label.textColor = Colors.gray500
        label.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.spacing2),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.spacing3),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        return container
    }
    
    private static func createSettingContainer() -> UIView {
        let container = UIView()
        container.backgroundColor = Colors.gray100
        container.layer.cornerRadius = CornerRadius.large
        container.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 56)
        ])
        
        return container
    }
    
    private static func createIconView(imageName: String, tintColor: UIColor = Colors.gray600) -> UIImageView {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: imageName)
        imageView.tintColor = tintColor
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: 20),
            imageView.widthAnchor.constraint(equalToConstant: 20)
        ])
        
        return imageView
    }
    
    private static func createSettingLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Fonts.titleSM.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private static func createDetailLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private static func createChevronView() -> UIImageView {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "chevron.right")
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = Colors.gray400
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: 12),
            imageView.widthAnchor.constraint(equalToConstant: 12)
        ])
        
        return imageView
    }
}
