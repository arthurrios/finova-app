//
//  DataRecoveryToastContainer.swift
//  Finova
//
//  Created by Arthur Rios on 13/09/25.
//

import UIKit

final class DataRecoveryToastContainer: UIView {
    
    private var toastView: DataRecoveryToastView?
    private var isShowing = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.clear
        isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = UIColor.clear
        isUserInteractionEnabled = false
    }
    
    // MARK: - Touch Handling
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isShowing else { return nil }
        
        // Only intercept touches that are actually on the toast view
        if let toastView = toastView {
            let toastPoint = convert(point, to: toastView)
            if toastView.bounds.contains(toastPoint) {
                return toastView.hitTest(toastPoint, with: event)
            }
        }
        
        // Pass through touches that are not on the toast
        return nil
    }
    
    // MARK: - Public Methods
    func showRecoveryToast(delegate: DataRecoveryToastViewDelegate) {
        guard !isShowing else { return }
        isShowing = true
        isUserInteractionEnabled = true
        
        let toast = DataRecoveryToastView()
        toast.delegate = delegate
        self.toastView = toast
        
        addSubview(toast)
        setupToastConstraints(toast)
        
        // Show with animation
        toast.show(animated: true)
    }
    
    func hideRecoveryToast(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let toast = toastView, isShowing else {
            completion?()
            return
        }
        
        toast.hide(animated: animated) { [weak self] in
            toast.removeFromSuperview()
            self?.toastView = nil
            self?.isShowing = false
            self?.isUserInteractionEnabled = false
            completion?()
        }
    }
    
    private func setupToastConstraints(_ toast: DataRecoveryToastView) {
        toast.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            toast.topAnchor.constraint(equalTo: topAnchor),
            toast.leadingAnchor.constraint(equalTo: leadingAnchor),
            toast.trailingAnchor.constraint(equalTo: trailingAnchor),
            toast.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
