//
//  CustomTabBarController.swift
//  Finova
//
//  Created by Arthur Rios on 01/08/25.
//

import UIKit

class CustomTabBarController: UITabBarController {
    
    // MARK: - Properties
    weak var customDelegate: CustomTabBarControllerDelegate?
    
    private let floatingActionButton = FloatingActionButton()
    private let tabBarContainerView = UIView()
    private let customTabBarView = UIView()
    private var tabButtons: [UIButton] = []
    private var tabLabels: [UILabel] = []
    private var tabContainers: [UIView] = []
    
    // Properties for dynamic constraint management
    private var buttonWidthConstraints: [UIButton: (small: NSLayoutConstraint, big: NSLayoutConstraint)] = [:]
    private var buttonHeightConstraints: [UIButton: (small: NSLayoutConstraint, big: NSLayoutConstraint)] = [:]
    private var buttonTopConstraints: [UIButton: NSLayoutConstraint] = [:]
    private var buttonCenterYConstraints: [UIButton: NSLayoutConstraint] = [:]
    private var labelVerticalConstraints: [UILabel: (top: NSLayoutConstraint, bottom: NSLayoutConstraint)] = [:]
    
    // Track selected tab index
    private var customSelectedIndex: Int = 0
    
    // MARK: - Tab Items
    private enum TabItem: Int, CaseIterable {
        case dashboard = 0
        case budgets = 1
        case add = 2
        case categories = 3
        case settings = 4
        
        var title: String {
            switch self {
            case .dashboard: return "dashboard.tab".localized
            case .budgets: return "budgets.tab".localized
            case .add: return ""
            case .categories: return "categories.tab".localized
            case .settings: return "settings.tab".localized
            }
        }
        
        var iconName: String {
            switch self {
            case .dashboard: return "home"
            case .budgets: return "wallet"
            case .add: return ""
            case .categories: return "tag"
            case .settings: return "settingsOutlinedIcon"
            }
        }
    }
    
