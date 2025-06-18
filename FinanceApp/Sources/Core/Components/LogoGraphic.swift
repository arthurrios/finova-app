//
//  LogoGraphic.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

class LogoGraphic: UIView {
    let loginImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "loginImage")
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    init () {
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        addSubview(loginImageView)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            loginImageView.topAnchor.constraint(equalTo: topAnchor),
            loginImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            loginImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            loginImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            loginImageView.heightAnchor.constraint(equalToConstant: Metrics.loginHeroHeight)
        ])
    }
}
