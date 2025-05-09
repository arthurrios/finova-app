//
//  Label+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 08/05/25.
//

import Foundation
import UIKit
private var styleKey: UInt8 = 0

extension UILabel {
    var fontStyle: Fonts? {
        get {
            return objc_getAssociatedObject(self, &styleKey) as? Fonts
        }
        set {
            objc_setAssociatedObject(self, &styleKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            applyStyle()
        }
    }
    
    func applyStyle() {
        guard let s = fontStyle, let original = text else { return }
        
        let casedText = s.textCasing?.apply(to: original) ?? original
        
        attributedText = NSAttributedString(string: casedText, attributes: s.attributes)
        adjustsFontForContentSizeCategory = true
    }
}
