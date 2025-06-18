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
    private var needsRefresh = false
    private var transactions: [Transaction] = []
    private var currentCellTransactions: [Transaction] = []
    private var transactionsByMonth: [Int: [Transaction]] = [:]
    
    private var currentCell: MonthCarouselCell?
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
        self.syncedViewModel.saveInitialDate()
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
        loadData()
        contentView.frame = view.bounds
        setupCollectionViews()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let monthData = viewModel.loadMonthlyCards()
        syncedViewModel.setMonthData(monthData)
        syncedViewModel.setTransactions(viewModel.transactionRepo.fetchTransactions())
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
    
    func loadData() {
        if let user = UserDefaultsManager.getUser() {
            contentView.welcomeTitleLabel.text = "dashboard.welcomeTitle".localized + "\(user.name)!"
            contentView.welcomeTitleLabel.applyStyle()
        }
        
        if let userImage = UserDefaultsManager.loadProfileImage() {
            contentView.avatar.userImage = userImage
        }
        
        transactions = viewModel.transactionRepo.fetchTransactions()
        
        let monthData = viewModel.loadMonthlyCards()
        
        syncedViewModel.setMonthData(monthData)
        syncedViewModel.setTransactions(transactions)
        viewModel.scheduleAllTransactionNotifications()
        
        contentView.monthCarousel.layoutIfNeeded()
    }
    
    private func setupCollectionViews() {
        contentView.monthSelectorView.collectionView.delegate = self
        contentView.monthSelectorView.collectionView.dataSource = self
        contentView.monthSelectorView.collectionView.register(
            MonthCell.self, forCellWithReuseIdentifier: MonthCell.reuseID)
        contentView.monthSelectorView.delegate = self
        
        contentView.monthCarousel.delegate = self
        contentView.monthCarousel.dataSource = self
        contentView.monthCarousel.register(
            MonthCarouselCell.self, forCellWithReuseIdentifier: MonthCarouselCell.reuseID)
        
        let monthTitles = syncedViewModel.getMonths()
        contentView.monthSelectorView.configure(
            months: monthTitles, selectedIndex: syncedViewModel.selectedIndex)
        
        contentView.monthCarousel.reloadData()
        
        contentView.monthSelectorView.layoutIfNeeded()
        contentView.monthCarousel.layoutIfNeeded()
    }
}

extension DashboardViewController: DashboardViewDelegate {
    func didTapProfileImage() {
        selectProfileImage()
    }
    
