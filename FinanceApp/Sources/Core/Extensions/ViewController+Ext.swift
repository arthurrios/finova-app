//
//  ViewController+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

extension UIViewController {
    func setupContentViewToBounds(contentView: UIView, respectingSafeArea: Bool = true) {
        view.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        let top    = respectingSafeArea ? view.safeAreaLayoutGuide.topAnchor    : view.topAnchor
        let bottom = respectingSafeArea ? view.safeAreaLayoutGuide.bottomAnchor : view.bottomAnchor
        let lead   = respectingSafeArea ? view.safeAreaLayoutGuide.leadingAnchor: view.leadingAnchor
        let trail  = view.trailingAnchor
        
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo:    top),
            contentView.bottomAnchor.constraint(equalTo: bottom),
            contentView.leadingAnchor.constraint(equalTo:lead),
            contentView.trailingAnchor.constraint(equalTo:trail)
        ])
    }
}
