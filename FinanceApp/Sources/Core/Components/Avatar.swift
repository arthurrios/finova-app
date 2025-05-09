//
//  Avatar.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation
import UIKit

class Avatar: UIView {
    
    var userImage: UIImage?
    
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
    
    private func setupUserImage() {
        if userImage != nil {
            userImageView.image = userImage
            addSubview(userImageView)
        } else {
            addSubview(userIconView)
        }
    }
    
    private func setupView() {
        layer.borderWidth = 1
        backgroundColor = Colors.gray300
        layer.borderColor = Colors.gray700.cgColor
        layer.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        
        heightAnchor.constraint(equalToConstant: Metrics.profileImageSize).isActive = true
        widthAnchor.constraint(equalToConstant: Metrics.profileImageSize).isActive = true
        
        setupUserImage()
        setupConstraints()
    }
    
    private func setupConstraints() {
        let item = userImage != nil ? userImageView : userIconView
            NSLayoutConstraint.activate([
                item.centerXAnchor.constraint(equalTo: centerXAnchor),
                item.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = frame.size.width / 2
    }
}