    // MARK: - Initialization
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        setupTabBar()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabBar()
        setupTabBarContainer()
        setupCustomTabBar()
        setupFloatingActionButton()
        hideOriginalTabBar()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        positionFloatingActionButton()
        // Positioning is now handled by Auto Layout constraints
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Positioning is now handled by Auto Layout constraints
    }
    
    private func setupTabBar() {
        delegate = self
        
        // Create real view controllers using the factory
        let dashboardVC = createRealDashboardViewController()
        let budgetsVC = createRealBudgetsViewController()
        let addVC = createPlaceholderViewController(title: "", icon: "")
        let categoriesVC = createRealCategoriesViewController()
        let settingsVC = createRealSettingsViewController()
        
        viewControllers = [dashboardVC, budgetsVC, addVC, categoriesVC, settingsVC]
        
        // Set initial tab
        customSelectedIndex = 0
    }
    
    private func createRealDashboardViewController() -> UIViewController {
        // Use the factory to create the real dashboard
        let dashboardVC = ViewControllersFactory().makeDashboardViewController(flowDelegate: self)
        
        // Remove the add transaction button from the dashboard view
        // The DashboardViewController has a contentView property that is DashboardView
        if let dashboardViewController = dashboardVC as? DashboardViewController {
            dashboardViewController.contentView.removeAddTransactionButton()
        }
        
        return dashboardVC
    }
    
    private func createRealBudgetsViewController() -> UIViewController {
        return ViewControllersFactory().makeBudgetsViewController(flowDelegate: self, date: nil)
    }
    
    private func createRealCategoriesViewController() -> UIViewController {
        return ViewControllersFactory().makeCategoriesViewController(flowDelegate: self)
    }
    
    private func createRealSettingsViewController() -> UIViewController {
        return ViewControllersFactory().makeSettingsViewController(flowDelegate: self)
    }
    
    private func setupTabBarContainer() {
        // Create a container view for the tab bar with padding
        tabBarContainerView.backgroundColor = Colors.gray700
        tabBarContainerView.layer.cornerRadius = 27.5 // Half of the height (55/2) for fully rounded sides
        tabBarContainerView.layer.masksToBounds = false // Allow shadow to show
        
        // Add shadow to match the floating button
        tabBarContainerView.layer.shadowColor = UIColor.black.cgColor
        tabBarContainerView.layer.shadowOffset = CGSize(width: 0, height: 6)
        tabBarContainerView.layer.shadowOpacity = 0.3
        tabBarContainerView.layer.shadowRadius = 8
        tabBarContainerView.layer.shouldRasterize = true
        tabBarContainerView.layer.rasterizationScale = UIScreen.main.scale
        
        tabBarContainerView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(tabBarContainerView)
        
        // Position the container with more padding to make it smaller in width
        NSLayoutConstraint.activate([
            tabBarContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Metrics.spacing8), // More padding
            tabBarContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Metrics.spacing8), // More padding
            tabBarContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Metrics.spacing3),
            tabBarContainerView.heightAnchor.constraint(equalToConstant: 55) // Slightly increased height for labels
        ])
    }
    
    private func setupCustomTabBar() {
        customTabBarView.translatesAutoresizingMaskIntoConstraints = false
        tabBarContainerView.addSubview(customTabBarView)
        
        // Create custom tab buttons
        createTabButtons()
        
        // Position custom tab bar within container
        NSLayoutConstraint.activate([
            customTabBarView.topAnchor.constraint(equalTo: tabBarContainerView.topAnchor),
            customTabBarView.leadingAnchor.constraint(equalTo: tabBarContainerView.leadingAnchor),
            customTabBarView.trailingAnchor.constraint(equalTo: tabBarContainerView.trailingAnchor),
            customTabBarView.bottomAnchor.constraint(equalTo: tabBarContainerView.bottomAnchor)
        ])
    }
    
    private func createTabButtons() {
        let items = TabItem.allCases.filter { $0 != .add } // Exclude add button
        
        // Create a horizontal stack view for the tab items
        let tabStackView = UIStackView()
        tabStackView.axis = .horizontal
        tabStackView.distribution = .equalSpacing
        tabStackView.alignment = .center
        tabStackView.translatesAutoresizingMaskIntoConstraints = false
        
        customTabBarView.addSubview(tabStackView)
        
        // Add constraints for the stack view
        NSLayoutConstraint.activate([
            tabStackView.leadingAnchor.constraint(equalTo: customTabBarView.leadingAnchor, constant: 10), // Less padding to push left stack more left
            tabStackView.trailingAnchor.constraint(equalTo: customTabBarView.trailingAnchor, constant: -10), // Less padding to push right stack more left
            tabStackView.centerYAnchor.constraint(equalTo: customTabBarView.centerYAnchor)
        ])
        
        // Create left group stack view
        let leftGroupStack = UIStackView()
        leftGroupStack.axis = .horizontal
        leftGroupStack.distribution = .equalSpacing
        leftGroupStack.alignment = .center
        leftGroupStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Create right group stack view
        let rightGroupStack = UIStackView()
        rightGroupStack.axis = .horizontal
        rightGroupStack.distribution = .equalSpacing
        rightGroupStack.alignment = .center
        rightGroupStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Add groups to main stack view
        tabStackView.addArrangedSubview(leftGroupStack)
        
        // Add center spacing view for plus button
        let centerSpacingView = UIView()
        centerSpacingView.translatesAutoresizingMaskIntoConstraints = false
        tabStackView.addArrangedSubview(centerSpacingView)
        NSLayoutConstraint.activate([
            centerSpacingView.widthAnchor.constraint(equalToConstant: 80) // Space for plus button
        ])
        
        tabStackView.addArrangedSubview(rightGroupStack)
        
        for (index, item) in items.enumerated() {
            // Create container view for icon and label
            let containerView = UIView()
            containerView.translatesAutoresizingMaskIntoConstraints = false
            
            // Create icon button
            let button = UIButton(type: .system)
            button.setImage(UIImage(named: item.iconName), for: .normal)
            
            // Set initial color based on button tag (not array index)
            let buttonTag = item.rawValue
            let isSelected: Bool
            switch buttonTag {
            case 0: // dashboard
                isSelected = true // Dashboard is initially selected
            case 1: // budgets
                isSelected = false
            case 3: // categories
                isSelected = false
            case 4: // settings
                isSelected = false
            default:
                isSelected = false
            }
            button.tintColor = isSelected ? Colors.mainMagenta : Colors.gray100
            
            button.tag = item.rawValue
            button.addTarget(self, action: #selector(tabButtonTapped(_:)), for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            
            // Create label
            let label = UILabel()
            label.text = item.title
            label.font = Fonts.title2XS.font // Use the smallest available font
            label.textColor = isSelected ? Colors.mainMagenta : Colors.gray100
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            label.isHidden = !isSelected // Hide label if not selected
            label.tag = item.rawValue // Use same tag as button for easy lookup
            
            // Add button and label to container
            containerView.addSubview(button)
            containerView.addSubview(label)
            
            // Common horizontal centering for button
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            ])

            // Label horizontal constraints (always active)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            ])

            // Create all possible constraints, but don't activate yet
            let buttonWidthSmall = button.widthAnchor.constraint(equalToConstant: 18)
            let buttonHeightSmall = button.heightAnchor.constraint(equalToConstant: 18)
            let buttonWidthBig = button.widthAnchor.constraint(equalToConstant: 24)
            let buttonHeightBig = button.heightAnchor.constraint(equalToConstant: 24)
            
            let buttonTop = button.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 3)
            let buttonCenterY = button.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
            
            let labelTop = label.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 2)
            let labelBottom = label.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -3)

            // Store constraints
            buttonWidthConstraints[button] = (small: buttonWidthSmall, big: buttonWidthBig)
            buttonHeightConstraints[button] = (small: buttonHeightSmall, big: buttonHeightBig)
            buttonTopConstraints[button] = buttonTop
            buttonCenterYConstraints[button] = buttonCenterY
            labelVerticalConstraints[label] = (top: labelTop, bottom: labelBottom)

            // Activate initial state
            if isSelected {
                buttonWidthSmall.isActive = true
                buttonHeightSmall.isActive = true
                buttonTop.isActive = true
                labelTop.isActive = true
                labelBottom.isActive = true
            } else {
                buttonWidthBig.isActive = true
                buttonHeightBig.isActive = true
                buttonCenterY.isActive = true
            }
            
            // Set container size constraints
            NSLayoutConstraint.activate([
                containerView.widthAnchor.constraint(equalToConstant: 60),
                containerView.heightAnchor.constraint(equalToConstant: 40)
            ])
            
            // Add to appropriate group based on index
            if index < 2 { // Dashboard and Budgets go to left group
                leftGroupStack.addArrangedSubview(containerView)
            } else { // Categories and Settings go to right group
                rightGroupStack.addArrangedSubview(containerView)
            }
            
            tabButtons.append(button)
            tabLabels.append(label)
            tabContainers.append(containerView)
        }
    }
    
    private func positionTabButtons() {
        // This method is no longer needed since we're using Auto Layout constraints
        // The positioning is now handled in positionContainer method
    }
    
    private func updateCustomTabBarLayout() {
        // Update button positions when container size changes
        let items = TabItem.allCases.filter { $0 != .add }
        let containerWidth = tabBarContainerView.frame.width
        let buttonSpacing = containerWidth / CGFloat(items.count + 1)
        
        for (index, button) in tabButtons.enumerated() {
            let xPosition = buttonSpacing * CGFloat(index + 1)
            button.frame.origin.x = xPosition - button.frame.width / 2
            button.frame.origin.y = (tabBarContainerView.frame.height - button.frame.height) / 2
        }
    }
    
    private func hideOriginalTabBar() {
        tabBar.isHidden = true
    }
    
    @objc private func tabButtonTapped(_ sender: UIButton) {
        let buttonTag = sender.tag
        
        // Map button tag to the correct tab index
        let newSelectedIndex: Int
        switch buttonTag {
        case 0: // dashboard
            newSelectedIndex = 0
        case 1: // budgets
            newSelectedIndex = 1
        case 3: // categories
            newSelectedIndex = 3
        case 4: // settings
            newSelectedIndex = 4
        default:
            newSelectedIndex = customSelectedIndex // Should not happen
        }
        
        // Only update if selection changed
        guard newSelectedIndex != customSelectedIndex else { return }
        customSelectedIndex = newSelectedIndex
        
        // Update the UITabBarController's selectedIndex for proper navigation
        self.selectedIndex = newSelectedIndex
        
        // Update button colors, label visibility, and icon sizes/positions
        for (index, button) in tabButtons.enumerated() {
            let currentButtonTag = button.tag
            let isSelected = (currentButtonTag == customSelectedIndex)
            
            button.tintColor = isSelected ? Colors.mainMagenta : Colors.gray100
            
            // Find corresponding label
            let label = tabLabels.first { $0.tag == currentButtonTag }
            
            // Deactivate current constraints
            buttonTopConstraints[button]?.isActive = false
            buttonCenterYConstraints[button]?.isActive = false
            buttonWidthConstraints[button]?.small.isActive = false
            buttonWidthConstraints[button]?.big.isActive = false
            buttonHeightConstraints[button]?.small.isActive = false
            buttonHeightConstraints[button]?.big.isActive = false
            
            if let label = label {
                labelVerticalConstraints[label]?.top.isActive = false
                labelVerticalConstraints[label]?.bottom.isActive = false
                
                // Update label visibility and color
                label.textColor = isSelected ? Colors.mainMagenta : Colors.gray100
                label.isHidden = !isSelected
                
                // Activate new constraints based on selection
                if isSelected {
                    buttonTopConstraints[button]?.isActive = true
                    buttonWidthConstraints[button]?.small.isActive = true
                    buttonHeightConstraints[button]?.small.isActive = true
                    labelVerticalConstraints[label]?.top.isActive = true
                    labelVerticalConstraints[label]?.bottom.isActive = true
                } else {
                    buttonCenterYConstraints[button]?.isActive = true
                    buttonWidthConstraints[button]?.big.isActive = true
                    buttonHeightConstraints[button]?.big.isActive = true
                }
            }
        }
        
        // Animate layout changes
        UIView.animate(withDuration: 0.2) {
            self.customTabBarView.layoutIfNeeded()
        }
        
        // Notify delegate
        customDelegate?.didSelectTab(at: customSelectedIndex)
    }
    
    private func setupFloatingActionButton() {
        floatingActionButton.delegate = self
        view.addSubview(floatingActionButton) // Add to main view instead of container
        
        // Set button size constraints to match dashboard add button
        NSLayoutConstraint.activate([
            floatingActionButton.widthAnchor.constraint(equalToConstant: 72),
            floatingActionButton.heightAnchor.constraint(equalToConstant: 72)
        ])
    }
    
    private func positionFloatingActionButton() {
        // Position the floating button centered with the tab bar container
        let containerFrame = tabBarContainerView.frame
        let buttonSize: CGFloat = 72 // Bigger than the bar (50pt bar, 72pt button)
        
        // Perfect center alignment with the tab bar container
        let centerX = containerFrame.midX - buttonSize / 2
        let centerY = containerFrame.midY - buttonSize / 2 // Center vertically with the tab bar
        
        floatingActionButton.frame = CGRect(
            x: centerX,
            y: centerY,
            width: buttonSize,
            height: buttonSize
        )
        
    }
    
    private func createPlaceholderViewController(title: String, icon: String) -> UIViewController {
        let viewController = UIViewController()
        viewController.tabBarItem = UITabBarItem(
            title: title,
            image: UIImage(named: icon),
            selectedImage: UIImage(named: icon)
        )
        
        // Add a simple label to show which tab this is
        let label = UILabel()
        label.text = title.isEmpty ? "Add transaction" : title
        label.textAlignment = .center
        label.font = Fonts.titleLG.font
        label.textColor = Colors.gray700
        label.translatesAutoresizingMaskIntoConstraints = false
        
        viewController.view.backgroundColor = Colors.gray200
        viewController.view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor)
        ])
        
        return viewController
    }
}

