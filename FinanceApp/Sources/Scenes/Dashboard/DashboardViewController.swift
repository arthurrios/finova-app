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
    
    private var currentIndex: Int = 0 {
      didSet {
        currentIndex = min(max(currentIndex, 0), viewModel.loadMonthlyCards().count - 1)
        scrollCarousel(to: currentIndex)
      }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        contentView.delegate = self
        
        view.addSubview(contentView)
        contentView.frame = view.bounds
        contentView.bind(viewModel: viewModel)

        setup()
        setupDelegates()
        
        checkForExistingData()
    }
    
    private func setup() {
        contentView.setupCarousel()
        buildHierarchy()
    }
    
    private func setupDelegates() {
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
        scrollCarousel(to: currentIndex - 1)
    }
    
    func didTapNext() {
        scrollCarousel(to: currentIndex + 1)
    }
    
    func didSelectMonth(at index: Int) {
        scrollCarousel(to: index)
    }
    
    private var currentCarouselIndex: Int {
        contentView.monthCarousel.indexPathsForVisibleItems.first?.item ?? 0
    }
    
    private func scrollCarousel(to newIndex: Int, animated: Bool = true) {
        let clamped = min(max(newIndex, 0), viewModel.loadMonthlyCards().count - 1)
        let ip = IndexPath(item: clamped, section: 0)
        contentView.monthCarousel.scrollToItem(at: ip, at: .centeredHorizontally, animated: true)
        contentView.monthSelectorView.scrollToMonth(at: newIndex, animated: animated)
    }
}
