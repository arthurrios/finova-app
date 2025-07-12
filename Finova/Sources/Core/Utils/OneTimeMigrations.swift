//
//  OneTimeMigrations.swift
//  FinanceApp
//
//  Created by Cursor on 27/01/25.
//

import Foundation

/// Handles one-time migrations and cleanup operations that should only run once
class OneTimeMigrations {

  static let shared = OneTimeMigrations()

  private init() {}

  /// Performs all necessary one-time migrations
  func performAllMigrations() {
    print("🔄 Checking for one-time migrations...")

    // Migration 1: Remove global profile images (v1.0.0)
    migrateGlobalProfileImages()

    print("✅ One-time migrations completed")
  }

  // MARK: - Individual Migrations

  private func migrateGlobalProfileImages() {
    let migrationKey = "migration_global_profile_images_removed_v1.0.0"

    if !UserDefaults.standard.bool(forKey: migrationKey) {
      print("🔄 Performing one-time global profile image cleanup...")

      // Remove all possible global profile image storage
      ProfileImageCleanup.shared.clearAllGlobalProfileImages()

      // Mark migration as completed
      UserDefaults.standard.set(true, forKey: migrationKey)
      UserDefaults.standard.synchronize()

      print("✅ Global profile image cleanup migration completed")
    } else {
      print("ℹ️ Global profile image cleanup already performed")
    }
  }
}
