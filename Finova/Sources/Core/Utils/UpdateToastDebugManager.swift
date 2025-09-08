//
//  UpdateToastDebugManager.swift
//  FinanceApp
//
//  Created by Arthur Rios on [Current Date]
//

import Foundation
import UIKit

#if DEBUG
  final class UpdateToastDebugManager {
    static let shared = UpdateToastDebugManager()

    private init() {}

    /// Show debug menu for update toast testing
    func showDebugMenu(from viewController: UIViewController) {
      let alert = UIAlertController(
        title: "🧪 Update Toast Debug",
        message: "Test update toast functionality",
        preferredStyle: .actionSheet
      )

      let forceShowAction = UIAlertAction(title: "🚀 Force Show Toast", style: .default) { _ in
        UpdateToastManager.shared.forceShowToastForTesting()
      }

      let setMockVersionAction = UIAlertAction(title: "📱 Set Mock Version", style: .default) { _ in
        self.showVersionInputAlert(from: viewController)
      }

      let resetStateAction = UIAlertAction(title: "🔄 Reset State", style: .destructive) { _ in
        UpdateToastManager.shared.resetTestingState()
        self.showSuccessAlert(from: viewController, message: "Testing state reset successfully")
      }

      let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

      alert.addAction(forceShowAction)
      alert.addAction(setMockVersionAction)
      alert.addAction(resetStateAction)
      alert.addAction(cancelAction)

      // For iPad
      if let popover = alert.popoverPresentationController {
        popover.sourceView = viewController.view
        popover.sourceRect = CGRect(
          x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0,
          height: 0)
        popover.permittedArrowDirections = []
      }

      viewController.present(alert, animated: true)
    }

    private func showVersionInputAlert(from viewController: UIViewController) {
      let alert = UIAlertController(
        title: "Set Mock Version",
        message: "Enter a version number (e.g., 1.1.0)",
        preferredStyle: .alert
      )

      alert.addTextField { textField in
        textField.placeholder = "1.1.0"
        textField.keyboardType = .decimalPad
      }

      let setAction = UIAlertAction(title: "Set", style: .default) { _ in
        if let version = alert.textFields?.first?.text, !version.isEmpty {
          UpdateToastManager.shared.setMockLatestVersion(version)
          self.showSuccessAlert(from: viewController, message: "Mock version set to \(version)")
        }
      }

      let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

      alert.addAction(setAction)
      alert.addAction(cancelAction)

      viewController.present(alert, animated: true)
    }

    private func showSuccessAlert(from viewController: UIViewController, message: String) {
      let alert = UIAlertController(
        title: "✅ Success",
        message: message,
        preferredStyle: .alert
      )

      alert.addAction(UIAlertAction(title: "OK", style: .default))
      viewController.present(alert, animated: true)
    }
  }
#endif
