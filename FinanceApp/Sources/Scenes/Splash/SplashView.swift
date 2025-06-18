//
//  SplashView.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

class SplashView: UIView {
    
    let logoImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "appLogo"))
        imageView.contentMode = .scaleAspectFit
        imageView.alpha = 0
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    let loginImageView = LogoGraphic()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        loginImageView.alpha = 0
        loginImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(logoImageView)
        addSubview(loginImageView)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            logoImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            logoImageView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -Metrics.spacing6),
            
            loginImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing3),
            loginImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing3)
        ])
    }
}
