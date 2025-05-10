//
//  Avatar.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation
import UIKit

class Avatar: UIView {
    
    var userImage: UIImage? {
         didSet { updateAvatarView() }
     }
    
    let userImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.clipsToBounds = true
        imageView.heightAnchor.constraint(equalToConstant: Metrics.profileImageSize).isActive = true
        imageView.widthAnchor.constraint(equalToConstant: Metrics.profileImageSize).isActive = true
        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    let userIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFit
        imageView.heightAnchor.constraint(equalToConstant: Metrics.profileIconSize).isActive = true
        imageView.widthAnchor.constraint(equalToConstant: Metrics.profileIconSize).isActive = true
        imageView.image = UIImage(named: "user")
        imageView.tintColor = Colors.gray500
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    init(userImage: UIImage? = nil) {
        self.userImage = userImage
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        layer.borderWidth = 1
        backgroundColor = Colors.gray300
        layer.borderColor = Colors.gray700.cgColor
        layer.masksToBounds = true
        isUserInteractionEnabled = true
        translatesAutoresizingMaskIntoConstraints = false
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        subviews.forEach { $0.removeFromSuperview() }
              NSLayoutConstraint.deactivate(constraints)
        
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Metrics.profileImageSize),
            heightAnchor.constraint(equalToConstant: Metrics.profileImageSize)
        ])
        
        if let img = userImage {
            userImageView.image = img
            addSubview(userImageView)
            
            NSLayoutConstraint.activate([
                userImageView.topAnchor.constraint(equalTo: topAnchor),
                userImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
                userImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                userImageView.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        } else {
            addSubview(userIconView)
            
            NSLayoutConstraint.activate([
                userIconView.centerXAnchor.constraint(equalTo: centerXAnchor),
                userIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                userIconView.widthAnchor.constraint(equalToConstant: Metrics.profileIconSize),
                userIconView.heightAnchor.constraint(equalToConstant: Metrics.profileIconSize)
            ])
        }
    }
    
    private func updateAvatarView() {
        subviews.forEach { $0.removeFromSuperview() }
        NSLayoutConstraint.deactivate(constraints)
        
        setupConstraints()
        
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = frame.size.width / 2
    }
}
