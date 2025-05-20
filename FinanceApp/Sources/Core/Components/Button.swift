//
//  Button.swift
//  FinanceApp
//
//  Created by Arthur Rios on 08/05/25.
//

import Foundation
import UIKit

public protocol ButtonDelegate: AnyObject {
    func buttonAction()
}

class Button: UIButton {
    enum ButtonVariant { case base, outlined, outlinedDisabled }
    
    var variant: ButtonVariant = .base {
        didSet { applyStyle() }
    }
    
    public weak var delegate: ButtonDelegate?
    var label: String
    
    init(variant: ButtonVariant = .base, label: String) {
        self.variant = variant
        self.label = label
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func applyStyle() {
        layer.borderWidth = 0
        layer.opacity = 1
        isEnabled = true
        
        switch variant {
        case .base:
            setTitleColor(Colors.gray100, for: .normal)
            backgroundColor = Colors.mainMagenta
            
        case .outlined:
            setTitleColor(Colors.mainMagenta, for: .normal)
            layer.borderWidth = 1
            layer.borderColor = Colors.mainMagenta.cgColor
            backgroundColor = Colors.lowMagenta
            
        case .outlinedDisabled:
            isEnabled = false
            setTitleColor(Colors.gray400, for: .disabled)
            layer.borderWidth = 1
            layer.borderColor = Colors.gray400.cgColor
            backgroundColor = Colors.gray600
            layer.opacity = 0.5
        }
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 8
        addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        heightAnchor.constraint(equalToConstant: Metrics.buttonHeight).isActive = true
        titleLabel?.font = Fonts.buttonMD.font
        setTitle(label, for: .normal)
        layer.masksToBounds = true
        
        applyStyle()
    }
    
    @objc
    private func buttonTapped() {
        delegate?.buttonAction()
    }
}
