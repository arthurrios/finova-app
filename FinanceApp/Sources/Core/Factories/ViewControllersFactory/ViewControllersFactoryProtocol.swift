//
//  ViewControllersFactoryProtocol.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
protocol ViewControllersFactoryProtocol: AnyObject {
    func makeSplashViewController(flowDelegate: SplashFlowDelegate) -> SplashViewController
}
