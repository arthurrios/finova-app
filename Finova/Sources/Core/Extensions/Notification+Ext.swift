//
//  Notification+Ext.swift
//  FinanceApp
//
//  Created by Arthur Rios on 10/06/25.
//

import Foundation

extension Notification.Name {
  static let transactionDataChanged = Notification.Name("transactionDataChanged")
  static let appDidEnterForeground = Notification.Name("appDidEnterForeground")
  static let navigateToTransactionDetails = Notification.Name("navigateToTransactionDetails")
  static let currencyDidChange = Notification.Name("currencyDidChange")
  static let navigateToStatementDetails = Notification.Name("navigateToStatementDetails")
  static let cloudKitRemoteNotificationReceived = Notification.Name("cloudKitRemoteNotificationReceived")
  static let syncStatusDidChange = Notification.Name("syncStatusDidChange")
  static let budgetGroupDataChanged = Notification.Name("budgetGroupDataChanged")
  static let groupInvitationReceived = Notification.Name("groupInvitationReceived")
  static let navigateToGroupInvitation = Notification.Name("navigateToGroupInvitation")
  static let groupMemberActionOccurred = Notification.Name("groupMemberActionOccurred")
  static let budgetDataChanged = Notification.Name("budgetDataChanged")
  static let creditCardDataChanged = Notification.Name("creditCardDataChanged")
  static let syncPushProgressDidChange = Notification.Name("syncPushProgressDidChange")
  static let syncPhaseProgressDidChange = Notification.Name("syncPhaseProgressDidChange")
  static let syncRequiresLoadingScreen = Notification.Name("syncRequiresLoadingScreen")
  static let localSyncableDataDidChange = Notification.Name("localSyncableDataDidChange")
  static let allocationTagsChanged = Notification.Name("allocationTagsChanged")
  static let valueVisibilityDidChange = Notification.Name("valueVisibilityDidChange")
}
