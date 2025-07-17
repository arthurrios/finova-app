//
//  SettingsView.swift
//  Finova
//
//  Created by Arthur Rios on 17/07/25.
//

import UIKit

final class SettingsView: UIView {
    weak var delegate: SettingsViewDelegate?
    
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
    
    override init(frame: CGRect) {
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        backgroundColor = Colors.gray200
        
        backButton.addTarget(self, action: #selector(handleDidTapBackButton), for: .touchUpInside)
        
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(backButton)
        headerItemsView.addSubview(headerTitleLabel)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
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
        ])
    }
    
    @objc
    private func handleDidTapBackButton() {
        delegate?.handleDidTapBackButton()
    }
}
