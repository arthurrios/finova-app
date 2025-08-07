//
//  FloatingActionButton.swift
//  Finova
//
//  Created by Arthur Rios on 01/08/25.
//

import UIKit

final class FloatingActionButton: UIButton {
    
    // MARK: - Properties
    weak var delegate: CustomTabBarControllerDelegate?
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupButton()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupButton() {
        // Set the plus icon with proper white tint
        if let originalImage = UIImage(named: "plus") {
            let newSize = CGSize(width: 28, height: 28) // Bigger icon
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
            originalImage.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            // Apply white tint to the image
            let whiteImage = resizedImage?.withTintColor(Colors.gray100, renderingMode: .alwaysOriginal)
            setImage(whiteImage, for: .normal)
        }
        
        // Configure button appearance
        tintColor = Colors.gray100
        backgroundColor = Colors.darkMagenta
        
        // Configure image view
        imageView?.contentMode = .center
        imageView?.tintColor = Colors.gray100
        
        // Make it circular for the main shape - smaller size
        layer.cornerRadius = 28
        
        // Add shadow for elevation
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 6)
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 8
        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
        
        // Add target action
        addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        
        // Enable auto layout
        translatesAutoresizingMaskIntoConstraints = false
    }
    
    // MARK: - Actions
    @objc
    private func buttonTapped() {
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Notify delegate
        delegate?.didTapFloatingActionButton()
    }
}
