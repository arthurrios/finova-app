//
//  DashboardView.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation
import UIKit
import ShimmerView

final class DashboardView: UIView {
    public weak var delegate: DashboardViewDelegate?
    
    let headerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = Colors.gray100
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Metrics.headerHeight).isActive = true
        return view
    }()
    
    let headerItemsView: UIView = {
        let view = UIView()
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: Metrics.spacing3, leading: Metrics.spacing5, bottom: Metrics.spacing6, trailing: Metrics.spacing5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let avatar = Avatar()
    
    let welcomeTitleLabel: UILabel = {
        let label = UILabel()
        label.fontStyle = Fonts.titleSM
        label.textColor = Colors.gray700
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let welcomeSubtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Fonts.textSM.font
        label.textColor = Colors.gray500
        label.text = "dashboard.welcomeSubtitle".localized
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let logoutButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: "logout"), for: .normal)
        btn.tintColor = Colors.gray500
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
    lazy var monthSelectorView: MonthSelectorView = {
        let sel = MonthSelectorView()
        sel.isHidden = true
        sel.heightAnchor.constraint(equalToConstant: Metrics.spacing8).isActive = true
        sel.translatesAutoresizingMaskIntoConstraints = false
        return sel
    }()
    
    lazy var monthCarousel: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.isHidden = true
        collectionView.isPagingEnabled = true
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()
    
    private let addTransactionButton: UIButton = {
        let btn = UIButton(type: .system)
        
        if let originalImage = UIImage(named: "plus") {
            let newSize = CGSize(width: 24, height: 24)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
            originalImage.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            btn.setImage(resizedImage, for: .normal)
        }
        
        btn.tintColor = Colors.gray100
        btn.backgroundColor = Colors.gray700
        
        btn.imageView?.contentMode = .center
        
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOffset = CGSize(width: 0, height: 4)
        btn.layer.shadowOpacity = 0.25
        btn.layer.shadowRadius = 4
        btn.layer.shouldRasterize = true
        btn.layer.rasterizationScale = UIScreen.main.scale
        
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
    let monthSelectorShimmerView: ShimmerView = {
        let style = ShimmerViewStyle(baseColor: Colors.gray100, highlightColor: .white, duration: 1.2, interval: 0.4, effectSpan: .points(120), effectAngle: 0 * CGFloat.pi)
        
        let view = ShimmerView()
        view.style = style
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.clipsToBounds = true
        view.startAnimating()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let monthCardShimmerView: ShimmerView = {
        let style = ShimmerViewStyle(baseColor: Colors.gray700, highlightColor: Colors.gray400, duration: 1.2, interval: 0.4, effectSpan: .points(120), effectAngle: 0 * CGFloat.pi)
        
        let view = ShimmerView()
        view.style = style
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.clipsToBounds = true
        view.startAnimating()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let transactionsTableShimmerView: ShimmerView = {
        let style = ShimmerViewStyle(baseColor: Colors.gray100, highlightColor: .white, duration: 1.2, interval: 0.4, effectSpan: .points(120), effectAngle: 0 * CGFloat.pi)
        
        let view = ShimmerView()
        view.style = style
        view.layer.borderColor = Colors.gray300.cgColor
        view.layer.borderWidth = 1
        view.layer.cornerRadius = CornerRadius.extraLarge
        view.clipsToBounds = true
        view.startAnimating()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    override init (frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupLayout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func configure(userName: String, profileImage: UIImage) {
        welcomeTitleLabel.text = "dashboard.welcomeTitle".localized + "\(userName)!"
        welcomeTitleLabel.applyStyle()
        
        avatar.userImage = profileImage
    }
    
    private func setupView() {
        backgroundColor = Colors.gray200
        
        addSubview(headerContainerView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(avatar)
        headerItemsView.addSubview(welcomeTitleLabel)
        headerItemsView.addSubview(welcomeSubtitleLabel)
        headerItemsView.addSubview(logoutButton)
        addSubview(addTransactionButton)
        addSubview(monthCardShimmerView)
        addSubview(transactionsTableShimmerView)
        addSubview(monthSelectorShimmerView)
        
        addSubview(monthSelectorView)
        addSubview(monthCarousel)
        
        bringSubviewToFront(addTransactionButton)
        
        logoutButton.addTarget(self,
                               action: #selector(logoutTapped),
                               for: .touchUpInside)
        
        addTransactionButton.addTarget(self,
                                       action: #selector(handleTapAddButton),
                                       for: .touchUpInside)
        
        setupImageGesture()
    }
    
    private func setupLayout() {
        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: topAnchor),
            headerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            headerItemsView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            headerItemsView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerItemsView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerItemsView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor),
            
            avatar.leadingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.leadingAnchor),
            avatar.topAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.topAnchor),
            
            welcomeTitleLabel.topAnchor.constraint(equalTo: avatar.topAnchor),
            welcomeTitleLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: Metrics.spacing3),
            
            welcomeSubtitleLabel.topAnchor.constraint(equalTo: welcomeTitleLabel.bottomAnchor, constant: Metrics.spacing1),
            welcomeSubtitleLabel.leadingAnchor.constraint(equalTo: welcomeTitleLabel.leadingAnchor),
            
            logoutButton.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            logoutButton.trailingAnchor.constraint(equalTo: headerItemsView.layoutMarginsGuide.trailingAnchor),
            logoutButton.heightAnchor.constraint(equalToConstant: Metrics.logoutButtonSize),
            logoutButton.widthAnchor.constraint(equalToConstant: Metrics.logoutButtonSize),
            
            monthSelectorView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing5),
            monthSelectorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            monthSelectorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            
            monthCarousel.topAnchor.constraint(equalTo: monthSelectorView.bottomAnchor),
            monthCarousel.leadingAnchor.constraint(equalTo: leadingAnchor),
            monthCarousel.trailingAnchor.constraint(equalTo: trailingAnchor),
            monthCarousel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            
            monthSelectorShimmerView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing5),
            monthSelectorShimmerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            monthSelectorShimmerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            monthSelectorShimmerView.heightAnchor.constraint(equalToConstant: 20),
            
            monthCardShimmerView.topAnchor.constraint(equalTo: monthSelectorView.bottomAnchor, constant: Metrics.spacing5),
            monthCardShimmerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            monthCardShimmerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
            monthCardShimmerView.heightAnchor.constraint(equalToConstant: Metrics.monthCardShimmerHeight),
            
            transactionsTableShimmerView.topAnchor.constraint(equalTo: monthCardShimmerView.bottomAnchor, constant: Metrics.spacing4),
            transactionsTableShimmerView.leadingAnchor.constraint(equalTo: monthCardShimmerView.leadingAnchor),
            transactionsTableShimmerView.trailingAnchor.constraint(equalTo: monthCardShimmerView.trailingAnchor),
            transactionsTableShimmerView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            
            addTransactionButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            addTransactionButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            addTransactionButton.heightAnchor.constraint(equalToConstant: Metrics.addButtonSize),
            addTransactionButton.widthAnchor.constraint(equalToConstant: Metrics.addButtonSize)
        ])
    }
    
    func hideShimmerViewsAndShowOriginals() {
        monthCardShimmerView.isHidden = true
        transactionsTableShimmerView.isHidden = true
        monthSelectorShimmerView.isHidden = true
        
        monthSelectorView.isHidden = false
        monthCarousel.isHidden = false
    }
    
    @objc private func logoutTapped() {
        delegate?.logout()
    }
    
    private func setupImageGesture() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleProfileImageTap))
        avatar.addGestureRecognizer(tapGestureRecognizer)
    }
    
    @objc
    private func handleProfileImageTap() {
        delegate?.didTapProfileImage()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        addTransactionButton.layer.cornerRadius = Metrics.addButtonSize / 2
        
        addTransactionButton.layer.shadowPath = UIBezierPath(
            roundedRect: addTransactionButton.bounds,
            cornerRadius: addTransactionButton.layer.cornerRadius
        ).cgPath
    }
    
    @objc
    private func handleTapAddButton() {
        delegate?.didTapAddTransaction()
    }
}
