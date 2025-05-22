//
//  MonthSelector.swift
//  FinanceApp
//
//  Created by Arthur Rios on 12/05/25.
//

import Foundation
import UIKit

class MonthSelectorView: UIView {
    
    weak var delegate: MonthSelectorDelegate?
    
    var months: [String] = [] {
        didSet {
            collectionView.reloadData()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.selectCell(at: self.selectedIndex, animated: false)
            }
        }
    }
    
    private(set) var selectedIndex: Int = 0
    
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
    
    internal lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = Metrics.spacing2
        layout.minimumLineSpacing = Metrics.spacing2
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        addSubview(leftButton)
        addSubview(rightButton)
        addSubview(collectionView)
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
            
            collectionView.leadingAnchor.constraint(equalTo: leftButton.trailingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: rightButton.leadingAnchor),
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    func configure(months: [String], selectedIndex: Int = 0) {
        self.selectedIndex = selectedIndex
        self.months = months
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.selectCell(at: selectedIndex, animated: false)
        }
    }
    
    func scrollToMonth(at index: Int, animated: Bool = true) {
        guard index >= 0, index < months.count else { return }
        selectedIndex = index
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.selectItem(at: indexPath,
                                  animated: true,
                                  scrollPosition: .centeredHorizontally)
        collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: animated)
    }
    
    private func selectCell(at index: Int, animated: Bool) {
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.selectItem(at: indexPath,
                                  animated: animated,
                                  scrollPosition: .centeredHorizontally)
        collectionView.scrollToItem(at: indexPath,
                                    at: .centeredHorizontally,
                                    animated: animated)
    }
    
    @objc
    private func prevTapped() {
        delegate?.didTapPrev()
    }
    
    @objc
    private func nextTapped() {
        delegate?.didTapNext()
    }
}

extension MonthSelectorView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return months.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MonthCell.reuseID, for: indexPath) as? MonthCell else { return UICollectionViewCell() }
        
        cell.configure(title: months[indexPath.item])
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        delegate?.didSelectMonth(at: indexPath.item)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: 0, height: bounds.height)
    }
}
