//
//  SplashView.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

class SplashView: UIView {
    
    private let gradientLayer = Colors.gradientBlack
    
    let logoImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "appLogo"))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.insertSublayer(gradientLayer, at: 0)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
    
    private func setupView() {
        addSubview(logoImageView)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            logoImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            logoImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}
