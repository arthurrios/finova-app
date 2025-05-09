//
//  Fonts.swift
//  FinanceApp
//
//  Created by Arthur Rios on 08/05/25.
//

import Foundation
import UIKit

struct Fonts {
    let size: CGFloat
    let weight: UIFont.Weight?
    let lineHeight: CGFloat?
    let textCasing: TextCasing?
    
    init(size: CGFloat,
         weight: UIFont.Weight? = .regular,
         lineHeight: CGFloat? = nil,
         textCasing: TextCasing = .none) {
        self.size = size
        self.weight = weight
        self.lineHeight = lineHeight
        self.textCasing = textCasing
    }
    
    var font: UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [.family: "Lato"])
            .addingAttributes([
                .traits: [UIFontDescriptor.TraitKey.weight: weight]
            ])
        
        let font = UIFont(descriptor: descriptor, size: size)
        return UIFontMetrics.default.scaledFont(for: font)
    }
    
    var paragraphStyle: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        if let height = lineHeight {
            p.minimumLineHeight = height
            p.maximumLineHeight = height
        }
        return p
    }
    
    var attributes: [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [:]
        attrs[.font] = font
        
        if lineHeight != nil {
            attrs[.paragraphStyle] = paragraphStyle
        }
        return attrs
    }
    
    static let titleLG = Fonts(size: 28, weight: .black)
    static let titleMD = Fonts(size: 16, weight: .bold)
    static let titleSM = Fonts(size: 14, weight: .bold, textCasing: .uppercase)
    static let titleXS = Fonts(size: 12, weight: .bold, textCasing: .uppercase)
    static let title2XS = Fonts(size: 10, weight: .bold, textCasing: .uppercase)
    static let textSM = Fonts(size: 14)
    static let textXS = Fonts(size: 12)
    static let input = Fonts(size: 16, lineHeight: 24)
    static let buttonMD = Fonts(size: 16, weight: .bold, lineHeight: 24)
    static let buttonSM = Fonts(size: 14, weight: .bold, lineHeight: 20)
}
