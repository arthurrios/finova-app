//
//  Colors.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

enum Colors {
    static let mainMagenta = UIColor(hex: "#DA4BDD")
    static let mainRed = UIColor(hex: "#D93A4A")
    static let mainGreen = UIColor(hex: "#1FA342")
    
    static let lowMagenta = UIColor(red: 220/255, green: 84/255, blue: 222/255, alpha: 0.05)
    static let opaqueWhite = UIColor(red: 249/255, green: 251/255, blue: 249/255, alpha: 0.05)
    
    static let gray100 = UIColor(hex: "#F9FBF9")
    static let gray200 = UIColor(hex: "#EFF0EF")
    static let gray300 = UIColor(hex: "#E5E6E5")
    static let gray400 = UIColor(hex: "#A1A2A1")
    static let gray500 = UIColor(hex: "#676767")
    static let gray600 = UIColor(hex: "#494A49")
    static let gray700 = UIColor(hex: "#0F0F0F")
    
    static var gradientBlack: CAGradientLayer {
        let gradient = CAGradientLayer()
        gradient.colors = [gray700.cgColor, UIColor(hex: "#2D2D2D").cgColor]
        
        let degrees: CGFloat = 102
        let radians = degrees * .pi / 180
        let dx = sin(radians)
        let dy = cos(radians)
        
        gradient.startPoint = CGPoint(x: 0.5 - dx/2, y: 0.5 - dy/2)
        gradient.endPoint = CGPoint(x: 0.5 + dx/2, y: 0.5 + dy/2)
        
        return gradient
    }
}

extension UIColor {
    convenience init(hex: String) {
        var hexFormatted: String = hex.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        hexFormatted = hexFormatted.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexFormatted).scanHexInt64(&rgb)
        
        let red: CGFloat = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green: CGFloat = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue: CGFloat = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
