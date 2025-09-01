//
//  DashboardViewController.swift
//  FinanceApp
//
//  Created by Arthur Rios on 09/05/25.
//

import Foundation
import ShimmerView
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
  private var isInitialLoadComplete = false

  private var currentCell: MonthCarouselCell?
  weak var flowDelegate: DashboardFlowDelegate?

  // MARK: - Shimmer State Tracking
  private var cardsWithActiveShimmer: Set<Int> = []

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
    setupCollectionViews()
    syncedViewModel.selectMonth(at: todayMonthIndex, animated: false)
    contentView.frame = view.bounds

    // Verificar e agendar notificações automaticamente
    checkAndScheduleNotificationsIfNeeded()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    // Evitar refresh desnecessário na primeira vez que a view aparece
    if isInitialLoadComplete {
      refreshDashboardData()
    }
  }

  private func refreshDashboardData() {
    print("🔄 Refreshing dashboard data...")

    // Load fresh data from repositories
    let monthData = viewModel.loadMonthlyCards()
    let transactions = viewModel.transactionRepo.fetchTransactions()

    // Update the view models with fresh data
    syncedViewModel.setMonthData(monthData)
    syncedViewModel.setTransactions(transactions)

    // Schedule notifications for any new transactions in the next 30 days
    scheduleNext30DaysNotifications()

    // Force refresh the current visible cell if it exists
    if let currentCell = currentCell {
      let selectedIndex = syncedViewModel.selectedIndex
      if selectedIndex < monthData.count {
        let currentMonthData = monthData[selectedIndex]

        // Refresh the month budget card with fresh data
        currentCell.monthCard.refresh(with: currentMonthData)

        // Update transactions for the current cell
        let key = DateFormatter.keyFormatter.string(from: currentMonthData.date)
        let filteredTransactions = transactions.filter { tx in
          let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
          let txKey = DateFormatter.keyFormatter.string(from: txDate)
          return txKey == key
        }.sorted { $0.date > $1.date }

        // Use the configure method to properly update the cell
        currentCell.configure(with: currentMonthData, transactions: filteredTransactions)

        print("✅ Refreshed current cell at index \(selectedIndex)")
      }
    }

    // Also refresh all visible cells in the collection view
    DispatchQueue.main.async {
      self.refreshVisibleCells()
    }
  }

  private func refreshVisibleCells() {
    let visibleIndexPaths = contentView.monthCarousel.indexPathsForVisibleItems

    for indexPath in visibleIndexPaths {
      if let cell = contentView.monthCarousel.cellForItem(at: indexPath) as? MonthCarouselCell {
        if indexPath.item < syncedViewModel.monthData.count {
          let monthData = syncedViewModel.monthData[indexPath.item]

          // Refresh the month budget card
          cell.monthCard.refresh(with: monthData)

          // Update transactions
          let key = DateFormatter.keyFormatter.string(from: monthData.date)
          let filteredTransactions = syncedViewModel.allTransactions.filter { tx in
            let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
            let txKey = DateFormatter.keyFormatter.string(from: txDate)
            return txKey == key
          }.sorted { $0.date > $1.date }

          cell.configure(with: monthData, transactions: filteredTransactions)
        }
      }
    }

    print("✅ Refreshed all visible cells")
  }

  /// Called when a transaction is added to immediately refresh the dashboard
  func refreshAfterTransactionAdd() {
    print("🔄 Refreshing dashboard after transaction addition...")

    // For transaction addition, we need to be more conservative since we don't know
    // which months will be affected (installments/recurring can span many months)
    // Show shimmer only on current card initially, then comprehensive cleanup
    showShimmerOnCurrentCard()

    // For recurring/installment transactions, we need to ensure generation is complete
    // Add a small delay to allow backend processing to complete
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      // Load fresh data after backend processing
      let monthData = self.viewModel.loadMonthlyCards()
      let transactions = self.viewModel.transactionRepo.fetchTransactions()

      // Update the view models
      self.syncedViewModel.setMonthData(monthData)
      self.syncedViewModel.setTransactions(transactions)

      // Schedule notifications for any new transactions in the next 30 days
      self.scheduleNext30DaysNotifications()

      // Force refresh the UI with animation
      DispatchQueue.main.async {
        self.refreshVisibleCellsWithAnimation()

        // Use comprehensive cleanup since installments might affect non-visible months
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
          self.hideShimmerOnAllCards()
        }
      }
    }
  }

  private func refreshVisibleCellsWithAnimation() {
    let visibleIndexPaths = contentView.monthCarousel.indexPathsForVisibleItems

    for indexPath in visibleIndexPaths {
      if let cell = contentView.monthCarousel.cellForItem(at: indexPath) as? MonthCarouselCell {
        if indexPath.item < syncedViewModel.monthData.count {
          let monthData = syncedViewModel.monthData[indexPath.item]

          // Animate the refresh
          UIView.transition(with: cell.monthCard, duration: 0.3, options: .transitionCrossDissolve)
          {
            cell.monthCard.refresh(with: monthData)
          }

          // Update transactions with animation
          let key = DateFormatter.keyFormatter.string(from: monthData.date)
          let filteredTransactions = syncedViewModel.allTransactions.filter { tx in
            let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
            let txKey = DateFormatter.keyFormatter.string(from: txDate)
            return txKey == key
          }.sorted { $0.date > $1.date }

          // Animate table view update
          UIView.transition(
            with: cell.transactionTableView, duration: 0.3, options: .transitionCrossDissolve
          ) {
            cell.configure(with: monthData, transactions: filteredTransactions)
          }
        }
      }
    }

    print("✅ Refreshed all visible cells with animation")
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    LoadingManager.shared.hideLoading()

    // Check if we should show notification success alert
    checkAndShowNotificationSuccessAlert()

    #if DEBUG
      // Add notification debugging on dashboard appear
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        self.debugNotificationSystem()
      }
    #endif
  }

  /// Check if we should show notification success alert and show it if needed
  private func checkAndShowNotificationSuccessAlert() {
    let shouldShowAlert = UserDefaults.standard.bool(forKey: "shouldShowNotificationSuccessAlert")

    if shouldShowAlert {
      // Clear the flag first
      UserDefaults.standard.set(false, forKey: "shouldShowNotificationSuccessAlert")

      // Get the alert type if specified
      let alertType = UserDefaults.standard.string(forKey: "notificationAlertType") ?? "success"

      // Show the appropriate alert
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {  // Small delay to ensure dashboard is fully loaded
        let monthlyManager = MonthlyNotificationManager()

        switch alertType {
        case "rescheduled":
          monthlyManager.showRescheduledAlert()
        case "failure":
          monthlyManager.showFailureAlert()
        case "permission":
          monthlyManager.showPermissionDeniedAlert()
        default:
          monthlyManager.showSuccessAlert()
        }

        // Clear the alert type
        UserDefaults.standard.removeObject(forKey: "notificationAlertType")
      }
    }
  }

  #if DEBUG
    private func debugNotificationSystem() {
      // Run comprehensive notification debugging
      DebugDataManager.shared.debugNotificationSystem()

      // Also show current pending notifications
      viewModel.debugPendingNotifications()
    }

    private func debugBalanceMonitoring() {
      // Run comprehensive balance monitoring debugging using dashboard data
      let balanceMonitor = BalanceMonitorManager()

      // Get current month data from the dashboard
      if let currentMonthData = syncedViewModel.getCurrentMonthData() {
        balanceMonitor.debugBalanceMonitoring(with: currentMonthData)
      } else {
        // Fallback to regular debug if no dashboard data available
        balanceMonitor.debugBalanceMonitoring()
      }
    }

    private func forceTriggerBalanceMonitoring() {
      // Force trigger balance monitoring
      let balanceMonitor = BalanceMonitorManager()
      balanceMonitor.forceTriggerBalanceMonitoring()
    }

    private func clearBalanceNotifications() {
      // Clear all negative balance notifications
      let balanceMonitor = BalanceMonitorManager()
      balanceMonitor.clearAllNegativeBalanceNotifications()

      // Show confirmation alert
      let alert = UIAlertController(
        title: "🧹 Notifications Cleared",
        message: "All negative balance notifications have been cleared.",
        preferredStyle: .alert
      )

      alert.addAction(UIAlertAction(title: "OK", style: .default))
      present(alert, animated: true)
    }

    private func testTomorrowNegativeBalanceAlert() {
      // Test tomorrow's negative balance notification
      let balanceMonitor = BalanceMonitorManager()
      balanceMonitor.testTomorrowNegativeBalanceNotification()

      // Show confirmation alert
      let alert = UIAlertController(
        title: "🧪 Test Notification Scheduled",
        message: "A test notification for tomorrow's negative balance will appear in 5 seconds.",
        preferredStyle: .alert
      )

      alert.addAction(UIAlertAction(title: "OK", style: .default))
      present(alert, animated: true)
    }

    private func testNegativeBalanceAlertIn1Minute() {
      // Test negative balance notification in 1 minute
      let balanceMonitor = BalanceMonitorManager()
      balanceMonitor.testNegativeBalanceNotificationIn1Minute()

      // Show confirmation alert
      let alert = UIAlertController(
        title: "🧪 Test Notification Scheduled",
        message: "A test negative balance notification will appear in 1 minute.",
        preferredStyle: .alert
      )

      alert.addAction(UIAlertAction(title: "OK", style: .default))
      present(alert, animated: true)
    }

    /// Reset notification state for testing
    private func resetNotificationStateForTesting() {
      // Clear all notification-related UserDefaults
      UserDefaults.standard.removeObject(forKey: "lastScheduledMonthKey")
      UserDefaults.standard.removeObject(forKey: "shouldShowNotificationSuccessAlert")
      UserDefaults.standard.removeObject(forKey: "notificationAlertType")

      print("🔔 🧪 Reset notification state for testing")

      // Show confirmation alert
      let alert = UIAlertController(
        title: "🧪 Notification State Reset",
        message:
          "Notification state has been reset. The next time you open the app, it should trigger the monthly notification setup.",
        preferredStyle: .alert
      )

      alert.addAction(UIAlertAction(title: "OK", style: .default))
      present(alert, animated: true)
    }
  #endif

  private func setup() {
    view.addSubview(contentView)
    buildHierarchy()

    contentView.delegate = self
    syncedViewModel.delegate = self

    // Setup notification observers for transaction data changes
    setupNotificationObservers()

    #if DEBUG
      setupDebugGestures()
    #endif
  }

  private func setupNotificationObservers() {
    // Listen for transaction data changes to invalidate ledger cache
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleTransactionDataChanged),
      name: .transactionDataChanged,
      object: nil
    )
  }

  @objc private func handleTransactionDataChanged() {
    print("🔄 Transaction data changed, invalidating ledger cache...")

    // Refresh current month balance specifically
    viewModel.transactionLedger.refreshCurrentMonthBalance()

    // Debug: Check for duplicate transactions
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      self.viewModel.debugDuplicateTransactions()
    }

    // Refresh the dashboard data
    DispatchQueue.main.async {
      self.refreshDashboardData()
    }
  }

  #if DEBUG
    private func setupDebugGestures() {
      // Add long press gesture to trigger notification debugging
      let longPressGesture = UILongPressGestureRecognizer(
        target: self, action: #selector(handleLongPress))
      longPressGesture.minimumPressDuration = 2.0
      view.addGestureRecognizer(longPressGesture)
    }

    @objc private func handleLongPress() {
      let alertController = UIAlertController(
        title: "🔔 Debug Notifications",
        message: "Choose a debugging action:",
        preferredStyle: .actionSheet
      )

      let debugAction = UIAlertAction(title: "🔍 Run Full Debug", style: .default) { _ in
        self.debugNotificationSystem()
      }

      let balanceDebugAction = UIAlertAction(title: "💰 Debug Balance Monitoring", style: .default) {
        _ in
        self.debugBalanceMonitoring()
      }

      let forceBalanceAction = UIAlertAction(title: "⚡ Force Balance Monitoring", style: .default) {
        _ in
        self.forceTriggerBalanceMonitoring()
      }

      let clearNotificationsAction = UIAlertAction(
        title: "🧹 Clear Balance Notifications", style: .default
      ) { _ in
        self.clearBalanceNotifications()
      }

      let testTomorrowAction = UIAlertAction(title: "🧪 Test Tomorrow's Alert (5s)", style: .default)
      { _ in
        self.testTomorrowNegativeBalanceAlert()
      }

      let test1MinAction = UIAlertAction(title: "🧪 Test Alert in 1 Minute", style: .default) { _ in
        self.testNegativeBalanceAlertIn1Minute()
      }

      let testAction = UIAlertAction(title: "📡 Test Notification (5s)", style: .default) { _ in
        DebugDataManager.shared.testNotificationNow()
      }

      let rescheduleAction = UIAlertAction(title: "🔄 Force Reschedule All", style: .default) { _ in
        DebugDataManager.shared.forceRescheduleNotifications()
      }

      let resetAction = UIAlertAction(title: "🧪 Reset Notification State", style: .default) { _ in
        self.resetNotificationStateForTesting()
      }

      let duplicateAnalysisAction = UIAlertAction(title: "🔍 Analyze Duplicates", style: .default) {
        _ in
        self.analyzeDuplicateTransactions()
      }

      let duplicateCleanupAction = UIAlertAction(title: "🧹 Clean Duplicates", style: .default) {
        _ in
        self.cleanupDuplicateTransactions()
      }

      let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

      alertController.addAction(debugAction)
      alertController.addAction(balanceDebugAction)
      alertController.addAction(forceBalanceAction)
      alertController.addAction(clearNotificationsAction)
      alertController.addAction(testTomorrowAction)
      alertController.addAction(test1MinAction)
      alertController.addAction(testAction)
      alertController.addAction(rescheduleAction)
      alertController.addAction(resetAction)
      alertController.addAction(duplicateAnalysisAction)
      alertController.addAction(duplicateCleanupAction)
      alertController.addAction(cancelAction)

      present(alertController, animated: true)
    }
  #endif

  // MARK: - Duplicate Transaction Management

  private func analyzeDuplicateTransactions() {
    let analysis = viewModel.analyzeDuplicateTransactions()

    let alert = UIAlertController(
      title: "🔍 Duplicate Analysis",
      message: analysis,
      preferredStyle: .alert
    )

    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }

  private func cleanupDuplicateTransactions() {
    let alert = UIAlertController(
      title: "🧹 Clean Duplicates",
      message: "This will remove all duplicate transactions. Are you sure?",
      preferredStyle: .alert
    )

    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(
      UIAlertAction(title: "Clean", style: .destructive) { _ in
        self.viewModel.cleanupExistingDuplicates()

        // Show completion alert
        let completionAlert = UIAlertController(
          title: "✅ Cleanup Complete",
          message:
            "Duplicate transactions have been removed. The dashboard will refresh automatically.",
          preferredStyle: .alert
        )
        completionAlert.addAction(UIAlertAction(title: "OK", style: .default))
        self.present(completionAlert, animated: true)
      })

    present(alert, animated: true)
  }

  private func buildHierarchy() {
    setupContentViewToBounds(contentView: contentView, respectingSafeArea: false)
  }

  func loadData() {
    print("📱 DashboardViewController.loadData() called")

    // Get user from UID-based settings first, fallback to global UserDefaults
    var displayUser: User?

    // First try to get Firebase user and set current UID if needed
    if let firebaseUser = AuthenticationManager.shared.currentUser {
      // Ensure current UID is set
      UIDUserDefaultsManager.shared.currentUserUID = firebaseUser.uid
      print("🔧 Set current UID to: \(firebaseUser.uid)")

      // Try to get UID-based settings
      if let uidSettings = UIDUserDefaultsManager.shared.getUserSettings(for: firebaseUser.uid) {
        displayUser = User(
          firebaseUID: firebaseUser.uid,
          name: uidSettings.name,
          email: uidSettings.email,
          isUserSaved: uidSettings.isUserSaved,
          hasFaceIdEnabled: uidSettings.hasFaceIdEnabled
        )
        print(
          "📱 Dashboard loading UID-based user: '\(uidSettings.name)' with UID: '\(firebaseUser.uid)'"
        )
      } else {
        // No UID settings found, check global and migrate
        if let globalUser = UserDefaultsManager.getUserWithUID() {
          displayUser = globalUser
          print(
            "📱 Dashboard loading global user: '\(globalUser.name)' with UID: '\(globalUser.firebaseUID ?? "nil")'"
          )

          // Migrate to UID-based system if same user
          if globalUser.firebaseUID == firebaseUser.uid {
            let userSettings = UserSettings(
              name: globalUser.name,
              email: globalUser.email,
              hasFaceIdEnabled: globalUser.hasFaceIdEnabled,
              isUserSaved: globalUser.isUserSaved
            )
            UIDUserDefaultsManager.shared.saveUserSettings(
              for: firebaseUser.uid, settings: userSettings)
            print("✅ Migrated user settings to UID-based system")
          }
        } else {
          // Create basic user from Firebase
          displayUser = User(
            firebaseUID: firebaseUser.uid,
            name: firebaseUser.displayName ?? "User",
            email: firebaseUser.email ?? "",
            isUserSaved: true,
            hasFaceIdEnabled: false
          )
          print("📱 Created basic user from Firebase: '\(displayUser!.name)'")
        }
      }
    }
    // Fallback to UID-based settings with stored current UID
    else if let currentUID = UIDUserDefaultsManager.shared.currentUserUID,
      let uidSettings = UIDUserDefaultsManager.shared.getUserSettings(for: currentUID)
    {
      displayUser = User(
        firebaseUID: currentUID,
        name: uidSettings.name,
        email: uidSettings.email,
        isUserSaved: uidSettings.isUserSaved,
        hasFaceIdEnabled: uidSettings.hasFaceIdEnabled
      )
      print("📱 Dashboard loading UID-based user: '\(uidSettings.name)' with UID: '\(currentUID)'")
    }
    // Final fallback to global UserDefaults
    else if let globalUser = UserDefaultsManager.getUserWithUID() {
      displayUser = globalUser
      print(
        "📱 Dashboard loading global user: '\(globalUser.name)' with UID: '\(globalUser.firebaseUID ?? "nil")'"
      )
    }

    if let user = displayUser {
      // 🔒 Authenticate SecureLocalDataManager for UID-isolated data access
      if let firebaseUID = user.firebaseUID {
        SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)
        print("🔒 SecureLocalDataManager authenticated for user: \(firebaseUID)")
      }

      contentView.welcomeTitleLabel.text = "dashboard.welcomeTitle".localized + "\(user.name)!"
      contentView.welcomeTitleLabel.applyStyle()
      print("📱 Dashboard welcome text set to: '\(contentView.welcomeTitleLabel.text ?? "nil")'")
    } else {
      print("❌ Dashboard: No user found in any UserDefaults system")
      contentView.welcomeTitleLabel.text = "dashboard.welcomeTitle".localized + "User!"
    }

    if let userImage = SecureLocalDataManager.shared.loadProfileImage() {
      contentView.avatar.userImage = userImage
    }

    transactions = viewModel.transactionRepo.fetchTransactions()

    let monthData = viewModel.loadMonthlyCards()

    syncedViewModel.setMonthData(monthData)
    syncedViewModel.setTransactions(transactions)

    // Analyze and clean up any existing duplicate transactions
    let analysis = viewModel.analyzeDuplicateTransactions()
    print(analysis)

    viewModel.cleanupExistingDuplicates()

    contentView.monthCarousel.layoutIfNeeded()

    // Marcar que o carregamento inicial foi concluído
    isInitialLoadComplete = true
    isLoadingInitialData = false

    print("✅ Initial data loading completed")
  }

  private func setupCollectionViews() {
    // Verificar se já foi configurado
    guard contentView.monthSelectorView.collectionView.delegate == nil else {
      print("⏭️ Collection views already configured, skipping setup")
      return
    }

    print("🔄 Setting up collection views...")

    contentView.monthSelectorView.collectionView.delegate = self
    contentView.monthSelectorView.collectionView.dataSource = self
    contentView.monthSelectorView.collectionView.register(
      MonthCell.self, forCellWithReuseIdentifier: MonthCell.reuseID)
    contentView.monthSelectorView.delegate = self

    contentView.monthCarousel.delegate = self
    contentView.monthCarousel.dataSource = self
    contentView.monthCarousel.register(
      MonthCarouselCell.self, forCellWithReuseIdentifier: MonthCarouselCell.reuseID)

    // Don't configure month selector here - let it be configured through didUpdateMonthData
    // This ensures consistency between month data and month selector

    contentView.monthCarousel.reloadData()

    contentView.monthSelectorView.layoutIfNeeded()
    contentView.monthCarousel.layoutIfNeeded()

    print("✅ Collection views setup completed")
  }
}

