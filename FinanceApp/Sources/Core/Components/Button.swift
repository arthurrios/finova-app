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
    enum ButtonVariant {
        case base
        case outlined
    }
    
    public weak var delegate: ButtonDelegate?
    var variant: ButtonVariant? = .base
    var label: String
        
    init(variant: ButtonVariant? = .base, label: String) {
        self.variant = variant
        self.label = label
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 8
        addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        heightAnchor.constraint(equalToConstant: Metrics.buttonHeight).isActive = true
        titleLabel?.font = Fonts.buttonMD.font
        setTitle(label, for: .normal)
        layer.masksToBounds = true

        switch variant {
            case .base:
            setTitleColor(Colors.gray100, for: .normal)
            backgroundColor = Colors.mainMagenta
            break
        case .outlined:
            setTitleColor(Colors.mainMagenta, for: .normal)
            layer.borderWidth = 1
            layer.borderColor = Colors.mainMagenta.cgColor
            backgroundColor = Colors.lowMagenta
        case .none:
            break
        }
    }
    
    @objc
    private func buttonTapped() {
        delegate?.buttonAction()
    }
}
