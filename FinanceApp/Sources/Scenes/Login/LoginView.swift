//
//  LoginView.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

final class LoginView: UIView {
    
    let loginImageView = LogoGraphic()
    
    override init (frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        loginImageView.translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Colors.gray100
        addSubview(loginImageView)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            loginImageView.topAnchor.constraint(equalTo: topAnchor),
            loginImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing3),
            loginImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing3),
        ])
    }
}
