//
//  ProjectionExplainerViewController.swift
//  Finova
//
//  Created by Arthur Rios on 07/08/26.
//

import UIKit

final class ProjectionExplainerViewController: UIViewController {

    private let contentView: ProjectionExplainerView
    private let viewModel: ProjectionExplainerViewModel
    private var visibilityObservation: ValueVisibilityObservation?

    init(contentView: ProjectionExplainerView, viewModel: ProjectionExplainerViewModel) {
        self.contentView = contentView
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = contentView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSheet()
        render()

        // The eye can be toggled from behind this sheet on iPad, and the sheet outlives a toggle on
        // iPhone if the user backgrounds and returns. Re-render rather than trusting the value read
        // at present time - the rule everywhere else on the dashboard.
        visibilityObservation = ValueVisibilityStore.shared.observe { [weak self] _ in
            self?.render()
        }
    }

    /// Medium and large, so the formula is readable without a drag but the history table can be
    /// expanded when a ledger has many categories. Matches the detents `CloudCleanupViewController`
    /// uses for the same reason.
    private func configureSheet() {
        guard let sheet = sheetPresentationController else { return }
        sheet.detents = [.medium(), .large()]
        sheet.prefersGrabberVisible = true
        sheet.preferredCornerRadius = CornerRadius.bottomSheet
    }

    private func render() {
        contentView.configure(
            title: viewModel.title,
            formulaHeader: viewModel.formulaHeader,
            formulaLines: viewModel.formulaLines,
            formulaNote: viewModel.formulaNote,
            historyHeader: viewModel.historyHeader,
            historyRows: viewModel.historyRows,
            historyEmptyText: viewModel.historyEmptyText,
            isValuesHidden: ValueVisibilityStore.shared.isHidden)
    }
}
