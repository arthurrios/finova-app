//
//  CustomTabBarDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 01/08/25.
//

import Foundation

protocol CustomTabBarControllerDelegate: AnyObject {
    func didSelectTab(at index: Int)
    func didTapFloatingActionButton()
}