    func didTapAddTransaction() {
        self.flowDelegate?.openAddTransactionModal()
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
    
    internal func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
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
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int)
    -> Int {
        return syncedViewModel.monthData.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
    -> UICollectionViewCell {
        if collectionView == contentView.monthCarousel {
            let model = syncedViewModel.monthData[indexPath.item]
            
            guard
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: MonthCarouselCell.reuseID, for: indexPath) as? MonthCarouselCell
            else {
                fatalError("Could not dequeue cell")
            }
            
            cell.monthCard.delegate = self
            
            cell.transactionTableView.dataSource = self
            cell.transactionTableView.delegate = self
            cell.transactionTableView.register(
                TransactionCell.self, forCellReuseIdentifier: TransactionCell.reuseID)
            
            let key = DateFormatter.keyFormatter.string(from: model.date)
            let txs = syncedViewModel.allTransactions.filter { tx in
                let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                let txKey = DateFormatter.keyFormatter.string(from: txDate)
                return txKey == key
            }.sorted { (tx1, tx2) -> Bool in
                return tx1.date > tx2.date
            }
            
            if indexPath.item == syncedViewModel.selectedIndex {
                currentCellTransactions = txs
                currentCell = cell
            }
            
            cell.tag = indexPath.item
            cell.transactions = txs
            cell.configure(with: model, transactions: txs)
            
            return cell
        } else {
            guard
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: MonthCell.reuseID, for: indexPath) as? MonthCell
            else {
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
    func collectionView(
        _ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        if collectionView == contentView.monthCarousel {
            return CGSize(width: collectionView.bounds.width, height: collectionView.bounds.height)
        } else if collectionView == contentView.monthSelectorView.collectionView {
            
            let spacing =
            (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?
                .minimumInteritemSpacing ?? 0
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
            let page = Int(floor((scrollView.contentOffset.x - pageWidth / 2) / pageWidth) + 1)
            syncedViewModel.selectMonth(at: page, animated: true)
            
            if let visibleCells = contentView.monthCarousel.visibleCells as? [MonthCarouselCell],
               let firstCell = visibleCells.first {
                currentCell = firstCell
                
                let index = firstCell.tag
                if index < syncedViewModel.monthData.count {
                    let model = syncedViewModel.monthData[index]
                    let key = DateFormatter.keyFormatter.string(from: model.date)
                    let txs = syncedViewModel.allTransactions.filter { tx in
                        let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                        let txKey = DateFormatter.keyFormatter.string(from: txDate)
                        return txKey == key
                    }.sorted { (tx1, tx2) -> Bool in
                        return tx1.date > tx2.date
                    }
                    currentCellTransactions = txs
                }
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
        
        if index < syncedViewModel.monthData.count {
            let model = syncedViewModel.monthData[index]
            let key = DateFormatter.keyFormatter.string(from: model.date)
            let txs = syncedViewModel.allTransactions.filter { tx in
                let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                let txKey = DateFormatter.keyFormatter.string(from: txDate)
                return txKey == key
            }.sorted { (tx1, tx2) -> Bool in
                return tx1.date > tx2.date
            }
            currentCellTransactions = txs
        }
        
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
            
            DispatchQueue.main.async {
                self.contentView.hideShimmerViewsAndShowOriginals()
                self.isLoadingInitialData = false
            }
        }
    }
    
    func didUpdateMonthData(_ data: [MonthBudgetCardType]) {
        let currentSelectedIndex = syncedViewModel.selectedIndex
        
        contentView.monthSelectorView.configure(
            months: data.map { $0.month }, selectedIndex: currentSelectedIndex)
        DispatchQueue.main.async {
            self.contentView.monthCarousel.reloadData()
        }
        if currentSelectedIndex == 0 && data.isEmpty {
            DispatchQueue.main.async {
                let todayKey = DateFormatter.keyFormatter.string(from: Date())
                if let currentIndex = self.syncedViewModel.monthData.firstIndex(where: {
                    DateFormatter.keyFormatter.string(from: $0.date) == todayKey
                }) {
                    self.syncedViewModel.selectMonth(at: currentIndex, animated: !self.isLoadingInitialData)
                }
            }
        } else if currentSelectedIndex > 0 {
            DispatchQueue.main.async {
                self.syncedViewModel.selectMonth(
                    at: currentSelectedIndex, animated: !self.isLoadingInitialData)
            }
        }
    }
    
    func didUpdateTransactions(_ transactions: [Transaction]) {
        DispatchQueue.main.async {
            self.contentView.monthCarousel.reloadData()
        }
        if currentCell != nil {
            let index = syncedViewModel.selectedIndex
            if index < syncedViewModel.monthData.count {
                let model = syncedViewModel.monthData[index]
                let key = DateFormatter.keyFormatter.string(from: model.date)
                let txs = syncedViewModel.allTransactions.filter { tx in
                    let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                    let txKey = DateFormatter.keyFormatter.string(from: txDate)
                    return txKey == key
                }.sorted { (tx1, tx2) -> Bool in
                    return tx1.date > tx2.date
                }
                currentCellTransactions = txs
            }
        }
    }
}

extension DashboardViewController: MonthBudgetCardDelegate {
    func didTapConfigButton() {
        flowDelegate?.navigateToBudgets(date: nil)
    }
    
    func didTapDefineBudgetButton(budgetDate: Date) {
        flowDelegate?.navigateToBudgets(date: budgetDate)
    }
}

// MARK: - Transaction Table View Management
extension DashboardViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard
            let parentCell = tableView.superview(of: MonthCarouselCell.self),
            parentCell.tag < syncedViewModel.monthData.count
        else { return 0 }
        
        let model = syncedViewModel.monthData[parentCell.tag]
        let key = DateFormatter.keyFormatter.string(from: model.date)
        let txs = syncedViewModel.allTransactions
            .filter { tx in
                let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                return DateFormatter.keyFormatter.string(from: txDate) == key
            }
            .sorted { $0.date > $1.date }
        
        return txs.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell =
        tableView.dequeueReusableCell(withIdentifier: TransactionCell.reuseID, for: indexPath)
        as! TransactionCell
        
        guard
            let parentCell = tableView.superview(of: MonthCarouselCell.self),
            parentCell.tag < syncedViewModel.monthData.count
        else {
            return cell
        }
        
        let model = syncedViewModel.monthData[parentCell.tag]
        let key = DateFormatter.keyFormatter.string(from: model.date)
        let txs = syncedViewModel.allTransactions
            .filter { tx in
                let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
                return DateFormatter.keyFormatter.string(from: txDate) == key
            }
            .sorted { $0.date > $1.date }
        
        let tx = txs[indexPath.row]
        
        let configuration = TransactionCellConfiguration(
            category: tx.category,
            title: tx.title,
            date: tx.date,
            value: tx.amount,
            transactionType: tx.type,
            transactionMode: tx.mode,
            installmentNumber: tx.installmentNumber,
            totalInstallments: tx.totalInstallments
        )
        cell.configure(with: configuration)
        
        cell.onDelete = { [weak self] completion in
            guard let self = self else { return }
            
            let transactionType = self.viewModel.getTransactionType(id: tx.id!)
            
            if transactionType == .simple {
                // Handle simple transactions with basic confirmation
                showConfirmation(
                    title: "transaction.delete.title".localized,
                    message: "delete.confirmation".localized,
                    okTitle: "alert.delete".localized
                ) {
                    switch self.viewModel.deleteTransaction(id: tx.id!) {
                    case .success:
                        self.handleTransactionDeletionSuccess(at: indexPath, transactionId: tx.id!)
                        completion(true)
                    case .failure(let error):
                        print(error)
                        completion(false)
                    }
                } onCancel: {
                    completion(false)
                }
            } else {
                // Handle complex transactions with user choice
                self.showTransactionDeletionOptions(
                    transactionId: tx.id!,
                    transactionType: transactionType,
                    indexPath: indexPath,
                    completion: completion
                )
            }
        }
        cell.selectionStyle = .none
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 67
    }
    
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        return nil
    }
}

private struct DeletionPromptContent {
    let title: String
    let message: String
    let allTitle: String
    let futureTitle: String
}

extension DashboardViewController {
    func cleanupWithUserPrompt() {
        viewModel.cleanupRecurringTransactionsWithUserPrompt { [weak self] completion in
            let alertController = UIAlertController(
                title: "recurring.cleanup.title".localized,
                message: "recurring.cleanup.message".localized,
                preferredStyle: .alert
            )
            
            let cleanAllAction = UIAlertAction(
                title: "recurring.cleanup.all".localized,
                style: .destructive
            ) { _ in
                completion(.all)
                self?.loadData()
            }
            
            let cleanFutureAction = UIAlertAction(
                title: "recurring.cleanup.future".localized,
                style: .default
            ) { _ in
                completion(.futureOnly)
                self?.loadData()
            }
            
            let cancelAction = UIAlertAction(
                title: "alert.cancel".localized,
                style: .cancel
            )
            
            alertController.addAction(cleanAllAction)
            alertController.addAction(cleanFutureAction)
            alertController.addAction(cancelAction)
            
            self?.present(alertController, animated: true)
        }
    }
    
