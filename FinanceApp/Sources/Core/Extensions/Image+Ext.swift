//
//  Image+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 20/06/25.
//

import Foundation
import UIKit

extension UIImage {
    func resizedPreservingColor(to targetSize: CGSize) -> UIImage {
        let original = self.withRenderingMode(.alwaysOriginal)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let rendered = renderer.image { _ in
            original.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.withRenderingMode(.alwaysOriginal)
    }
}

