//
//  SceneDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import GoogleSignIn
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

  var window: UIWindow?
  var flowController: AppFlowController?

  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = (scene as? UIWindowScene) else { return }
    let window = UIWindow(windowScene: windowScene)
    flowController = AppFlowController()
    let rootViewController = flowController?.startFlow()

    window.rootViewController = rootViewController
    self.window = window
    self.window?.makeKeyAndVisible()
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let url = URLContexts.first?.url else { return }
    GIDSignIn.sharedInstance.handle(url)
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    // Called as the scene is being released by the system.
    // This occurs shortly after the scene enters the background, or when its session is discarded.
    // Release any resources associated with this scene that can be re-created the next time the scene connects.
    // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    // Called when the scene has moved from an inactive state to an active state.
    // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.

    // Sync delivered notifications from notification center to history
    // This captures notifications that arrived while app was in background
    NotificationHistoryManager.shared.syncDeliveredNotifications()
  }

  func sceneWillResignActive(_ scene: UIScene) {
    // Called when the scene will move from an active state to an inactive state.
    // This may occur due to temporary interruptions (ex. an incoming phone call).
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    // Called as the scene transitions from the background to the foreground.
    // Use this method to undo the changes made on entering the background.
    logInfo("Scene will enter foreground - triggering app refresh")
    triggerAppRefresh()
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
    // Called as the scene transitions from the foreground to the background.
    // Use this method to save data, release shared resources, and store enough scene-specific state information
    // to restore the scene back to its current state.
  }

  // MARK: - App Refresh on Foreground

  /// Triggers a comprehensive app refresh when the app comes into the foreground
  private func triggerAppRefresh() {
    logInfo("Starting comprehensive app refresh...")

    // Add a small delay to ensure the app is fully loaded and ready
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      // First post the notification for app-wide refresh
      self.performAppWideRefresh()

      // Then refresh the dashboard if it's currently visible
      self.refreshDashboardIfVisible()
    }
  }

  /// Refreshes the dashboard if it's currently the top view controller
  private func refreshDashboardIfVisible() {
    guard let navigationController = window?.rootViewController as? UINavigationController else {
      logWarning("No navigation controller found for refresh")
      return
    }

    // Check if the top view controller is the dashboard
    if let dashboardViewController = navigationController.topViewController
      as? DashboardViewController
    {
      logDebug("Dashboard is visible - triggering refresh with animation")
      dashboardViewController.refreshOnForegroundWithAnimation()
    } else {
      logDebug("Dashboard not visible - skipping dashboard refresh")
    }
  }

  /// Performs app-wide refresh operations
  private func performAppWideRefresh() {
    logDebug("Performing app-wide refresh operations...")

    // Post a notification that the app has entered foreground
    // This can be used by other parts of the app that need to refresh
    NotificationCenter.default.post(name: .appDidEnterForeground, object: nil)

    // Check for app updates from App Store (works on any screen)
    checkForAppUpdates()
  }

  /// Check for app updates and show toast if newer version available
  private func checkForAppUpdates() {
    logDebug("Checking for app updates on foreground...")

    UpdateToastManager.shared.checkForUpdatesFromAppStore { [weak self] hasNewerVersion in
      guard hasNewerVersion else {
        logDebug("No newer version available")
        return
      }

      // Check if we should show the toast (respects cooldowns)
      guard UpdateToastManager.shared.shouldShowUpdateToast() else {
        logDebug("Update available but toast cooldown active")
        return
      }

      // Show the update toast on the current window
      DispatchQueue.main.async {
        self?.showUpdateToastOnCurrentWindow()
      }
    }
  }

  /// Shows the update toast on the current window regardless of which screen is visible
  private func showUpdateToastOnCurrentWindow() {
    guard let window = window else {
      logWarning("No window available to show update toast")
      return
    }

    // Check if toast is already being shown
    if window.viewWithTag(UpdateToastWindowTag) != nil {
      logDebug("Update toast already visible")
      return
    }

    let toastContainer = UpdateToastContainer()
    toastContainer.tag = UpdateToastWindowTag
    toastContainer.translatesAutoresizingMaskIntoConstraints = false

    window.addSubview(toastContainer)
    NSLayoutConstraint.activate([
      toastContainer.topAnchor.constraint(equalTo: window.topAnchor),
      toastContainer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
      toastContainer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
      toastContainer.bottomAnchor.constraint(equalTo: window.bottomAnchor),
    ])

    // Create a delegate handler for the toast
    let handler = UpdateToastWindowHandler(container: toastContainer)
    toastContainer.showUpdateToast(delegate: handler)
    UpdateToastManager.shared.markToastAsShown()

    // Store handler to prevent deallocation
    objc_setAssociatedObject(
      toastContainer, &AssociatedKeys.handlerKey, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

    logInfo("Update toast shown on window")
  }
}

// MARK: - Constants

private let UpdateToastWindowTag = 99999

// MARK: - Associated Keys for objc_setAssociatedObject

private struct AssociatedKeys {
  static var handlerKey = "updateToastHandlerKey"
}

// MARK: - Update Toast Window Handler

/// Handles update toast actions when shown from SceneDelegate (window-level)
private class UpdateToastWindowHandler: NSObject, UpdateToastViewDelegate {
  weak var container: UpdateToastContainer?

  init(container: UpdateToastContainer) {
    self.container = container
    super.init()
  }

  func updateToastViewDidTapUpdate(_ view: UpdateToastView) {
    UpdateToastManager.shared.openAppStore()
    hideToast()
  }

  func updateToastViewDidTapDismiss(_ view: UpdateToastView) {
    UpdateToastManager.shared.markToastAsDismissed()
    hideToast()
  }

  private func hideToast() {
    container?.hideUpdateToast(animated: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.container?.removeFromSuperview()
    }
  }

}
