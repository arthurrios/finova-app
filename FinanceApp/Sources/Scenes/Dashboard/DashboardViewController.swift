//
//  DashboardViewController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation
import UIKit

final class DashboardViewController: UIViewController {
    let contentView: DashboardView
    let viewModel: DashboardViewModel
    let syncedViewModel: SyncedCollectionsViewModel
    var todayMonthIndex: Int
    var isLoadingInitialData: Bool
    weak var flowDelegate: DashboardFlowDelegate?
    
    init(
        contentView: DashboardView,
        viewModel: DashboardViewModel,
        flowDelegate: DashboardFlowDelegate
    ) {
        self.contentView = contentView
        self.viewModel = viewModel
        self.syncedViewModel = SyncedCollectionsViewModel()
        self.flowDelegate = flowDelegate
        self.todayMonthIndex = UserDefaultsManager.getCurrentMonthIndex()
        self.isLoadingInitialData = true
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        contentView.frame = view.bounds
        loadData()
        setupCollectionViews()
        view.layoutIfNeeded()
    }
    
    private func setup() {
        view.addSubview(contentView)
        buildHierarchy()
        
        contentView.delegate = self
        syncedViewModel.delegate = self
    }
    
    private func buildHierarchy() {
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
    }
    
    private func loadData() {
        if let user = UserDefaultsManager.getUser() {
            contentView.welcomeTitleLabel.text = "dashboard.welcomeTitle".localized + "\(user.name)!"
            contentView.welcomeTitleLabel.applyStyle()
        }
        
        if let userImage = UserDefaultsManager.loadProfileImage() {
            contentView.avatar.userImage = userImage
        }
        
        let transactions = viewModel.transactionRepo.fetchTransactions()
        let monthData = viewModel.loadMonthlyCards()
        
        syncedViewModel.setMonthData(monthData)
        syncedViewModel.setTransactions(transactions)
    }
    
    private func setupCollectionViews() {
        contentView.monthSelectorView.collectionView.delegate = self
        contentView.monthSelectorView.collectionView.dataSource = self
        contentView.monthSelectorView.collectionView.register(MonthCell.self, forCellWithReuseIdentifier: MonthCell.reuseID)
        contentView.monthSelectorView.delegate = self
        
        contentView.monthCarousel.delegate = self
        contentView.monthCarousel.dataSource = self
        contentView.monthCarousel.register(MonthCarouselCell.self, forCellWithReuseIdentifier: MonthCarouselCell.reuseID)
        
        let monthTitles = syncedViewModel.getMonths()
        contentView.monthSelectorView.configure(months: monthTitles, selectedIndex: syncedViewModel.selectedIndex)
        
        
        syncedViewModel.selectMonth(at: todayMonthIndex)
        
        contentView.monthSelectorView.layoutIfNeeded()
        contentView.monthCarousel.layoutIfNeeded()
    }
}

extension DashboardViewController: DashboardViewDelegate {
    func didTapProfileImage() {
        selectProfileImage()
    }
    
    func didTapAddTransaction() {
        print("Add transaction tapped")
    }
    
    func logout() {
        UserDefaultsManager.removeUser()
        self.flowDelegate?.logout()
    }
}

extension DashboardViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private func selectProfileImage() {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        imagePicker.allowsEditing = true
        present(imagePicker, animated: true, completion: nil)
    }
    
    internal func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let editedImage = info[UIImagePickerController.InfoKey.editedImage] as? UIImage {
            contentView.avatar.userImage = editedImage
            UserDefaultsManager.saveProfileImage(image: editedImage)
        } else if let originalImage = info[.originalImage] as? UIImage {
            contentView.avatar.userImage = originalImage
            UserDefaultsManager.saveProfileImage(image: originalImage)
        }
        
        dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true)
    }
}

extension DashboardViewController: MonthSelectorDelegate {
    func didTapPrev() {
        syncedViewModel.moveToPreviousMonth()
    }
    
    func didTapNext() {
        syncedViewModel.moveToNextMonth()
    }
    
    func didSelectMonth(at index: Int) {
        syncedViewModel.selectMonth(at: index)
    }
}