extension DashboardViewController: DashboardViewDelegate {
  func didTapSettings() {
    self.flowDelegate?.navigateToSettings()
  }

  func didTapProfileImage() {
    selectProfileImage()
  }

  func didTapAddTransaction() {
    self.flowDelegate?.openAddTransactionModal()
  }

  func logout() {
    AuthenticationManager.shared.signOut()
    SecureLocalDataManager.shared.signOut()
    UserDefaultsManager.signOutCurrentUser()

    print("✅ Complete logout performed")
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
      SecureLocalDataManager.shared.saveProfileImage(editedImage)
    } else if let originalImage = info[.originalImage] as? UIImage {
      contentView.avatar.userImage = originalImage
      SecureLocalDataManager.shared.saveProfileImage(originalImage)
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
    -> Int
  {
    return syncedViewModel.monthData.count
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
    -> UICollectionViewCell
  {
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
        let firstCell = visibleCells.first
      {
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

      // Clean up any lingering shimmer when user scrolls to new month
      if !cardsWithActiveShimmer.isEmpty {
        print(
          "🔄 Cleaning up \(cardsWithActiveShimmer.count) cards with lingering shimmer after scroll")
        hideShimmerOnAllCards()
      }

      // Only run emergency cleanup occasionally to avoid interference
      // Check if there are any visible shimmer views that shouldn't be there
      let hasOrphanedShimmer = contentView.monthCarousel.visibleCells.contains { cell in
        if let monthCell = cell as? MonthCarouselCell {
          return monthCell.monthCard.viewWithTag(998) != nil
        }
        return false
      }

      if hasOrphanedShimmer {
        print("🚨 Found orphaned shimmer views, cleaning up")
        emergencyShimmerCleanup()
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

    // Verificar se os dados realmente mudaram antes de reconfigurar
    let currentMonths = contentView.monthSelectorView.months
    let newMonths = data.map { $0.month }
    let monthsChanged = currentMonths != newMonths

    print("🔍 didUpdateMonthData called with \(data.count) items")
    print("🔍 New months array: \(newMonths)")

    // Check for duplicates in the incoming data
    let uniqueMonths = Set(newMonths)
    if uniqueMonths.count != newMonths.count {
      print("⚠️ DUPLICATES FOUND in incoming data!")
      let duplicates = newMonths.filter { month in
        newMonths.filter { $0 == month }.count > 1
      }
      print("⚠️ Duplicate months: \(Array(Set(duplicates)))")

      // Check if the issue is in the data itself
      print("🔍 Checking MonthBudgetCardType data:")
      for (index, card) in data.enumerated() {
        print("  \(index): \(card.date) -> \(card.month)")
      }
    }

    if monthsChanged {
      contentView.monthSelectorView.configure(
        months: newMonths, selectedIndex: currentSelectedIndex)
    }

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

    DispatchQueue.main.async {
      self.contentView.hideShimmerViewsAndShowOriginals()
      self.isLoadingInitialData = false
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
          // For simple transactions, only show shimmer on the current month card
          self.showShimmerOnCurrentCard()

          switch self.viewModel.deleteTransaction(id: tx.id!) {
          case .success:
            self.handleTransactionDeletionSuccess(at: indexPath, transactionId: tx.id!)
            completion(true)
          case .failure(let error):
            print(error)
            // Hide shimmer on error
            self.hideShimmerOnAllCards()
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

// MARK: - Loading State Management
extension DashboardViewController {
  private func showDeletionLoadingOverlay() {
    // Reuse existing shimmer views from the dashboard for consistent UX
    guard let currentCell = currentCell else { return }

    // Create a subtle overlay to indicate deletion is in progress
    let overlay = UIView()
    overlay.backgroundColor = UIColor.black.withAlphaComponent(0.1)
    overlay.tag = 999  // Unique tag for removal
    overlay.translatesAutoresizingMaskIntoConstraints = false

    currentCell.transactionTableView.addSubview(overlay)
    NSLayoutConstraint.activate([
      overlay.topAnchor.constraint(equalTo: currentCell.transactionTableView.topAnchor),
      overlay.leadingAnchor.constraint(equalTo: currentCell.transactionTableView.leadingAnchor),
      overlay.trailingAnchor.constraint(equalTo: currentCell.transactionTableView.trailingAnchor),
      overlay.bottomAnchor.constraint(equalTo: currentCell.transactionTableView.bottomAnchor),
    ])

    // Disable table view interaction during deletion
    currentCell.transactionTableView.isUserInteractionEnabled = false

    // Add a subtle fade animation
    overlay.alpha = 0
    UIView.animate(withDuration: 0.3) {
      overlay.alpha = 1
    }
  }

  private func hideDeletionLoadingOverlay() {
    guard let currentCell = currentCell else { return }

    // Re-enable table view interaction
    currentCell.transactionTableView.isUserInteractionEnabled = true

    // Remove the overlay with animation
    if let overlay = currentCell.transactionTableView.viewWithTag(999) {
      UIView.animate(
        withDuration: 0.3,
        animations: {
          overlay.alpha = 0
        }
      ) { _ in
        overlay.removeFromSuperview()
      }
    }
  }

  // MARK: - Shimmer Loading for Budget Cards

  private func showShimmerLoadingOnCard(_ card: MonthBudgetCard) {
    // Prevent multiple shimmer views
    if card.viewWithTag(998) != nil {
      return
    }

    // Create a shimmer overlay that matches the card design
    let shimmerView = ShimmerView()
    shimmerView.style = ShimmerViewStyle(
      baseColor: Colors.gray700.withAlphaComponent(0.3),
      highlightColor: Colors.gray400.withAlphaComponent(0.6),
      duration: 1.0,
      interval: 0.3,
      effectSpan: .points(120),
      effectAngle: 0 * CGFloat.pi
    )

    shimmerView.layer.cornerRadius = CornerRadius.extraLarge
    shimmerView.clipsToBounds = true
    shimmerView.tag = 998  // Unique tag for removal
    shimmerView.translatesAutoresizingMaskIntoConstraints = false

    card.addSubview(shimmerView)
    NSLayoutConstraint.activate([
      shimmerView.topAnchor.constraint(equalTo: card.topAnchor),
      shimmerView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
      shimmerView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
      shimmerView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
    ])

    shimmerView.startAnimating()

    // Fade in the shimmer
    shimmerView.alpha = 0
    UIView.animate(withDuration: 0.2) {
      shimmerView.alpha = 1
    }
  }

  private func hideShimmerLoadingOnCard(_ card: MonthBudgetCard) {
    guard let shimmerView = card.viewWithTag(998) as? ShimmerView else {
      return
    }

    // Ensure we're on the main queue
    DispatchQueue.main.async {
      UIView.animate(
        withDuration: 0.3,
        animations: {
          shimmerView.alpha = 0
        }
      ) { _ in
        shimmerView.stopAnimating()
        shimmerView.removeFromSuperview()
      }
    }
  }

  // MARK: - Multi-Card Shimmer Management

  private func showShimmerOnCurrentCard() {
    guard let currentCell = currentCell else { return }

    // Get the current month index
    let visibleIndexPaths = contentView.monthCarousel.indexPathsForVisibleItems
    if let currentIndexPath = visibleIndexPaths.first {
      showShimmerLoadingOnCard(currentCell.monthCard)
      cardsWithActiveShimmer.insert(currentIndexPath.item)
    }

    // Safety mechanism for single card
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
      print("⚠️ Single card shimmer safety timeout triggered")
      self.hideShimmerOnAllCards()
    }
  }

  private func showShimmerOnAllVisibleCards() {
    let visibleIndexPaths = contentView.monthCarousel.indexPathsForVisibleItems

    for indexPath in visibleIndexPaths {
      if let cell = contentView.monthCarousel.cellForItem(at: indexPath) as? MonthCarouselCell {
        showShimmerLoadingOnCard(cell.monthCard)
        cardsWithActiveShimmer.insert(indexPath.item)
      }
    }

    // Safety mechanism: ensure shimmer doesn't get stuck for more than 3 seconds
    // This is only a fallback - normal operation should hide shimmer immediately after data updates
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
      print("⚠️ Shimmer safety timeout triggered after 3 seconds - investigating potential issue")
      self.hideShimmerOnAllCards()
    }
  }

  private func hideShimmerOnAllVisibleCards() {
    let visibleIndexPaths = contentView.monthCarousel.indexPathsForVisibleItems

    for indexPath in visibleIndexPaths {
      // Only try to hide shimmer on cards that we know have shimmer
      if cardsWithActiveShimmer.contains(indexPath.item),
        let cell = contentView.monthCarousel.cellForItem(at: indexPath) as? MonthCarouselCell
      {
        hideShimmerLoadingOnCard(cell.monthCard)
        cardsWithActiveShimmer.remove(indexPath.item)
      }
    }
  }

  private func hideShimmerOnAllCards() {
    // Hide shimmer on all cards that might have it, not just visible ones
    print("🔄 Cleaning up shimmer on all potentially affected cards")

    // First try visible cards
    hideShimmerOnAllVisibleCards()

    // For comprehensive cleanup, we need a different approach for non-visible cells
    // We'll schedule a cleanup that triggers when users scroll to affected months
    if !cardsWithActiveShimmer.isEmpty {
      print("🔄 Scheduling cleanup for \(cardsWithActiveShimmer.count) cards with potential shimmer")

      // Force cleanup by trying to access cells that might exist
      for cardIndex in cardsWithActiveShimmer {
        let indexPath = IndexPath(item: cardIndex, section: 0)
        if let cell = contentView.monthCarousel.cellForItem(at: indexPath) as? MonthCarouselCell {
          hideShimmerLoadingOnCard(cell.monthCard)
        }
      }
    }

    // Clear all tracking regardless
    cardsWithActiveShimmer.removeAll()

    // Add an additional safety mechanism: clean up any shimmer views that might be orphaned
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      self.emergencyShimmerCleanup()
    }
  }

  private func emergencyShimmerCleanup() {
    // Last resort cleanup - remove any shimmer views that might be stuck
    print("🚨 Emergency shimmer cleanup triggered")

    // Check all currently loaded cells for shimmer views
    for case let cell as MonthCarouselCell in contentView.monthCarousel.visibleCells {
      if let shimmerView = cell.monthCard.viewWithTag(998) {
        shimmerView.removeFromSuperview()
        print("🧹 Removed orphaned shimmer view")
      }
    }
  }
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
    -> DeletionPromptContent
  {
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
    // Show loading state for complex deletions that might affect multiple transactions
    showDeletionLoadingOverlay()

    // Complex transactions (recurring/installments) can affect multiple months
    showShimmerOnAllVisibleCards()

    viewModel.deleteComplexTransaction(
      transactionId: transactionId,
      cleanupOption: cleanupOption
    ) { [weak self] result in
      DispatchQueue.main.async {
        self?.hideDeletionLoadingOverlay()

        switch result {
        case .success:
          self?.handleTransactionDeletionSuccess(at: indexPath, transactionId: transactionId)
          completion(true)
        case .failure(let error):
          print("Error deleting complex transaction: \(error)")
          // Hide shimmer on error
          self?.hideShimmerOnAllCards()
          completion(false)
        }
      }
    }
  }

  private func handleTransactionDeletionSuccess(at indexPath: IndexPath, transactionId: Int) {
    // Ensure we're on main queue for UI updates
    DispatchQueue.main.async {
      guard self.currentCell != nil else {
        self.loadData()
        return
      }

      // Shimmer is already shown before deletion starts - no need to show again
      // For recurring transactions, multiple rows might be affected
      // Instead of trying to manually sync, reload the fresh data and update safely
      self.refreshAfterTransactionDeletion()

      // Hide shimmer after a brief moment to let users see the data has updated
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        self.hideShimmerOnAllCards()
      }
    }
  }

  private func refreshAfterTransactionDeletion() {
    print("🔄 Refreshing dashboard after transaction deletion...")

    // Load fresh data immediately
    let monthData = viewModel.loadMonthlyCards()
    let transactions = viewModel.transactionRepo.fetchTransactions()

    // Update the view models
    syncedViewModel.setMonthData(monthData)
    syncedViewModel.setTransactions(transactions)

    // Update current cell data safely
    if let currentCell = currentCell {
      let currentIndex = contentView.monthCarousel.indexPathsForVisibleItems.first?.item ?? 0

      if currentIndex < syncedViewModel.monthData.count {
        let monthData = syncedViewModel.monthData[currentIndex]
        let key = DateFormatter.keyFormatter.string(from: monthData.date)

        let filteredTransactions = syncedViewModel.allTransactions.filter { tx in
          let txDate = Date(timeIntervalSince1970: TimeInterval(tx.dateTimestamp))
          let txKey = DateFormatter.keyFormatter.string(from: txDate)
          return txKey == key
        }.sorted { $0.date > $1.date }

        // Safely update the cell with new transaction data
        currentCell.configure(with: monthData, transactions: filteredTransactions)
      }
    }

    // Force refresh visible cells with animation for any other visible cells
    refreshVisibleCellsWithAnimation()
  }

  // MARK: - Automatic Notification Scheduling

  /// Verifica e agenda notificações automaticamente quando necessário
  private func checkAndScheduleNotificationsIfNeeded() {
    let status = viewModel.checkMonthlyNotificationsStatus()

    switch status {
    case .notConfigured:
      print("🔔 📅 No notifications configured, scheduling automatically...")
      scheduleNotificationsAutomatically()

    case .outdated:
      print("🔔 📅 Notifications are outdated, updating...")
      scheduleNotificationsAutomatically()

    case .configured:
      print("🔔 📅 Notifications are already configured for this month")
      break
    }
  }

  /// Agenda notificações automaticamente sem interação do usuário
  private func scheduleNotificationsAutomatically() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      self.scheduleNext30DaysNotifications()
    }
  }

  /// Smart notification scheduling for the next 30 days
  private func scheduleNext30DaysNotifications() {
    print("🔔 📅 Starting smart notification scheduling for next 30 days...")

    // Check if user is authenticated first
    guard let user = UserDefaultsManager.getUser(),
      let firebaseUID = user.firebaseUID
    else {
      print("🔔 ❌ Cannot schedule notifications: User not authenticated")
      return
    }

    // Authenticate SecureLocalDataManager
    SecureLocalDataManager.shared.authenticateUser(firebaseUID: firebaseUID)

    // Get all transactions
    let allTxs = viewModel.transactionRepo.fetchAllTransactions()
    let now = Date()
    var calendar = Calendar.current
    calendar.timeZone = TimeZone.current

    // Filter for future transactions in next 30 days (excluding hidden parent transactions)
    let thirtyDaysFromNow = calendar.date(byAdding: .day, value: 30, to: now) ?? now

    let next30DaysTxs = allTxs.filter { tx in
      // Skip parent transactions that are not visible in UI
      if tx.hasInstallments == true && tx.amount == 0 {
        return false
      }
      if tx.isRecurring == true && tx.parentTransactionId == nil && tx.amount == 0 {
        return false
      }

      // Create notification time (8 AM) in local timezone
      var notificationDate = calendar.startOfDay(for: tx.date)
      notificationDate =
        calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

      // Must be in future and within 30 days
      return notificationDate > now && tx.date <= thirtyDaysFromNow
    }.sorted { $0.date < $1.date }  // Sort by date (closest first)

    print("🔔 📅 Found \(next30DaysTxs.count) transactions in next 30 days")

    // Get currently pending notifications to avoid duplicates
    UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] requests in
      DispatchQueue.main.async {
        let existingNotificationIds = Set(requests.map { $0.identifier })

        // Schedule notifications for transactions that don't already have them
        var scheduledCount = 0
        var skippedCount = 0

        for tx in next30DaysTxs {
          guard let transactionId = tx.id else { continue }

          let notificationId = "transaction_\(transactionId)"

          if existingNotificationIds.contains(notificationId) {
            print("🔔 ⏭️ Skipping transaction \(tx.title) - notification already exists")
            skippedCount += 1
            continue
          }

          // Schedule the notification
          self?.scheduleNotificationForTransaction(tx, calendar: calendar)
          scheduledCount += 1

          // Respect iOS limit - stop at 50 total (but prioritize by date)
          if scheduledCount >= 50 {
            print("🔔 ⚠️ Reached iOS notification limit (50), stopping")
            break
          }
        }

        print("🔔 ✅ Smart scheduling complete:")
        print("🔔    📊 Scheduled: \(scheduledCount) new notifications")
        print("🔔    ⏭️ Skipped: \(skippedCount) existing notifications")
        print("🔔    📅 Total in next 30 days: \(next30DaysTxs.count)")

        // Clean up any duplicate notifications
        self?.removeDuplicateNotifications()
      }
    }
  }

