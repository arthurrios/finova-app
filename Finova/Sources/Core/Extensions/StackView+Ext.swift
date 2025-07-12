//
//  StackView+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation
import UIKit

extension UIStackView {
  convenience init(
    axis: NSLayoutConstraint.Axis,
    spacing: CGFloat = 0,
    alignment: UIStackView.Alignment = .fill,
    distribution: UIStackView.Distribution = .fill,
    arrangedSubviews: [UIView] = []
  ) {
    self.init(arrangedSubviews: arrangedSubviews)
    self.axis = axis
    self.spacing = spacing
    self.alignment = alignment
    self.distribution = distribution
    self.translatesAutoresizingMaskIntoConstraints = false
  }
}