// MARK: - UITabBarControllerDelegate
extension CustomTabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if let index = viewControllers?.firstIndex(of: viewController), index == 2 {
            return false
        }
        return true
    }
    
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if let index = viewControllers?.firstIndex(of: viewController) {
            customDelegate?.didSelectTab(at: index)
        }
    }
}

// MARK: - CustomTabBarControllerDelegate
extension CustomTabBarController: CustomTabBarControllerDelegate {
    func didSelectTab(at index: Int) {
        //
    }
    
    func didTapFloatingActionButton() {
        let addTransactionVC = ViewControllersFactory().makeAddTransactionModalViewController(flowDelegate: self)
        
        // Present as a normal view that covers the entire screen
        addTransactionVC.modalPresentationStyle = .overCurrentContext
        addTransactionVC.modalTransitionStyle = .crossDissolve
        
        present(addTransactionVC, animated: true)
    }
}

// MARK: - Flow Delegates
extension CustomTabBarController: DashboardFlowDelegate {
    func logout() {
        // Handle logout
        customDelegate?.didSelectTab(at: -1) // Signal logout
    }
    
    func navigateToBudgets(date: Date?) {
        // Navigate to budgets tab
        customSelectedIndex = 1
        self.selectedIndex = 1
    }
    
    func openAddTransactionModal() {
        // This is now handled by the floating button
        didTapFloatingActionButton()
    }
    
