//
//  RegisterView.swift
//  FinanceApp
//
//  Created by Arthur Rios on 19/06/25.
//

import Foundation
import UIKit

final class RegisterView: UIView {
    public weak var delegate: RegisterViewDelegate?
    
    let containerView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Metrics.spacing10,
            leading: Metrics.spacing8,
            bottom: Metrics.spacing3,
            trailing: Metrics.spacing8)
        view.layer.opacity = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let appLogoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "appLogo")
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
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
        addSubview(containerView)
        containerView.addSubview(appLogoImageView)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: Metrics.spacing8),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            
            appLogoImageView.topAnchor.constraint(equalTo: containerView.layoutMarginsGuide.topAnchor),
            appLogoImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            appLogoImageView.heightAnchor.constraint(equalToConstant: 80),
            appLogoImageView.widthAnchor.constraint(equalToConstant: 80)
        ])
    }
}
