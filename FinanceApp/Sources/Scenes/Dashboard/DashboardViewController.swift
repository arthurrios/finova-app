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
    let flowDelegate: DashboardFlowDelegate
    private var monthlyCards: [MonthBudgetCardType] = []
    
    init(
        contentView: DashboardView,
        viewModel: DashboardViewModel,
        flowDelegate: DashboardFlowDelegate
    ) {
        self.contentView = contentView
        self.viewModel = viewModel
        self.flowDelegate = flowDelegate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        monthlyCards = viewModel.loadMonthlyCards()
        let txs = viewModel.transactionRepo.fetchTransactions()
        
        contentView.carouselData = monthlyCards
        contentView.allTransactions = txs
        contentView.currentMonthIndex = viewModel.currentMonthIndex
        
        view.addSubview(contentView)
        contentView.frame = view.bounds
        
        setup()
        setupDelegates()
        
        checkForExistingData()
        
        view.layoutIfNeeded()
        contentView.reloadData()
    }
    
    private func setup() {
        contentView.reloadData()
        buildHierarchy()
    }
    
    private func setupDelegates() {
        contentView.delegate = self
        contentView.monthSelectorView.delegate = self
    }
    
    private func buildHierarchy() {
        setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
    }
    
    private func checkForExistingData() {
        if let user = UserDefaultsManager.getUser() {
            contentView.welcomeTitleLabel.text = "dashboard.welcomeTitle".localized + "\(user.name)!"
            contentView.welcomeTitleLabel.applyStyle()
        }
        
        if let userImage = UserDefaultsManager.loadProfileImage() {
            contentView.avatar.userImage = userImage
        }
    }
}

extension DashboardViewController: DashboardViewDelegate {
    func didTapProfileImage() {
        selectProfileImage()
    }
    
    func didTapAddTransaction() {
        //
    }
    
    
    
    func logout() {
        UserDefaultsManager.removeUser()
        self.flowDelegate.logout()
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
        scrollCarousel(to: contentView.monthSelectorView.selectedIndex - 1)
    }
    
    func didTapNext() {
        scrollCarousel(to: contentView.monthSelectorView.selectedIndex + 1)
    }
    
    func didSelectMonth(at index: Int) {
        scrollCarousel(to: index)
    }
    
    private func scrollCarousel(to newIndex: Int, animated: Bool = true) {
        let clamped = min(max(newIndex, 0), monthlyCards.count - 1)
        let ip = IndexPath(item: clamped, section: 0)
                
        contentView.monthCarousel.performBatchUpdates({}) { _ in
            self.contentView.monthCarousel.scrollToItem(at: ip, at: .centeredHorizontally, animated: animated)
            self.contentView.monthSelectorView.scrollToMonth(at: clamped, animated: animated)
        }
    }
}
