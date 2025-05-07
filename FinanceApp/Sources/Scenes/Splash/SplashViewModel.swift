//
//  SplashViewModel.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation

final class SplashViewModel {
    var onAnimationFinished: (() -> Void)?
    
    func performInitialAnimation(completion: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            completion()
        }
    }
}
