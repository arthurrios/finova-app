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
    
    // MARK: - Tab Items
    private enum TabItem: Int, CaseIterable {
        case dashboard = 0
        case budgets = 1
        case add = 2
        case categories = 3
        case settings = 4
        
        var title: String {
            switch self {
            case .dashboard: return ""
            case .budgets: return ""
            case .add: return ""
            case .categories: return ""
            case .settings: return ""
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
        positionTabButtons()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Ensure buttons are positioned after layout
        positionTabButtons()
    }
    
    private func setupTabBar() {
        delegate = self
        
        // Create placeholder view controllers for now
        let dashboardVC = createPlaceholderViewController(title: "Dashboard", icon: "home")
        let budgetsVC = createPlaceholderViewController(title: "Budgets", icon: "wallet")
        let addVC = createPlaceholderViewController(title: "", icon: "")
        let categoriesVC = createPlaceholderViewController(title: "Categories", icon: "tag")
        let settingsVC = createPlaceholderViewController(title: "Settings", icon: "settingsOutlinedIcon")
        
        viewControllers = [dashboardVC, budgetsVC, addVC, categoriesVC, settingsVC]
        
        // Set initial tab
        selectedIndex = 0
    }
    
    private func setupTabBarContainer() {
        // Create a container view for the tab bar with padding
        tabBarContainerView.backgroundColor = Colors.gray700
        tabBarContainerView.layer.cornerRadius = 25 // Smaller radius for smaller height
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
            tabBarContainerView.heightAnchor.constraint(equalToConstant: 50) // Smaller height for better visual hierarchy
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
        print("Creating \(items.count) tab buttons")
        
        for (index, item) in items.enumerated() {
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
            
            // Set initial frame - consistent 24pt size
            button.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
            
            // Remove debug background
            button.backgroundColor = UIColor.clear
            
            customTabBarView.addSubview(button)
            tabButtons.append(button)
            print("Created button for \(item.iconName) at index \(index)")
        }
    }
    
    private func positionTabButtons() {
        let items = TabItem.allCases.filter { $0 != .add }
        let containerWidth = tabBarContainerView.bounds.width
        let buttonSize: CGFloat = 24
        
        // Create space in the middle for the plus button
        // Divide the container into 5 sections: left1, left2, center(plus), right1, right2
        let sectionWidth = containerWidth / 5
        
        print("Positioning \(tabButtons.count) buttons in container width: \(containerWidth), section width: \(sectionWidth)")
        
        for (index, button) in tabButtons.enumerated() {
            var xPosition: CGFloat
            
            // Position buttons with space in the middle for plus button
            switch index {
            case 0: // Dashboard (leftmost)
                xPosition = sectionWidth * 0.5
            case 1: // Budgets (left of center)
                xPosition = sectionWidth * 1.5
            case 2: // Categories (right of center)
                xPosition = sectionWidth * 3.5
            case 3: // Settings (rightmost)
                xPosition = sectionWidth * 4.5
            default:
                xPosition = 0
            }
            
            let yPosition = (tabBarContainerView.bounds.height - buttonSize) / 2 // Center vertically
            
            // Ensure consistent button size
            button.frame = CGRect(x: xPosition - buttonSize/2, y: yPosition, width: buttonSize, height: buttonSize)
            
            // Ensure proper image sizing
            button.imageView?.contentMode = .scaleAspectFit
            
            print("Positioned button \(index) at x: \(xPosition - buttonSize/2), y: \(yPosition), size: \(buttonSize)x\(buttonSize)")
        }
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
        // TabItem: dashboard=0, budgets=1, add=2, categories=3, settings=4
        // But we exclude 'add' from our buttons, so the mapping is:
        // Button 0 (dashboard) -> selectedIndex 0
        // Button 1 (budgets) -> selectedIndex 1  
        // Button 3 (categories) -> selectedIndex 2
        // Button 4 (settings) -> selectedIndex 3
        let selectedIndex: Int
        switch buttonTag {
        case 0: // dashboard
            selectedIndex = 0
        case 1: // budgets
            selectedIndex = 1
        case 3: // categories
            selectedIndex = 2
        case 4: // settings
            selectedIndex = 3
        default:
            selectedIndex = 0
        }
        
        self.selectedIndex = selectedIndex
        
        // Update button colors with magenta for selected, gray for unselected
        for (index, button) in tabButtons.enumerated() {
            let buttonTag = button.tag
            let isSelected: Bool
            switch buttonTag {
            case 0: // dashboard
                isSelected = selectedIndex == 0
            case 1: // budgets
                isSelected = selectedIndex == 1
            case 3: // categories
                isSelected = selectedIndex == 2
            case 4: // settings
                isSelected = selectedIndex == 3
            default:
                isSelected = false
            }
            button.tintColor = isSelected ? Colors.mainMagenta : Colors.gray100
        }
        
        customDelegate?.didSelectTab(at: selectedIndex)
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
        let buttonSize: CGFloat = 72 // Bigger than the bar (50pt bar, 56pt button)
        
        // Perfect center alignment with the tab bar container
        let centerX = containerFrame.midX - buttonSize / 2
        let centerY = containerFrame.midY - buttonSize / 2 // Center vertically with the tab bar
        
        floatingActionButton.frame = CGRect(
            x: centerX,
            y: centerY,
            width: buttonSize,
            height: buttonSize
        )
        
        print("Floating button positioned at x: \(centerX), y: \(centerY), container center: \(containerFrame.midX)")
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
        //
    }
}
