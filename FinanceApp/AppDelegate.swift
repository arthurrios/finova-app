//
//  AppDelegate.swift
//  FinanceApp
//
//  Created by Arthur Rios on 07/05/25.
//

import Firebase
import GoogleSignIn
import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureFirebase()
    registerForNotifications()
    return true
  }

  // MARK: UISceneSession Lifecycle

  func application(
    _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return UISceneConfiguration(
      name: "Default Configuration", sessionRole: connectingSceneSession.role)
  }

  func application(
    _ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>
  ) {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
  }

  private func configureFirebase() {
    guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") else {
      print(
        "⚠️ GoogleService-Info.plist not found - Firebase configuration skipped (likely in test environment)"
      )
      return
    }

    if FileManager.default.fileExists(atPath: path) {
      print("🔥 Configuring Firebase...")
      FirebaseApp.configure()
      print("✅ Firebase configured successfully")

      // Verify Firebase is working
      if let app = FirebaseApp.app() {
        print("✅ Firebase app instance: \(app)")
        print("✅ Firebase project ID: \(app.options.projectID ?? "Unknown")")
      } else {
        print("❌ Firebase app instance is nil!")
      }

      // Test Auth instance
      let auth = Auth.auth()
      print("✅ Firebase Auth instance: \(auth)")

      // Configure Google Sign-In
      guard let plist = NSDictionary(contentsOfFile: path),
        let clientId = plist["CLIENT_ID"] as? String
      else {
        print("⚠️ CLIENT_ID not found in GoogleService-Info.plist")
        return
      }

      print("🔑 CLIENT_ID: \(clientId)")
      GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
      print("✅ Google Sign-In configured successfully")

      #if DEBUG
        // AuthTestHelper.testAuthenticationFlow()
      #endif
    } else {
      print("⚠️ GoogleService-Info.plist file not accessible - Firebase configuration skipped")
    }
  }

  func registerForNotifications() {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if granted {
        print("User granted permission for notifications")
      } else if let error = error {
        print("\(error) - User did not grant permission for notifications")
      }
    }
  }
}