  /// Schedule notification for a specific transaction
  private func scheduleNotificationForTransaction(_ tx: Transaction, calendar: Calendar) {
    guard let transactionId = tx.id else { return }

    let id = "transaction_\(transactionId)"

    // Create notification time (8 AM) in local timezone
    var notificationDate = calendar.startOfDay(for: tx.date)
    notificationDate =
      calendar.date(byAdding: .hour, value: 8, to: notificationDate) ?? notificationDate

    // Only schedule if notification time is in the future
    guard notificationDate > Date() else { return }

    let timeInterval = notificationDate.timeIntervalSinceNow
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

    let titleKey =
      tx.type == .income
      ? "notification.transaction.title.income" : "notification.transaction.title.expense"
    let bodyKey =
      tx.type == .income
      ? "notification.transaction.body.income" : "notification.transaction.body.expense"

    let amountString = tx.amount.currencyString
    let title = titleKey.localized
    let body = String(format: bodyKey.localized, amountString, tx.title)

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "TRANSACTION_REMINDER"
    content.userInfo = ["transactionId": transactionId, "date": tx.date.timeIntervalSince1970]

    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        print("🔔 ❌ Error scheduling notification for \(tx.title): \(error)")
      } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        print(
          "🔔 ✅ Scheduled notification for \(tx.title) at \(formatter.string(from: notificationDate))"
        )
      }
    }
  }

  /// Remove duplicate notifications based on content similarity
  private func removeDuplicateNotifications() {
    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      DispatchQueue.main.async {
        // Group notifications by content (title + body combination)
        var notificationGroups: [String: [UNNotificationRequest]] = [:]

        for request in requests {
          // Skip system notifications (monthly reminders, etc.)
          if request.identifier.contains("monthly_") || request.identifier.contains("test_") {
            continue
          }

          // Create a key based on title and body content
          let contentKey = "\(request.content.title)_\(request.content.body)"

          if notificationGroups[contentKey] == nil {
            notificationGroups[contentKey] = []
          }
          notificationGroups[contentKey]?.append(request)
        }

        // Find and remove duplicates
        var duplicatesFound = 0
        var idsToRemove: [String] = []

        for (contentKey, group) in notificationGroups {
          if group.count > 1 {
            print("🔔 🚨 Found \(group.count) duplicates for: \(contentKey)")
            duplicatesFound += group.count - 1

            // Keep the first one, remove the rest
            let duplicatesToRemove = Array(group.dropFirst())
            for duplicate in duplicatesToRemove {
              idsToRemove.append(duplicate.identifier)
              print("🔔 ❌ Will remove duplicate: \(duplicate.identifier)")
            }
          }
        }

        if duplicatesFound > 0 {
          print("🔔 🧹 Removing \(duplicatesFound) duplicate notifications...")
          UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: idsToRemove)
          print("🔔 ✅ Removed duplicate notifications")
        } else {
          print("🔔 ✅ No duplicate notifications found")
        }
      }
    }
  }
}
