//
//  LoadingManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on 23/06/25.
//

import Foundation
import UIKit

class LoadingManager {
    static let shared = LoadingManager()
    
    private var loadingView: UIView?
    private var activityIndicator: UIActivityIndicatorView?
    
    private init() {}
    
    // MARK: - Public methods
    
    func showLoading(on viewController: UIViewController, message: String = "loading.message".localized) {
        DispatchQueue.main.async {
            self.hideLoading()
            
            let loadingView = self.createLoadingView()
            viewController.view.addSubview(loadingView)
            
            loadingView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                loadingView.topAnchor.constraint(equalTo: viewController.view.topAnchor),
                loadingView.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
                loadingView.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
                loadingView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor)
            ])
            
            self.loadingView = loadingView
            
            loadingView.alpha = 0
            UIView.animate(withDuration: 0.3) {
                loadingView.alpha = 1
            }
        }
    }
    
    func hideLoading() {
        DispatchQueue.main.async {
            guard let loadingView = self.loadingView else { return }
            
            UIView.animate(withDuration: 0.3, animations: {
                loadingView.alpha = 0
            }) { _ in
                loadingView.removeFromSuperview()
                self.loadingView = nil
                self.activityIndicator = nil
            }
        }
    }
    
    // MARK: - Private methods
    
    private func createLoadingView() -> UIView {
          let containerView = UIView()
          containerView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
          
          let contentView = UIView()
          contentView.backgroundColor = UIColor.systemBackground
          contentView.layer.cornerRadius = 12
          contentView.layer.shadowColor = UIColor.black.cgColor
          contentView.layer.shadowOffset = CGSize(width: 0, height: 2)
          contentView.layer.shadowRadius = 8
          contentView.layer.shadowOpacity = 0.1
          contentView.translatesAutoresizingMaskIntoConstraints = false
          
          let activityIndicator = UIActivityIndicatorView(style: .large)
          activityIndicator.color = Colors.mainMagenta
          activityIndicator.startAnimating()
          activityIndicator.translatesAutoresizingMaskIntoConstraints = false
          
          containerView.addSubview(contentView)
          contentView.addSubview(activityIndicator)
          
          self.activityIndicator = activityIndicator
          
          NSLayoutConstraint.activate([
              // Content view centered
              contentView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
              contentView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
              contentView.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.8),
              contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
              
              // Activity indicator
              activityIndicator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
              activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)
          ])
          
          return containerView
      }
}
