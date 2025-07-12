//
//  ProgressView+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation
import UIKit

extension UIProgressView {
  func roundRightCornersFixedHeight(_ height: CGFloat) {
    transform = .identity

    translatesAutoresizingMaskIntoConstraints = false
    if let constraint = constraints.first(where: { $0.firstAttribute == .height }) {
      constraint.constant = height
    } else {
      heightAnchor.constraint(equalToConstant: height).isActive = true
    }

    layer.cornerRadius = height / 2
    layer.masksToBounds = true

    layoutIfNeeded()
    guard subviews.count > 1 else { return }
    let fill = subviews[1]

    fill.layer.cornerRadius = height / 2
    fill.layer.maskedCorners = [
      .layerMaxXMinYCorner,
      .layerMaxXMaxYCorner
    ]
    fill.clipsToBounds = true
  }
}
