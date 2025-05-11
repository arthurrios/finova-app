//
//  ProgressView+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation
import UIKit

extension UIProgressView {
  func roundRightCornersFixedHeight(_ h: CGFloat) {
    transform = .identity
    
    translatesAutoresizingMaskIntoConstraints = false
    if let c = constraints.first(where: { $0.firstAttribute == .height }) {
      c.constant = h
    } else {
      heightAnchor.constraint(equalToConstant: h).isActive = true
    }
    
    layer.cornerRadius = h/2
    layer.masksToBounds = true
    
    layoutIfNeeded()
    guard subviews.count > 1 else { return }
    let fill = subviews[1]
    
    fill.layer.cornerRadius = h/2
    fill.layer.maskedCorners = [
      .layerMaxXMinYCorner,
      .layerMaxXMaxYCorner
    ]
    fill.clipsToBounds = true
  }
}
