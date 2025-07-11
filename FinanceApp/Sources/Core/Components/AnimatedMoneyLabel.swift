//
//  AnimatedMoneyLabel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 02/07/25.
//

import SwiftUI

struct AnimatedNumberLabel: View {
  var value: Int
  let font: UIFont
  let color: UIColor

  var body: some View {
    Text(value.currencyString)
      .font(Font(font))
      .foregroundColor(Color(color))
      .if(iOS17OrLater) { view in
        view.contentTransition(.numericText())  // iOS 17+ smooth animation

      }
      .animation(.easeInOut(duration: 0.3), value: value)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var iOS17OrLater: Bool {
    if #available(iOS 17.0, *) {
      return true
    } else {
      return false
    }
  }
}

extension View {
  @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content)
    -> some View
  {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}
