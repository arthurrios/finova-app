//
//  DashboardView.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation
import UIKit

final class DashboardView: UIView {
    public weak var delegate: DashboardViewDelegate?
    public var carouselData: [MonthBudgetCardType] = []
    public var allTransactions: [Transaction] = []
    public var currentMonthIndex: Int = 0
    
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
        sel.heightAnchor.constraint(equalToConstant: Metrics.spacing8).isActive = true
        sel.translatesAutoresizingMaskIntoConstraints = false
        return sel
    }()
    
    internal let monthCarousel: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()
    
    override init (frame: CGRect) {
        super.init(frame: frame)
        setupView()
        addMonthSelector()
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
        addSubview(monthSelectorView)
        headerContainerView.addSubview(headerItemsView)
        headerItemsView.addSubview(avatar)
        headerItemsView.addSubview(welcomeTitleLabel)
        headerItemsView.addSubview(welcomeSubtitleLabel)
        headerItemsView.addSubview(logoutButton)
        
        logoutButton.addTarget(self,
                               action: #selector(logoutTapped),
                               for: .touchUpInside)
        
        setupConstraints()
        setupImageGesture()
    }
    
    private func addMonthSelector() {
        addSubview(monthSelectorView)
        NSLayoutConstraint.activate([
            monthSelectorView.topAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: Metrics.spacing5),
            monthSelectorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.spacing4),
            monthSelectorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.spacing4),
        ])
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
    
    private func setupConstraints() {
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
        ])
    }
}

extension DashboardView {
    
    func reloadData() {
        setupCarousel()
        setupMonthSelector()
        setupIndexes()
    }
    
    func setupCarousel() {
        monthCarousel.dataSource = self
        monthCarousel.delegate = self
        
        monthCarousel.collectionViewLayout.invalidateLayout()
        if let flow = monthCarousel.collectionViewLayout as? UICollectionViewFlowLayout {
            flow.scrollDirection = .horizontal
            flow.minimumLineSpacing = 0
            flow.itemSize = bounds.size
        }
        
        monthCarousel.isPagingEnabled = true
        monthCarousel.backgroundColor = .clear
        monthCarousel.isScrollEnabled = false
        monthCarousel.showsHorizontalScrollIndicator = false
        
        monthCarousel.register(MonthCarouselCell.self, forCellWithReuseIdentifier: MonthCarouselCell.reuseID)
        
        if monthCarousel.superview == nil {
            addSubview(monthCarousel)
            monthCarousel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                monthCarousel.topAnchor.constraint(equalTo: monthSelectorView.bottomAnchor, constant: Metrics.spacing4),
                monthCarousel.leadingAnchor.constraint(equalTo: leadingAnchor),
                monthCarousel.trailingAnchor.constraint(equalTo: trailingAnchor),
                monthCarousel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
            ])
        }
        monthCarousel.reloadData()
        monthCarousel.layoutIfNeeded()
    }
    
    private func setupMonthSelector() {
        let monthTitles = carouselData.map { $0.month }
        let initial = currentMonthIndex
        monthSelectorView.configure(months: monthTitles, selectedIndex: initial)
        monthSelectorView.layoutIfNeeded()
        monthSelectorView.scrollToMonth(at: initial, animated: false)
    }
    
    private func setupIndexes() {
        let todayKey = DateFormatter.keyFormatter.string(from: Date())
        
        if let currentIndex = carouselData.firstIndex(where: {
            DateFormatter.keyFormatter.string(from: $0.date) == todayKey
        }) {
            let ip = IndexPath(item: currentIndex, section: 0)
            monthCarousel.scrollToItem(at: ip, at: .centeredHorizontally, animated: false)
        }
    }
}

extension DashboardView {
    override func layoutSubviews() {
        super.layoutSubviews()
        if let flow = monthCarousel.collectionViewLayout as? UICollectionViewFlowLayout {
            flow.itemSize = monthCarousel.bounds.size
        }
        monthCarousel.collectionViewLayout.invalidateLayout()
    }
}

extension DashboardView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.carouselData.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let model = carouselData[indexPath.item]
        guard let date = Calendar.current.date(byAdding: .month, value: indexPath.item - carouselData.count / 2, to: Date()) else {
            return UICollectionViewCell()
        }
        
        let key = DateFormatter.keyFormatter.string(from: date)
        let txs = allTransactions.filter { tx in
            DateFormatter.keyFormatter.string(from: tx.date) == key
        }
        
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MonthCarouselCell.reuseID, for: indexPath) as? MonthCarouselCell else {
            fatalError("Could not dequeue cell")
        }
        
        cell.configure(with: model, transactions: txs)
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: collectionView.bounds.width, height: collectionView.bounds.height)
    }
}
