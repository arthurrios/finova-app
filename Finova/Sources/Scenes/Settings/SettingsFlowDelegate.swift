//
//  SettingsFlowDelegate.swift
//  Finova
//
//  Created by Arthur Rios on 17/07/25.
//

public protocol SettingsFlowDelegate: AnyObject {
    func dismissSettings()
    func logout()
    func settingsDidAppear()
}
