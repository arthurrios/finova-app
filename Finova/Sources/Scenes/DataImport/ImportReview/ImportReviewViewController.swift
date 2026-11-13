//
//  ImportReviewViewController.swift
//  Finova
//

import UIKit

final class ImportReviewViewController: UIViewController {

    private let contentView: ImportReviewView
    let viewModel: ImportReviewViewModel
    weak var flowDelegate: ImportFlowDelegate?

    private var sections: [ImportReviewSection] = []

    init(
        contentView: ImportReviewView,
        viewModel: ImportReviewViewModel,
        flowDelegate: ImportFlowDelegate?
    ) {
        self.contentView = contentView
        self.viewModel = viewModel
        self.flowDelegate = flowDelegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() { view = contentView }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "import.review.title".localized
        navigationItem.hidesBackButton = true

        contentView.delegate = self
        contentView.tableView.dataSource = self
        contentView.tableView.delegate = self
        contentView.tableView.register(ImportRowCell.self, forCellReuseIdentifier: ImportRowCell.identifier)

        bindViewModel()
        reload()

        // Started only now that the diff is on screen and complete. Nothing waits on it, and it
        // patches in one atomic update rather than mutating rows under the user's finger.
        viewModel.refineCategoriesInBackground(existing: TransactionRepository().fetchAllTransactions())
    }

    private func bindViewModel() {
        viewModel.onPlanUpdated = { [weak self] in self?.reload() }

        viewModel.onApplyProgress = { [weak self] done, total in
            self?.contentView.setState(.applying(done: done, total: total))
        }

        viewModel.onApplyFinished = { [weak self] batch in
            guard let self else { return }
            // A single-button acknowledgement, so not `showConfirmation` — there is nothing to
            // cancel once the rows are written.
            let alert = UIAlertController(
                title: "import.done.title".localized,
                message: String(format: "import.done.message".localized, batch.rowsInserted),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default) { _ in
                self.flowDelegate?.didFinishImport()
            })
            self.present(alert, animated: true)
        }

        viewModel.onError = { [weak self] message in
            self?.contentView.setState(.failed(message))
        }
    }

    private func reload() {
        sections = viewModel.sections
        contentView.tableView.reloadData()
        guard !viewModel.isApplying else { return }
        contentView.setState(.reviewing(
            summary: viewModel.summary,
            net: viewModel.netTotal,
            canApply: viewModel.canApply,
            warning: viewModel.warningMessage,
            needsSignDecision: !viewModel.plan.undecidedRows.isEmpty))
    }
}

// MARK: - ImportReviewViewDelegate

extension ImportReviewViewController: ImportReviewViewDelegate {

    func didTapApply() {
        let resolved = viewModel.plan.resolve(with: viewModel.overrides)
        showConfirmation(
            title: "import.confirm.title".localized,
            message: String(format: "import.confirm.message".localized, resolved.rows.count),
            okTitle: "import.confirm.ok".localized,
            onOk: { [weak self] in self?.viewModel.apply() })
    }

    func didTapCancel() {
        // Nothing has been written yet, but the user has done real work laying out the diff.
        showConfirmation(
            title: "import.discard.title".localized,
            message: "import.discard.message".localized,
            okTitle: "import.discard.ok".localized,
            onOk: { [weak self] in self?.flowDelegate?.dismissImport() })
    }

    func didTapResolveSigns(asWritten: Bool) {
        viewModel.resolveAllSigns(asWritten: asWritten)
    }
}

// MARK: - Table view

extension ImportReviewViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "\(sections[section].title) (\(sections[section].rows.count))"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        sections[section].footer
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ImportRowCell.identifier, for: indexPath) as? ImportRowCell else {
            return UITableViewCell()
        }
        let row = sections[indexPath.section].rows[indexPath.row]
        cell.configure(
            row: row,
            title: viewModel.title(for: row),
            category: viewModel.category(for: row),
            isIncluded: viewModel.isIncluded(row))

        cell.onToggleInclusion = { [weak self] in self?.viewModel.toggleInclusion(of: row) }
        cell.onTapCategory = { [weak self] in self?.presentCategoryPicker(for: row) }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].rows[indexPath.row]
        guard !row.disposition.isFailure else { return }

        if case .needsDecision(.ambiguousSign) = row.disposition {
            presentSignPicker(for: row)
            return
        }
        presentRowEditor(for: row)
    }

    // MARK: - Editors

    private func presentCategoryPicker(for row: ImportRow) {
        let sheet = UIAlertController(
            title: "import.review.category.title".localized, message: nil, preferredStyle: .actionSheet)
        let current = viewModel.category(for: row)

        for category in TransactionCategory.allCases.sorted(by: { $0.displayName < $1.displayName }) {
            let action = UIAlertAction(title: category.displayName, style: .default) { [weak self] _ in
                self?.viewModel.setCategory(category, for: row)
            }
            if category == current { action.setValue(true, forKey: "checked") }
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        presentAsSheetIfNeeded(sheet)
    }

    private func presentSignPicker(for row: ImportRow) {
        let sheet = UIAlertController(
            title: viewModel.title(for: row),
            message: "import.review.signPrompt".localized,
            preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(
            title: "transactionType.income".localized, style: .default) { [weak self] _ in
                self?.viewModel.setType(.income, for: row)
            })
        sheet.addAction(UIAlertAction(
            title: "transactionType.expense".localized, style: .default) { [weak self] _ in
                self?.viewModel.setType(.expense, for: row)
            })
        sheet.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        presentAsSheetIfNeeded(sheet)
    }

    private func presentRowEditor(for row: ImportRow) {
        let alert = UIAlertController(
            title: "import.review.edit.title".localized, message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] field in
            field.text = self?.title(forEditing: row)
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "alert.cancel".localized, style: .cancel))
        alert.addAction(UIAlertAction(title: "alert.ok".localized, style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text else { return }
            self?.viewModel.setTitle(text, for: row)
        })
        present(alert, animated: true)
    }

    private func title(forEditing row: ImportRow) -> String { viewModel.title(for: row) }

    /// Action sheets need an anchor on iPad or they crash on presentation.
    private func presentAsSheetIfNeeded(_ alert: UIAlertController) {
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(
                x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }
}
