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
  }

  func sceneWillResignActive(_ scene: UIScene) {
    // Called when the scene will move from an active state to an inactive state.
    // This may occur due to temporary interruptions (ex. an incoming phone call).
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    // Called as the scene transitions from the background to the foreground.
    // Use this method to undo the changes made on entering the background.
    print("🔄 Scene will enter foreground - triggering app refresh")
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
    print("🔄 Starting comprehensive app refresh...")
    print("🔄 App refresh triggered at: \(Date())")

    // Add a small delay to ensure the app is fully loaded and ready
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      // Refresh the dashboard if it's currently visible
      self.refreshDashboardIfVisible()

      // Trigger any other app-wide refresh logic
      self.performAppWideRefresh()
    }
  }

  /// Refreshes the dashboard if it's currently the top view controller
  private func refreshDashboardIfVisible() {
    guard let navigationController = window?.rootViewController as? UINavigationController else {
      print("🔄 No navigation controller found for refresh")
      return
    }

    // Check if the top view controller is the dashboard
    if let dashboardViewController = navigationController.topViewController
      as? DashboardViewController
    {
      print("🔄 Dashboard is visible - triggering refresh")
      dashboardViewController.refreshAfterTransactionAdd()
    } else {
      print("🔄 Dashboard not visible - skipping dashboard refresh")
    }
  }

  /// Performs app-wide refresh operations
  private func performAppWideRefresh() {
    print("🔄 Performing app-wide refresh operations...")

    // Post a notification that the app has entered foreground
    // This can be used by other parts of the app that need to refresh
    NotificationCenter.default.post(name: .appDidEnterForeground, object: nil)

    // Any other app-wide refresh logic can be added here
    // For example: refresh cached data, check for updates, etc.
  }

}
