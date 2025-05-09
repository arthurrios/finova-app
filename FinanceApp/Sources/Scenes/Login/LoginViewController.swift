//
//  LoginViewController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Foundation
import UIKit

final class LoginViewController: UIViewController {
    let contentView: LoginView
    public weak var flowDelegate: LoginFlowDelegate?
    
    init(contentView: LoginView, flowDelegate: LoginFlowDelegate) {
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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startKeyboardObservers()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopKeyboardObservers()
    }

    
    private func setup() {
        view.addSubview(contentView)
        view.backgroundColor = Colors.gray100
        buildHierarchy()
    }
    
    
    private func buildHierarchy() {
        setupContentViewToBounds(contentView: contentView)
    }
    
    
    func animateShow(completion: (() -> Void)? = nil) {
        self.view.layoutIfNeeded()
        UIView.animate(withDuration: 1, animations: {
            self.contentView.containerView.alpha = 1
        }) { _ in
            completion?()
        }
    }
}
