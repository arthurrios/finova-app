//
//  View+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 08/05/25.
//

import Foundation
import UIKit

extension UIView {
    func pinToEdges(of superview: UIView,
                    top: CGFloat? = nil,
                    leading: CGFloat? = nil,
                    bottom: CGFloat? = nil,
                    trailing: CGFloat? = nil) {
        translatesAutoresizingMaskIntoConstraints = false
        if let top = top {
            topAnchor.constraint(equalTo: superview.topAnchor, constant: top).isActive = true
        }
        if let leading = leading {
            leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: leading).isActive = true
        }
        if let bottom = bottom {
            bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: -bottom).isActive = true
        }
        if let trailing = trailing {
            trailingAnchor.constraint(equalTo: superview.trailingAnchor, constant: -trailing).isActive = true
        }
    }
    
    func pinToSuperview(with insets: UIEdgeInsets = .zero) {
            guard let superview = self.superview else {
                fatalError("pinToSuperview(): no superview for \(self)")
            }
            translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                topAnchor.constraint(equalTo: superview.topAnchor, constant: insets.top),
                leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: insets.left),
                trailingAnchor.constraint(equalTo: superview.trailingAnchor, constant: -insets.right),
                bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: -insets.bottom)
            ])
        }
}
