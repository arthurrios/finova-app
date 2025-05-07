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
    
    private func setup() {
        self.view.addSubview(contentView)
        self.navigationController?.isNavigationBarHidden = true
        
        setupConstraints()
        
        startAnimation()
    }
    
    private func setupConstraints() {
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
    }
    
    private func startAnimation() {
        
        viewModel.performInitialAnimation { [weak self] in
            guard let self else { return }
            
            UIView.animate(withDuration: 1, animations: {
                self.contentView.logoImageView.alpha = 1
            }, completion: { _ in
                self.viewModel.onAnimationFinished?()
            })
        }
    }
}
