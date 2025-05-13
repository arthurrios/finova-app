//
//  DashboardViewCarousel+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 11/05/25.
//

import Foundation
import UIKit

extension DashboardView {
    
    private struct AssociatedKeys {
        static var carouselData: UInt8 = 0
        static var allTransactions: UInt8 = 0
    }
    
    private var carouselData: [MonthBudgetCardType] {
        get { objc_getAssociatedObject(self, &AssociatedKeys.carouselData) as? [MonthBudgetCardType] ?? [] }
        set { objc_setAssociatedObject(self, &AssociatedKeys.carouselData, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    private var allTransactions: [Transaction] {
        get { objc_getAssociatedObject(self, &AssociatedKeys.allTransactions) as? [Transaction] ?? [] }
        set { objc_setAssociatedObject(self, &AssociatedKeys.allTransactions, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    func bind(viewModel: DashboardViewModel) {
        carouselData = viewModel.loadMonthlyCards()
        allTransactions = viewModel.transactionRepo.fetchTransactions()
        
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
        monthCarousel.isScrollEnabled = true
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
        monthSelectorView.configure(months: monthTitles)
    }
    
    private func setupIndexes() {
        let todayKey = DateFormatter.keyFormatter.string(from: Date())
        
        if let currentIndex = carouselData.firstIndex(where: {
            DateFormatter.keyFormatter.string(from: $0.date) == todayKey
        }) {
            let ip = IndexPath(item: currentIndex, section: 0)
            monthCarousel.scrollToItem(at: ip, at: .centeredHorizontally, animated: false)
            monthSelectorView.collectionView.scrollToItem(at: ip, at: .centeredHorizontally, animated: true)
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
        return carouselData.count
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