    private func showTransactionDeletionOptions(
        transactionId: Int,
        transactionType: TransactionComplexityType,
        indexPath: IndexPath,
        completion: @escaping (Bool) -> Void
    ) {
        let content = getDeletionPromptContent(for: transactionType)
        
        let alertController = UIAlertController(
            title: content.title,
            message: content.message,
            preferredStyle: .alert
        )
        
        let deleteAllAction = UIAlertAction(
            title: content.allTitle,
            style: .destructive
        ) { [weak self] _ in
            self?.performComplexTransactionDeletion(
                transactionId: transactionId,
                cleanupOption: .all,
                indexPath: indexPath,
                completion: completion
            )
        }
        
        let deleteFutureAction = UIAlertAction(
            title: content.futureTitle,
            style: .default
        ) { [weak self] _ in
            self?.performComplexTransactionDeletion(
                transactionId: transactionId,
                cleanupOption: .futureOnly,
                indexPath: indexPath,
                completion: completion
            )
        }
        
        let cancelAction = UIAlertAction(
            title: "alert.cancel".localized,
            style: .cancel
        ) { _ in
            completion(false)
        }
        
        alertController.addAction(deleteAllAction)
        alertController.addAction(deleteFutureAction)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true)
    }
    
    private func getDeletionPromptContent(for transactionType: TransactionComplexityType)
    -> DeletionPromptContent {
        switch transactionType {
        case .recurringParent, .recurringInstance:
            return DeletionPromptContent(
                title: "recurring.delete.title".localized,
                message: "recurring.delete.message".localized,
                allTitle: "recurring.delete.all".localized,
                futureTitle: "recurring.delete.future".localized
            )
        case .installmentParent, .installmentInstance:
            return DeletionPromptContent(
                title: "installment.delete.title".localized,
                message: "installment.delete.message".localized,
                allTitle: "installment.delete.all".localized,
                futureTitle: "installment.delete.remaining".localized
            )
        case .simple:
            return DeletionPromptContent(
                title: "transaction.delete.title".localized,
                message: "delete.confirmation".localized,
                allTitle: "alert.delete".localized,
                futureTitle: "alert.delete".localized
            )
        }
    }
    
    private func performComplexTransactionDeletion(
        transactionId: Int,
        cleanupOption: RecurringCleanupOption,
        indexPath: IndexPath,
        completion: @escaping (Bool) -> Void
    ) {
        viewModel.deleteComplexTransaction(
            transactionId: transactionId,
            cleanupOption: cleanupOption
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.handleTransactionDeletionSuccess(at: indexPath, transactionId: transactionId)
                    completion(true)
                case .failure(let error):
                    print("Error deleting complex transaction: \(error)")
                    completion(false)
                }
            }
        }
    }
    
    private func handleTransactionDeletionSuccess(at indexPath: IndexPath, transactionId: Int) {
        syncedViewModel.removeTransaction(withId: transactionId)
        
        currentCell?.transactions.remove(at: indexPath.row)
        currentCell?.transactionTableView.beginUpdates()
        currentCell?.transactionTableView.deleteRows(at: [indexPath], with: .automatic)
        currentCell?.transactionTableView.endUpdates()
        
        let newCount = currentCell?.transactions.count ?? 0
        currentCell?.updateTableHeight(txsCount: newCount)
        currentCell?.toggleEmptyState(newCount == 0)
        loadData()
    }
}