    func navigateToSettings() {
        // Navigate to settings
        customSelectedIndex = 4 // Settings tab
        self.selectedIndex = 4
    }
}

extension CustomTabBarController: BudgetsFlowDelegate {
    func navBackToDashboard() {
        // Navigate back to dashboard
        customSelectedIndex = 0
        self.selectedIndex = 0
    }
}

extension CustomTabBarController: CategoriesFlowDelegate {
    func navigateToSubCategoryManagement() {
        // Handle sub-category management
    }
    
    func navigateToSubCategoryCreation(parentCategory: TransactionCategory?) {
        // Handle sub-category creation
    }
    
    func navigateToBudgetAllocation(for month: Date) {
        // Handle budget allocation navigation
    }
    
    func navigateBackToDashboard() {
        // Navigate back to dashboard
        customSelectedIndex = 0
        self.selectedIndex = 0
    }
}

extension CustomTabBarController: SettingsFlowDelegate {
    func dismissSettings() {
        // Navigate back to dashboard
        customSelectedIndex = 0
        self.selectedIndex = 0
    }
    
    // Remove duplicate logout method - use the one from DashboardFlowDelegate
}

extension CustomTabBarController: AddTransactionModalFlowDelegate {
    func didAddTransaction() {
        // Handle transaction added
        dismiss(animated: true) {
            // Refresh the dashboard data after modal is dismissed
            self.refreshDashboardData()
        }
    }
    
    private func refreshDashboardData() {
        // Get the current dashboard view controller
        if let dashboardVC = viewControllers?[0] as? DashboardViewController {
            // Trigger a refresh of the dashboard data
            dashboardVC.refreshDashboardData()
        }
    }
}
