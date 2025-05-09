//
//  SplashViewController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

final class SplashViewController: UIViewController {
    let viewModel = SplashViewModel()
    let contentView: SplashView
    public weak var flowDelegate: SplashFlowDelegate?
    
    private let gradientLayer = Colors.gradientBlack
    
    init(contentView: SplashView, flowDelegate: SplashFlowDelegate) {
        self.contentView = contentView
        self.flowDelegate = flowDelegate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
        view.layer.insertSublayer(gradientLayer, at: 0)
    }
    
    private func decideNavigationFlow() {
        if let user = UserDefaultsManager.getUser(), user.isUserSaved ?? false {
            flowDelegate?.navigateToDashboard()
        } else {
            animateLogoUp()
        }
    }

    
    private func setup() {
        self.view.backgroundColor = Colors.gray100
        self.view.addSubview(contentView)
        self.navigationController?.isNavigationBarHidden = true
        
        buildHierarchy()

        startAnimation()
    }
    
    private func buildHierarchy() {
        setupContentViewToBounds(contentView: contentView)
    }
    
    @objc
    private func navigateToLogin() {
        self.flowDelegate?.navigateToLogin()
    }
}


// MARK: - Animations
extension SplashViewController {
    private func startAnimation() {
        
        viewModel.performInitialAnimation { [weak self] in
            guard let self else { return }
            
            UIView.animate(withDuration: 1, animations: {
                self.contentView.logoImageView.alpha = 1
            }, completion: { _ in
                self.decideNavigationFlow()
            })
        }
    }
    
    private func animateLogoUp() {
        UIView.animate(withDuration: 1, delay: 0, options: [.curveEaseOut], animations: {
            self.contentView.logoImageView.transform = self.contentView.logoImageView.transform
                .translatedBy(x: 0, y: -200)
                .scaledBy(x: 1.15, y: 1.15)
        }, completion: { _ in
            UIView.animate(withDuration: 1, animations: {
                self.contentView.loginImageView.alpha = 1
            })

            let fadeAnimation = CABasicAnimation(keyPath: "opacity")
            fadeAnimation.fromValue = 1
            fadeAnimation.toValue = 0
            fadeAnimation.duration = 1
            fadeAnimation.fillMode = .forwards
            fadeAnimation.isRemovedOnCompletion = false
            self.gradientLayer.add(fadeAnimation, forKey: "fade")

            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.gradientLayer.removeFromSuperlayer()
                self.navigateToLogin()
            }
        })
    }

}
