//
//  ImportFlowDelegate.swift
//  Finova
//

import Foundation

protocol ImportFlowDelegate: AnyObject {
    /// The file parsed cleanly enough to review directly.
    func navigateToImportReview(file: LoadedFile, plan: ImportPlan)
    /// Inference was unsure about something structural; let the user correct it first.
    func navigateToImportMapping(file: LoadedFile, plan: ImportPlan)
    /// The user corrected the mapping and wants to see the diff again.
    func didConfirmImportMapping(file: LoadedFile, plan: ImportPlan)
    func didFinishImport()
    func dismissImport()
}
