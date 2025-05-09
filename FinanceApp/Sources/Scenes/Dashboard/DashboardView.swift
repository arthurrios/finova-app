//
//  DashboardView.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation
import UIKit

final class DashboardView: UIView {
    public weak var delegate: DashboardViewDelegate?
    
    let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight).isActive = true
        return view
    }()
    
    let headerItemsView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: Metrics.spacing3, leading: Metrics.spacing5, bottom: Metrics.spacing6, trailing: Metrics.spacing5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let avatar = Avatar()
    
    let welcomeTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.textColor = Colors.gray700
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let welcomeSubtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.text = "dashboard.welcomeSubtitle".localized
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init (frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func configure(userName: String) {
        welcomeTitleLabel.text = "dashboard.welcomeTitle".localized + "\(userName)!"
        welcomeTitleLabel.applyStyle()
    }
    
    private func setupView() {
        backgroundColor = Colors.gray200
        
        
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(avatar)
        headerItemsView.addSubview(welcomeTitleLabel)
        headerItemsView.addSubview(welcomeSubtitleLabel)
        
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
            
            avatar.leadingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
            avatar.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
            
            welcomeTitleLabel.topAnchor.constraint(equalTo: avatar.topAnchor),
            welcomeTitleLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: Metrics.spacing3),
            
            welcomeSubtitleLabel.topAnchor.constraint(equalTo: welcomeTitleLabel.bottomAnchor, constant: Metrics.spacing1),
            welcomeSubtitleLabel.leadingAnchor.constraint(equalTo: welcomeTitleLabel.leadingAnchor),
        ])
    }
}