extension DashboardViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return syncedViewModel.monthData.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView == contentView.monthCarousel {
            let model = syncedViewModel.monthData[indexPath.item]
            
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MonthCarouselCell.reuseID, for: indexPath) as? MonthCarouselCell else {
                fatalError("Could not dequeue cell")
            }
            
            let key = DateFormatter.keyFormatter.string(from: model.date)
            let txs = syncedViewModel.allTransactions.filter { tx in
                DateFormatter.keyFormatter.string(from: tx.date) == key
            }
            
            cell.configure(with: model, transactions: txs)
            
            return cell
        } else {
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MonthCell.reuseID, for: indexPath) as? MonthCell else {
                fatalError("Could not dequeue month cell")
            }
            
            let monthName = syncedViewModel.monthData[indexPath.item].month
            cell.configure(title: monthName)
            return cell
        }
    }
}

extension DashboardViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView == contentView.monthSelectorView.collectionView {
            syncedViewModel.selectMonth(at: indexPath.item)
        }
    }
}

extension DashboardViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView == contentView.monthCarousel {
            return CGSize(width: collectionView.bounds.width, height: collectionView.bounds.height)
        } else if collectionView == contentView.monthSelectorView.collectionView {
            
            let spacing = (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.minimumInteritemSpacing ?? 0
            let totalSpacing = spacing * 4
            let availableWidth = collectionView.bounds.width - totalSpacing
            let cellWidth = availableWidth / 5
            
            return CGSize(width: cellWidth, height: collectionView.bounds.height)
        } else {
            return CGSize(width: collectionView.bounds.width, height: collectionView.bounds.height)
        }
    }
}

extension DashboardViewController: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView == contentView.monthCarousel {
            let pageWidth = scrollView.frame.width
            let currentPage = Int(floor((scrollView.contentOffset.x - pageWidth / 2) / pageWidth) + 1)
            
            if currentPage >= 0 && currentPage < syncedViewModel.monthData.count {
                syncedViewModel.selectMonth(at: currentPage, animated: true)
            }
        }
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        scrollViewDidEndDecelerating(scrollView)
    }
}

extension DashboardViewController: SyncedCollectionsViewModelDelegate {
    func didUpdateSelectedIndex(_ index: Int, animated: Bool) {
         let ip = IndexPath(item: index, section: 0)

         // If it’s our initial load, wrap in a CATransaction to know exactly
         // when the scrolling animation and layout are done.
         if isLoadingInitialData {
             CATransaction.begin()
             CATransaction.setCompletionBlock { [weak self] in
                 guard let self = self else { return }
                 // show the real content
                 self.contentView.hideShimmerViewsAndShowOriginals()
                 self.isLoadingInitialData = false
             }

             contentView.monthCarousel.performBatchUpdates(nil) { _ in
                 // scroll the carousel
                 self.contentView.monthCarousel.scrollToItem(
                     at: ip,
                     at: .centeredHorizontally,
                     animated: true
                 )
                 // update the month selector highlight
                 self.contentView.monthSelectorView.scrollToMonth(
                     at: index,
                     animated: animated
                 )
             }

             CATransaction.commit()
         }
         else {
             // all subsequent updates can just run normally
             contentView.monthCarousel.performBatchUpdates(nil) { _ in
                 self.contentView.monthCarousel.scrollToItem(
                     at: ip,
                     at: .centeredHorizontally,
                     animated: animated
                 )
                 self.contentView.monthSelectorView.scrollToMonth(
                     at: index,
                     animated: animated
                 )
             }
         }
    }
    
    func didUpdateMonthData(_ data: [MonthBudgetCardType]) {
        let currentSelectedIndex = syncedViewModel.selectedIndex
        
        contentView.monthSelectorView.configure(months: data.map { $0.month }, selectedIndex: currentSelectedIndex)
        contentView.monthCarousel.reloadData()
        
        if currentSelectedIndex == 0 && data.count > 0 {
            DispatchQueue.main.async {
                let todayKey = DateFormatter.keyFormatter.string(from: Date())
                if let currentIndex = self.syncedViewModel.monthData.firstIndex(where: {
                    DateFormatter.keyFormatter.string(from: $0.date) == todayKey
                }) {
                    self.syncedViewModel.selectMonth(at: currentIndex, animated: false)
                }
            }
        } else if currentSelectedIndex > 0 {
            DispatchQueue.main.async {
                self.syncedViewModel.selectMonth(at: currentSelectedIndex, animated: false)
            }
        }
    }
    
    func didUpdateTransactions(_ transactions: [Transaction]) {
        contentView.monthCarousel.reloadData()
    }
}
