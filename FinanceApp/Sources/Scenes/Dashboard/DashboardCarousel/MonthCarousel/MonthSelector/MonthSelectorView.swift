//
//  MonthSelector.swift
//  FinanceApp
//
//  Created by Arthur Rios on 12/05/25.
//

import Foundation
import UIKit

class MonthSelectorView: UIView {
    private let leftButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronLeft"), for: .normal)
        button.heightAnchor.constraint(equalToConstant: Metrics.spacing4).isActive = true
        button.widthAnchor.constraint(equalToConstant: Metrics.spacing4).isActive = true
        button.tintColor = Colors.gray500
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let rightButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "chevronRight"), for: .normal)
        button.heightAnchor.constraint(equalToConstant: Metrics.spacing4).isActive = true
        button.widthAnchor.constraint(equalToConstant: Metrics.spacing4).isActive = true
        button.tintColor = Colors.gray500
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.isPagingEnabled = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private var monthKeys: [String] = []
    private var monthsButtons: [UIButton] = []
    internal var months: [String] = []
    weak var delegate: MonthSelectorDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    convenience init(months: [String]) {
        self.init(frame: .zero)
        setupMonths()
    }
    
    func configure(keys: [String], months: [String]) {
        guard keys.count == months.count else { return }
        self.monthKeys = keys
        self.months = months
        setNeedsLayout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        addSubview(leftButton)
        addSubview(rightButton)
        addSubview(scrollView)
        leftButton.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
        rightButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            leftButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            scrollView.leadingAnchor.constraint(equalTo: leftButton.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rightButton.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    func setupMonths() {
        monthsButtons.forEach { $0.removeFromSuperview() }
        monthsButtons = []
        
        var x: CGFloat = 0
        let buttonWidth: CGFloat = 60
        let height = bounds.height
        
        for (index, month) in months.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(month, for: .normal)
            btn.tag = index
            btn.frame = CGRect(x: x, y: 0, width: buttonWidth, height: height)
            btn.addTarget(self, action: #selector(monthTapped(_:)), for: .touchUpInside)
            scrollView.addSubview(btn)
            monthsButtons.append(btn)
            x += buttonWidth
        }
        scrollView.contentSize = CGSize(width: x, height: height)
    }
    
    override func layoutSubviews() {
      super.layoutSubviews()
      setupMonths()
    }
    
    @objc
    private func prevTapped() {
        delegate?.didTapPrev()
    }
    
    @objc
    private func nextTapped() {
        delegate?.didTapNext()
    }
    
    @objc
    private func monthTapped(_ sender: UIButton) {
        let key = monthKeys[sender.tag]
        delegate?.didSelectMonth(withKey: key, at: sender.tag)
    }
}

extension MonthSelectorView {
    func scrollToMonth(at index: Int, animated: Bool = true) {
        guard index >= 0, index < monthsButtons.count else { return }
        let btn = monthsButtons[index]
        
        let centerX = (btn.frame.midX) - (bounds.width / 2.15)
        let maxOffsetX = scrollView.contentSize.width - scrollView.bounds.width
        let clampedX = max(0, min(centerX, maxOffsetX))
        scrollView.setContentOffset(CGPoint(x: clampedX, y: 0), animated: animated)
        
        monthsButtons.forEach { $0.alpha = ($0.tag == index ? 1 : 0.5) }
    }
}
